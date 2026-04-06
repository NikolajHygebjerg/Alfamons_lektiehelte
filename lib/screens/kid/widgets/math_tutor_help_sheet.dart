import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../../../services/alfamon_cloud_tts.dart';
import '../../../utils/math_tutor_lesson.dart';
import '../../../utils/math_tutor_prerecorded_intro.dart';
import '../../../widgets/tts_setup_intro_dialog.dart';
import '../kid_math_input_device.dart';
import 'kid_math_numeric_keypad.dart';

/// Pause mellem sætninger ved oplæsning (samme taletempo — mere luft).
const _kMathTutorPauseBetweenSentencesMs = 650;

/// Lydfiler hvor indtalen bruger «i alt» eller kortere navn — matcher stadig guiden.
const List<String> _kGuidedHvorMangeEnereIaltSammenAliases = [
  'hvor_mange_enere_er_der_i_alt_naar_du_lae_gger_de_to_tal_sammen',
];

const List<String> _kGuidedHvorMangeTiereAliases = [
  'hvor_mange_tiere',
];

bool _isMacDesktop() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

bool _languageSetOk(dynamic result) => result == 1 || result == true;

Future<void> _safeFlutterTtsStop(FlutterTts tts) async {
  try {
    await tts.stop();
  } on MissingPluginException {
    // fx Linux (flutter_tts har ingen implementation) eller plugin ikke indlæst.
  } catch (_) {}
}

/// Stemniveau til sortering: premium/forbedret før standard (Apple + Android).
int _ttsVoiceQualityRank(String? rawQuality) {
  final q = (rawQuality ?? '').toLowerCase().trim();
  if (q == 'premium' || q.contains('very high')) return 50;
  if (q == 'enhanced' || q == 'high') return 40;
  if (q == 'normal') return 30;
  if (q == 'default') return 20;
  if (q == 'low') return 10;
  if (q.contains('very low')) return 5;
  return 15;
}

/// Vælg den bedst tilgængelige danske systemstemme (ikke bare den første i listen).
Future<void> _applyBestDanishSystemVoice(FlutterTts tts) async {
  try {
    final dynamic voices = await tts.getVoices;
    if (voices is! List || voices.isEmpty) return;
    final candidates = <Map<String, String>>[];
    for (final raw in voices) {
      if (raw is! Map) continue;
      final localeFull = '${raw['locale'] ?? ''}'.trim();
      if (localeFull.isEmpty) continue;
      final localeLower = localeFull.toLowerCase();
      if (!localeLower.startsWith('da')) continue;
      final id = '${raw['identifier'] ?? ''}'.trim();
      final name = '${raw['name'] ?? ''}'.trim();
      // iOS/macOS: identifier; Android: name + locale (flutter_tts)
      if (id.isEmpty && (name.isEmpty)) continue;
      candidates.add({
        'identifier': id,
        'locale': localeFull,
        'quality': '${raw['quality'] ?? ''}',
        'name': name,
      });
    }
    if (candidates.isEmpty) return;
    candidates.sort((a, b) {
      final byQ = _ttsVoiceQualityRank(b['quality']).compareTo(
        _ttsVoiceQualityRank(a['quality']),
      );
      if (byQ != 0) return byQ;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    for (final c in candidates) {
      final id = c['identifier'] ?? '';
      final dynamic r;
      if (id.isNotEmpty) {
        r = await tts.setVoice({'identifier': id});
      } else {
        r = await tts.setVoice({
          'name': c['name']!,
          'locale': c['locale']!,
        });
      }
      if (_languageSetOk(r)) {
        debugPrint(
          'math_tutor TTS voice: ${c['name']} (${c['quality']})',
        );
        return;
      }
    }
  } catch (_) {}
}

Future<String> _pickDanishLanguage(FlutterTts tts) async {
  const candidates = ['da-DK', 'da_DK', 'da-dk', 'da'];
  try {
    final dynamic raw = await tts.getLanguages;
    if (raw is! List) return 'da-DK';
    final list = raw.map((e) => '$e').toList();
    for (final c in candidates) {
      for (final e in list) {
        if (e.toLowerCase() == c.toLowerCase()) return e;
      }
    }
    final fuzzy = list.where((e) => e.toLowerCase().startsWith('da')).toList();
    if (fuzzy.isNotEmpty) return fuzzy.first;
  } catch (_) {}
  return 'da-DK';
}

/// Langsommere end platform-default (AVSpeech/Android) — mindre «robot»-hastighed og hakket output.
Future<void> _applyComfortableSpeechRate(FlutterTts tts) async {
  try {
    final range = await tts.getSpeechRateValidRange;
    final span = range.normal - range.min;
    final slow = range.min + span * 0.38;
    await tts.setSpeechRate(slow.clamp(range.min, range.max));
  } catch (e, st) {
    debugPrint('math_tutor TTS speech rate: $e\n$st');
    try {
      await tts.setSpeechRate(_isMacDesktop() ? 0.36 : 0.26);
    } catch (_) {}
  }
}

/// Bundark med bamsen, mønter, tale og svar-trin. Returnerer `true` ved rigtigt endeligt svar.
Future<bool?> showMathTutorHelpSheet(
  BuildContext context,
  MathTutorLesson lesson,
) async {
  await TtsSetupIntro.showReminderIfNeeded(context);
  if (!context.mounted) return null;
  return showModalBottomSheet<bool?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MathTutorHelpSheetBody(lesson: lesson),
  );
}

enum _TutorPhase {
  intro,
  /// Minus med lån: mønt-trin 0 = oprindelige tal, 1 = efter veksling (under oplæsning).
  minusBorrowWalk,
  /// Minus med lån efter korrekt ener-svar: tier gennemstreget → tier-minus (før subTens).
  minusBorrowTensWalk,
  /// Plus med mente: enere i alt → mente-klip + skærm → tiere i alt → afslutning.
  addOnesSum,
  /// Kun visning under mente-klip (ingen input); derefter automatisk [addTensCount].
  addOnesDigit,
  addTensCount,
  addResultPraise,
  /// Minus: hele stykket med svar + ros efter korrekt tier-svar (med eller uden lån).
  minusBorrowFinalResult,
  /// Minus: tier i svar → ener i svar (uændret idé).
  subTens,
  subOnes,
}

class _MathTutorHelpSheetBody extends StatefulWidget {
  const _MathTutorHelpSheetBody({required this.lesson});

  final MathTutorLesson lesson;

  @override
  State<_MathTutorHelpSheetBody> createState() => _MathTutorHelpSheetBodyState();
}

List<String> _mathTutorTtsChunks(String text) {
  final t = text.trim();
  if (t.isEmpty) return [];
  final parts = t
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? [t] : parts;
}

String _mathTutorMenteOnesMid(int onesSum) {
  final d = onesSum % 10;
  return switch (d) {
    0 => 'Vi har 10 som vi lægger til tierne',
    1 => 'Vi gemmer én en og har 10 som vi lægger til tierne',
    _ => 'Vi gemmer de $d enere og har 10 som vi lægger til tierne',
  };
}

class _MathTutorHelpSheetBodyState extends State<_MathTutorHelpSheetBody> {
  late final FlutterTts _tts;
  late final AlfamonCloudTts _cloudTts;
  bool _speaking = false;
  /// Sand under flere [speak]-kald i træk, så completion-handler ikke sætter _speaking=false for tidligt.
  bool _multiPartSpeak = false;
  bool _ttsReady = false;
  /// Sand, når platformen ikke har flutter_tts (fx Linux) eller plugin mangler.
  bool _ttsChannelMissing = false;
  /// Starter intro-lyd én gang efter TTS-klargøring.
  bool _autoIntroScheduled = false;

  final AudioPlayer _assetClipPlayer = AudioPlayer();

  _TutorPhase _phase = _TutorPhase.intro;
  /// Minus: om vi brugte låne-mellemskridt (til korrekt tier-oplæsning bagefter).
  bool _minusUsedBorrow = false;
  /// 0 = To møntrækker (a, b); 1 = splittet minuend + andet tal.
  int _minusBorrowCoinStep = 0;
  /// Minus uden lån (subTens): antal **tier**-par fjernet ved tryk (fx 2−1).
  int _minusNoBorrowTensInteractiveRemoved = 0;
  /// Efter lån: antal enere på minuend-siden barnet har «trukket væk» ved tryk (subOnes).
  int _minusBorrowOnesInteractiveRemoved = 0;
  /// 0 = oprindelige tier med gennemstregning, 1 = tier efter lån − subtrahend tier.
  int _minusBorrowTensStep = 0;
  final _mainAnswerCtrl = TextEditingController();
  final _stepAnswerCtrl = TextEditingController();
  final _mainAnswerFocus = FocusNode();
  final _stepFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _cloudTts = AlfamonCloudTts();
    _tts = FlutterTts();
    _initTts();
  }

  /// Mønt-TTS når `m_*.mp3` mangler.
  Future<void> _playCoinTtsFallback(String text) async {
    final plain = mathTutorPlainTextForTts(text);
    if (plain.isEmpty) {
      return;
    }
    if (AlfamonCloudTts.hasSession) {
      final ok = await _cloudTts.speak(plain);
      if (ok) {
        return;
      }
    }
    if (!_ttsChannelMissing) {
      await _tts.speak(plain);
    }
  }

  Future<void> _initTts() async {
    final mac = _isMacDesktop();
    String? langHint;

    void registerHandlers() {
      _tts.setCompletionHandler(() {
        if (_multiPartSpeak) return;
        if (mounted) setState(() => _speaking = false);
      });
      _tts.setErrorHandler((dynamic msg) {
        if (mounted) {
          setState(() => _speaking = false);
          final text = msg is String ? msg : '$msg';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tale: $text')),
          );
        }
      });
    }

    try {
      try {
        // Sand: mere rolig afspilning og færre race ved stop/start end false på macOS.
        await _tts.awaitSpeakCompletion(true);
      } on MissingPluginException {
        _ttsChannelMissing = true;
        langHint =
            'Tale-plugin er ikke tilgængelig her. flutter_tts understøtter ikke '
            'Linux-desktop; på macOS/Windows/iOS/Android/web: stop appen helt, '
            'kør `flutter clean`, `flutter pub get`, og start forfra (fuld genstart).';
      } catch (_) {}

      if (_ttsChannelMissing) {
        return;
      }

      registerHandlers();

      try {
        final lang = await _pickDanishLanguage(_tts);
        var gotLang = _languageSetOk(await _tts.setLanguage(lang));
        if (!gotLang) {
          for (final fallback in ['da-DK', 'da']) {
            if (_languageSetOk(await _tts.setLanguage(fallback))) {
              gotLang = true;
              break;
            }
          }
        }
        await _applyBestDanishSystemVoice(_tts);
        if (!gotLang) {
          langHint = mac
              ? 'Tilføj dansk stemme: Systemindstillinger → Tilgængelighed → Læs og tal → Systemstemme / Administrer stemmer.'
              : 'Installér dansk tale på enheden (Indstillinger → Tale/sprog).';
        }
      } catch (e, st) {
        debugPrint('math_tutor TTS language/voice: $e\n$st');
        await _applyBestDanishSystemVoice(_tts);
        langHint = mac
            ? 'Tilføj dansk stemme: Systemindstillinger → Tilgængelighed → Læs og tal → Systemstemme / Administrer stemmer.'
            : 'Installér dansk tale på enheden (Indstillinger → Tale/sprog).';
      }

      try {
        await _tts.setVolume(1.0);
        await _tts.setPitch(1.0);
      } catch (e, st) {
        debugPrint('math_tutor TTS volume/pitch: $e\n$st');
      }

      await _applyComfortableSpeechRate(_tts);
    } on MissingPluginException {
      _ttsChannelMissing = true;
      langHint ??=
          'Tale-plugin er ikke tilgængelig (manglende native implementation). '
          'På Linux understøttes tale ikke; ellers: fuld genstart af appen eller '
          '`flutter clean` + ny build.';
    } catch (e, st) {
      debugPrint('math_tutor TTS init: $e\n$st');
      langHint ??= mac
          ? 'Kunne ikke klargøre tale. Tjek «Læs og tal», vælg systemstemme, eller genstart appen.'
          : 'Kunne ikke klargøre tale. Genstart appen.';
    } finally {
      if (mounted) {
        setState(() => _ttsReady = true);
        if (langHint != null) {
          debugPrint('math_tutor TTS: $langHint');
        }
        if (!_autoIntroScheduled) {
          _autoIntroScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_playTts());
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _mainAnswerCtrl.dispose();
    _stepAnswerCtrl.dispose();
    _mainAnswerFocus.dispose();
    _stepFocus.dispose();
    unawaited(_cloudTts.dispose());
    unawaited(_assetClipPlayer.dispose());
    unawaited(_safeFlutterTtsStop(_tts));
    super.dispose();
  }

  Future<void> _playTts() async {
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (!mounted) {
      return;
    }
    setState(() {
      _speaking = true;
      _multiPartSpeak = true;
    });
    try {
      final ok = await playMathTutorPrerecordedIntroFirstScreen(
        player: _assetClipPlayer,
        operandLeft: widget.lesson.operandLeft,
        operandRight: widget.lesson.operandRight,
        isAddition: widget.lesson.isAddition,
        playCoinTtsFallback: _playCoinTtsFallback,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kunne ikke afspille oplæsning. Tjek at alle lydfiler findes i '
              'assets/matematiktutor/ (se math_tutor_prerecorded_intro.dart).',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('math_tutor forhåndsoplæsning: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke afspille oplæsning ($e).'),
          ),
        );
      }
    } finally {
      _multiPartSpeak = false;
      if (mounted) {
        setState(() => _speaking = false);
      }
    }
  }

  Future<void> _stopTts() async {
    _multiPartSpeak = false;
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (mounted) setState(() => _speaking = false);
  }

  /// Lydfil hvis `assets/matematiktutor/<slug>.mp3` findes; ellers TTS (hvis muligt).
  Future<void> _speakGuidedWithAsset(
    String danishSentence, {
    List<String> basenameAliases = const [],
  }) async {
    if (danishSentence.trim().isEmpty) return;
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (!mounted) return;
    final ok = await mathTutorTryPlayGuidedPhraseAsset(
      player: _assetClipPlayer,
      danishSentence: danishSentence,
      basenameAliases: basenameAliases,
    );
    if (!ok && mounted) {
      if (_ttsChannelMissing && !AlfamonCloudTts.hasSession) return;
      await _speakLine(danishSentence);
    }
  }

  /// Forkert tal på guidet trin: `nej_det_er_ikke_rigtigt_proev_igen.mp3` først.
  Future<void> _speakNejProevIgenWithAsset() async {
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (!mounted) return;
    var ok = await mathTutorTryPlayNejIkkeRigtigtProevIgen(_assetClipPlayer);
    if (!ok && mounted) {
      ok = await mathTutorTryPlayGuidedPhraseAsset(
        player: _assetClipPlayer,
        danishSentence: 'Nej det er ikke rigtigt. Prøv igen.',
        basenameAliases: const [kGuidedNejIkkeRigtigtProevIgen],
      );
    }
    if (!ok && mounted) {
      if (_ttsChannelMissing && !AlfamonCloudTts.hasSession) return;
      await _speakLine('Nej det er ikke rigtigt, prøv igen.');
    }
  }

  Future<void> _speakGodtDerErEnere(int os) async {
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (!mounted) return;
    final ok = await mathTutorTryPlayGodtDerErEnere(
      player: _assetClipPlayer,
      enereCount: os,
    );
    if (!ok && mounted) {
      if (_ttsChannelMissing && !AlfamonCloudTts.hasSession) return;
      await _speakLine('Godt der er $os enere.');
    }
  }

  Future<void> _speakMenteOnesExplainWithClips(int onesSum) async {
    final prefix = 'Det giver $onesSum. ${_mathTutorMenteOnesMid(onesSum)}.';
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (!mounted) return;
    var okOpen = await mathTutorTryPlayMenteDetGiverOpening(
      player: _assetClipPlayer,
      onesSum: onesSum,
    );
    if (!okOpen && mounted) {
      okOpen = await mathTutorTryPlayGuidedPhraseAsset(
        player: _assetClipPlayer,
        danishSentence: prefix,
      );
    }
    if (!okOpen && mounted) {
      if (_ttsChannelMissing && !AlfamonCloudTts.hasSession) {
        // ingen åbning
      } else {
        await _speakLine(prefix);
      }
    }
  }

  Future<void> _goToAddTensCountAndAskTens() async {
    if (!mounted) return;
    setState(() {
      _phase = _TutorPhase.addTensCount;
      _stepAnswerCtrl.clear();
    });
    _focusStepField();
    await _speakGuidedWithAsset(
      'Hvor mange tiere er der?',
      basenameAliases: _kGuidedHvorMangeTiereAliases,
    );
  }

  Future<void> _speakGodtDetGiverAltsaa(int exp) async {
    await _cloudTts.stop();
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}
    await _safeFlutterTtsStop(_tts);
    if (!mounted) return;
    var ok = await mathTutorTryPlayGodtDetGiverAltsaa(
      player: _assetClipPlayer,
      expectedAnswer: exp,
    );
    if (!ok && mounted) {
      ok = await mathTutorTryPlayGuidedPhraseAsset(
        player: _assetClipPlayer,
        danishSentence: 'Godt det giver altså $exp.',
      );
    }
    if (!ok && mounted) {
      await _speakLine('Godt det giver altså $exp.');
    }
  }

  Future<void> _speakLine(String line) async {
    if (line.isEmpty) return;
    if (_ttsChannelMissing && !AlfamonCloudTts.hasSession) return;
    final bits = _mathTutorTtsChunks(line);
    for (var i = 0; i < bits.length; i++) {
      await _cloudTts.stop();
      await _safeFlutterTtsStop(_tts);
      if (!mounted) return;
      setState(() => _speaking = true);
      var ok = false;
      if (AlfamonCloudTts.hasSession) {
        ok = await _cloudTts.speak(bits[i]);
      }
      if (!ok && !_ttsChannelMissing) {
        try {
          await _tts.speak(bits[i]);
          ok = true;
        } catch (e, st) {
          debugPrint('math_tutor TTS line: $e\n$st');
        }
      }
      if (mounted) setState(() => _speaking = false);
      if (!ok) break;
      if (i < bits.length - 1) {
        await Future<void>.delayed(
          const Duration(milliseconds: _kMathTutorPauseBetweenSentencesMs),
        );
      }
    }
  }

  void _focusStepField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stepFocus.requestFocus();
    });
  }

  Future<void> _startAddOnesGuided() async {
    setState(() {
      _phase = _TutorPhase.addOnesSum;
      _stepAnswerCtrl.clear();
    });
    _focusStepField();
    await _speakGuidedWithAsset(
      'Hvor mange enere er der ialt, når du lægger de to tal sammen?',
      basenameAliases: _kGuidedHvorMangeEnereIaltSammenAliases,
    );
  }

  /// Plus: spring ener-trin over når ene-summen er 0 (fx 10+20); ellers er der enere at tælle.
  bool get _additionNeedsOnesStep =>
      widget.lesson.isAddition && _onesSum != 0;

  Future<void> _startAdditionGuidedFromIntroOrRetry() async {
    if (_additionNeedsOnesStep) {
      await _startAddOnesGuided();
    } else {
      await _goToAddTensCountAndAskTens();
    }
  }

  /// Minus efter intro / forkert svar: afspil energennemgang → (evt. svar enere) → tier-gennemgang → svar tiere.
  Future<void> _startMinusGuidedAfterIntroOrWrong() async {
    await _stopTts();
    if (!mounted) return;
    setState(() => _speaking = true);
    try {
      await _assetClipPlayer.stop();
    } catch (_) {}

    final lesson = widget.lesson;
    final exp = lesson.expectedAnswer;
    final a = lesson.operandLeft;
    final b = lesson.operandRight;

    final borrow = mathTutorMinusNeedsBorrowTenToOnes(a, b);
    _minusUsedBorrow = borrow;
    _minusBorrowCoinStep = 0;
    _minusBorrowOnesInteractiveRemoved = 0;
    _minusBorrowTensStep = 0;

    if (borrow) {
      setState(() {
        _phase = _TutorPhase.minusBorrowWalk;
        _minusBorrowCoinStep = 0;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final ok = await mathTutorTryPlayMinusBorrowOnesDetailedWalkthrough(
        player: _assetClipPlayer,
        operandLeft: a,
        operandRight: b,
        onVisualStep: (step) async {
          if (!mounted) return;
          setState(() => _minusBorrowCoinStep = step);
          if (step != 0) {
            await Future<void>.delayed(const Duration(milliseconds: 90));
          }
        },
      );
      if (!ok && mounted) {
        final ao = a % 10;
        final bo = b % 10;
        final adj = 10 + ao;
        await _speakLine(
          'Vi starter med enerne, det vil sige $ao minus $bo. '
          'Det kan vi ikke, for så bliver det et minus tal; vi må derfor låne en tier. '
          'Vi veksler en tier til ti enere. Så har vi $adj. '
          'Nu er det $adj enere minus $bo enere. Skriv svaret i boksen.',
        );
      }
    } else {
      if (exp % 10 != 0) {
        if (!mounted) return;
        setState(() {
          _speaking = true;
          _phase = _TutorPhase.subOnes;
          _stepAnswerCtrl.clear();
          _minusBorrowOnesInteractiveRemoved = 0;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      final okOpen = await mathTutorTryPlayMinusOnesNoBorrowViStarterOpening(
        player: _assetClipPlayer,
        operandLeft: a,
        operandRight: b,
      );
      if (!okOpen && mounted) {
        final ao = a % 10;
        final bo = b % 10;
        await _speakLine(
          'Vi starter med enerne, det vil sige $ao minus $bo.',
        );
      }
    }
    if (!mounted) return;

    if (exp % 10 != 0) {
      if (borrow) {
        if (!mounted) return;
        setState(() {
          _speaking = true;
          _phase = _TutorPhase.subOnes;
          _stepAnswerCtrl.clear();
          _minusBorrowOnesInteractiveRemoved = 0;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      final okTaps = await mathTutorTryPlayMinusBorrowInteractiveOnesInstruction(
        player: _assetClipPlayer,
        subtrahendOnes: b % 10,
      );
      if (!okTaps && mounted) {
        final bo = b % 10;
        await _speakLine(
          'Du skal altså trække $bo guldmønter fra. '
          'Tryk på $bo guldmønter for at fjerne dem og se resultatet.',
        );
      }
      if (!mounted) return;
      setState(() => _speaking = false);
      _focusStepField();
      return;
    }

    var ok = await mathTutorTryPlayMinusTensExplanation(
      player: _assetClipPlayer,
      operandLeft: a,
      operandRight: b,
      useBorrowTierPreamble: borrow,
    );
    if (!ok && mounted) {
      final at = borrow ? a ~/ 10 - 1 : a ~/ 10;
      await _speakLine(
        'Der er $at. Hvis du bruger ${b ~/ 10}, '
        'hvor mange tiere har du så tilbage?',
      );
    }
    if (!mounted) return;
    setState(() {
      _speaking = false;
      _phase = _TutorPhase.subTens;
      _stepAnswerCtrl.clear();
      _minusNoBorrowTensInteractiveRemoved = 0;
    });
    _focusStepField();
    await _speakGuidedWithAsset(
      'Hvor mange tiere er der?',
      basenameAliases: _kGuidedHvorMangeTiereAliases,
    );
  }

  Future<void> _onDirectOk() async {
    final raw = _mainAnswerCtrl.text.trim().replaceAll(' ', '');
    final v = int.tryParse(raw);
    if (v == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skriv et tal.')),
        );
      }
      return;
    }
    await _stopTts();
    if (v == widget.lesson.expectedAnswer) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    await _speakGuidedWithAsset('Nej det er ikke rigtigt.');
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (widget.lesson.isAddition) {
      await _startAdditionGuidedFromIntroOrRetry();
    } else {
      await _startMinusGuidedAfterIntroOrWrong();
    }
  }

  int get _onesSum =>
      (widget.lesson.operandLeft % 10) + (widget.lesson.operandRight % 10);

  int get _carry => _onesSum ~/ 10;

  int get _tensTotal =>
      (widget.lesson.operandLeft ~/ 10) +
      (widget.lesson.operandRight ~/ 10) +
      _carry;

  int _tutorStepMaxDigits() {
    switch (_phase) {
      case _TutorPhase.intro:
        return 3;
      case _TutorPhase.minusBorrowWalk:
      case _TutorPhase.minusBorrowTensWalk:
        return 1;
      case _TutorPhase.addOnesSum:
        return 2;
      case _TutorPhase.addOnesDigit:
        return 1;
      case _TutorPhase.addTensCount:
      case _TutorPhase.subTens:
      case _TutorPhase.subOnes:
        return 2;
      case _TutorPhase.addResultPraise:
      case _TutorPhase.minusBorrowFinalResult:
        return 3;
    }
  }

  bool _tutorShowsBottomKeypad(bool useNumpad) {
    if (!useNumpad) return false;
    return _phase == _TutorPhase.intro ||
        _phase == _TutorPhase.addOnesSum ||
        _phase == _TutorPhase.addTensCount ||
        _phase == _TutorPhase.subTens ||
        _phase == _TutorPhase.subOnes;
  }

  void _tutorNumpadDigit(int d) {
    if (!_ttsReady || _speaking) return;
    if (_phase == _TutorPhase.intro) {
      if (_mainAnswerCtrl.text.length >= 3) return;
      _mainAnswerCtrl.text += '$d';
    } else if (_phase == _TutorPhase.addOnesSum ||
        _phase == _TutorPhase.addTensCount ||
        _phase == _TutorPhase.subTens ||
        _phase == _TutorPhase.subOnes) {
      final maxD = _tutorStepMaxDigits();
      if (_stepAnswerCtrl.text.length >= maxD) return;
      _stepAnswerCtrl.text += '$d';
    }
    setState(() {});
  }

  void _tutorNumpadBackspace() {
    if (_phase == _TutorPhase.intro) {
      final t = _mainAnswerCtrl.text;
      if (t.isEmpty) return;
      _mainAnswerCtrl.text = t.substring(0, t.length - 1);
    } else if (_phase == _TutorPhase.addOnesSum ||
        _phase == _TutorPhase.addTensCount ||
        _phase == _TutorPhase.subTens ||
        _phase == _TutorPhase.subOnes) {
      final t = _stepAnswerCtrl.text;
      if (t.isEmpty) return;
      _stepAnswerCtrl.text = t.substring(0, t.length - 1);
    }
    setState(() {});
  }

  Widget _tutorRoundOkButton({required VoidCallback? onPressed}) {
    return Material(
      color: const Color(0xFF2B9348),
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.check, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  /// Lille rød «videre» (intro): springer til guidet flow uden fuldt svar.
  Widget _tutorVidereArrowButton({required VoidCallback? onPressed}) {
    return Material(
      color: const Color(0xFFE53935),
      borderRadius: BorderRadius.circular(22),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_forward, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Future<void> _onIntroVidere() async {
    if (_speaking || !_ttsReady) return;
    await _stopTts();
    if (!mounted) return;
    if (widget.lesson.isAddition) {
      await _startAdditionGuidedFromIntroOrRetry();
    } else {
      await _startMinusGuidedAfterIntroOrWrong();
    }
  }

  Future<void> _onGuidedOk() async {
    if (_phase == _TutorPhase.addResultPraise ||
        _phase == _TutorPhase.minusBorrowFinalResult) {
      return;
    }
    final raw = _stepAnswerCtrl.text.trim().replaceAll(' ', '');
    final v = int.tryParse(raw);
    if (v == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skriv et tal.')),
        );
      }
      return;
    }
    final exp = widget.lesson.expectedAnswer;
    final os = _onesSum;

    switch (_phase) {
      case _TutorPhase.addOnesSum:
        if (v != os) {
          await _speakNejProevIgenWithAsset();
          return;
        }
        if (os >= 10) {
          if (!mounted) return;
          setState(() {
            _phase = _TutorPhase.addOnesDigit;
            _stepAnswerCtrl.clear();
          });
          await _speakMenteOnesExplainWithClips(os);
          if (!mounted) return;
          await _goToAddTensCountAndAskTens();
        } else {
          await _speakGodtDerErEnere(os);
          if (!mounted) return;
          await _goToAddTensCountAndAskTens();
        }
      case _TutorPhase.addOnesDigit:
        break;
      case _TutorPhase.addTensCount:
        if (v != _tensTotal) {
          await _speakNejProevIgenWithAsset();
          return;
        }
        if (!mounted) return;
        setState(() => _phase = _TutorPhase.addResultPraise);
        await _speakGodtDetGiverAltsaa(exp);
        if (!mounted) return;
        await Future<void>.delayed(
          const Duration(milliseconds: _kMathTutorPauseBetweenSentencesMs),
        );
        if (!mounted) return;
        await _speakGuidedWithAsset('Godt gået.');
      case _TutorPhase.subTens:
        if (v != exp ~/ 10) {
          if (!widget.lesson.isAddition &&
              !_minusUsedBorrow &&
              widget.lesson.operandRight ~/ 10 > 0) {
            if (mounted) {
              setState(() => _minusNoBorrowTensInteractiveRemoved = 0);
            }
          }
          await _speakNejProevIgenWithAsset();
          return;
        }
        if (!mounted) return;
        setState(() {
          _speaking = true;
          _phase = _TutorPhase.minusBorrowFinalResult;
        });
        try {
          await _assetClipPlayer.stop();
        } catch (_) {}
        final okFinal = await mathTutorTryPlayMinusBorrowFinalResultPraise(
          player: _assetClipPlayer,
          expectedAnswer: exp,
        );
        if (!okFinal && mounted) {
          await _speakLine('Svaret er $exp. Godt gået.');
        }
        if (!mounted) return;
        setState(() => _speaking = false);
        return;
      case _TutorPhase.subOnes:
        if (v != exp % 10) {
          if (!widget.lesson.isAddition && mounted) {
            setState(() => _minusBorrowOnesInteractiveRemoved = 0);
          }
          await _speakNejProevIgenWithAsset();
          return;
        }
        if (!mounted) return;
        final a = widget.lesson.operandLeft;
        final b = widget.lesson.operandRight;
        if (_minusUsedBorrow) {
          setState(() {
            _speaking = true;
            _phase = _TutorPhase.minusBorrowTensWalk;
            _minusBorrowTensStep = 0;
          });
        }
        try {
          await _assetClipPlayer.stop();
        } catch (_) {}
        if (_minusUsedBorrow) {
          final okWalk = await mathTutorTryPlayMinusBorrowTensAfterOnesWalkthrough(
            player: _assetClipPlayer,
            operandLeft: a,
            operandRight: b,
            onVisualStep: (step) async {
              if (!mounted) return;
              setState(() => _minusBorrowTensStep = step);
              await Future<void>.delayed(const Duration(milliseconds: 90));
            },
          );
          if (!okWalk && mounted) {
            final ot = a ~/ 10;
            final nt = a ~/ 10 - 1;
            final bt = b ~/ 10;
            await _speakLine(
              'Der var $ot tiere, men vi brugte den ene, så nu er der kun $nt. '
              'Nu er det $nt minus $bt. Skriv svaret i boksen.',
            );
          }
        } else {
          if (!mounted) return;
          setState(() {
            _speaking = true;
            _phase = _TutorPhase.subTens;
            _stepAnswerCtrl.clear();
            _minusNoBorrowTensInteractiveRemoved = 0;
          });
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          try {
            await _assetClipPlayer.stop();
          } catch (_) {}
          final okOpen = await mathTutorTryPlayMinusNoBorrowTensAfterOnesOpening(
            player: _assetClipPlayer,
            operandLeft: a,
            operandRight: b,
          );
          if (!okOpen && mounted) {
            await _speakLine(
              'Så går vi til tierne. Der er ${a ~/ 10}. '
              'Det er ${a ~/ 10} minus ${b ~/ 10}.',
            );
          }
          final bt = b ~/ 10;
          if (bt > 0) {
            final okTaps =
                await mathTutorTryPlayMinusBorrowInteractiveOnesInstruction(
              player: _assetClipPlayer,
              subtrahendOnes: bt,
            );
            if (!okTaps && mounted) {
              await _speakLine(
                'Du skal altså trække $bt guldmønter fra. '
                'Tryk på $bt guldmønter for at fjerne dem og se resultatet.',
              );
            }
          }
          if (!mounted) return;
          setState(() => _speaking = false);
          _focusStepField();
          await _speakGuidedWithAsset(
            'Hvor mange tiere er der?',
            basenameAliases: _kGuidedHvorMangeTiereAliases,
          );
          return;
        }
        if (!mounted) return;
        setState(() {
          _speaking = false;
          _phase = _TutorPhase.subTens;
          _stepAnswerCtrl.clear();
          _minusNoBorrowTensInteractiveRemoved = 0;
        });
        _focusStepField();
        break;
      case _TutorPhase.intro:
      case _TutorPhase.minusBorrowWalk:
      case _TutorPhase.minusBorrowTensWalk:
      case _TutorPhase.addResultPraise:
      case _TutorPhase.minusBorrowFinalResult:
        break;
    }
  }

  Future<void> _onAddResultOk() async {
    await _stopTts();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildMinusBorrowWalkContent(BuildContext context) {
    final a = widget.lesson.operandLeft;
    final b = widget.lesson.operandRight;
    final ao = a % 10;
    final bo = b % 10;
    final adj = 10 + ao;
    switch (_minusBorrowCoinStep) {
      case 1:
        return mathTutorMinusBorrowTierAboveOnesBlock(
          context,
          minuendOnes: ao,
          subtrahendOnes: bo,
        );
      case 2:
        return mathTutorMinusBorrowTierEqualsTenOnesColumn(
          context,
          minuendOnes: ao,
          subtrahendOnes: bo,
        );
      case 3:
        return mathTutorMinusBorrowFinalOnesSubtract(
          context,
          minuendOnesAfterBorrow: adj,
          subtrahendOnes: bo,
        );
      case 0:
      default:
        return mathTutorMinusBorrowOnesEquationWithCoins(
          context,
          minuendOnes: ao,
          subtrahendOnes: bo,
        );
    }
  }

  Widget _buildMinusBorrowTensWalkContent(BuildContext context) {
    final a = widget.lesson.operandLeft;
    final b = widget.lesson.operandRight;
    final a0 = a ~/ 10;
    final a1 = a ~/ 10 - 1;
    final bt = b ~/ 10;
    switch (_minusBorrowTensStep) {
      case 1:
        return Align(
          alignment: Alignment.topCenter,
          child: mathTutorMinusBorrowTensEquationWithCoins(
            context,
            minuendTensAfterBorrow: a1,
            subtrahendTens: bt,
          ),
        );
      case 0:
      default:
        return Align(
          alignment: Alignment.topCenter,
          child: mathTutorMinusBorrowTensWithBorrowStruck(
            context,
            originalTenCount: a0,
          ),
        );
    }
  }

  Widget _buildPhaseContent(BuildContext context) {
    final lesson = widget.lesson;
    final exp = lesson.expectedAnswer;
    switch (_phase) {
      case _TutorPhase.intro:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: lesson.screenWidgets,
        );
      case _TutorPhase.minusBorrowWalk:
        return _buildMinusBorrowWalkContent(context);
      case _TutorPhase.minusBorrowTensWalk:
        return _buildMinusBorrowTensWalkContent(context);
      case _TutorPhase.addOnesSum:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: lesson.screenWidgets,
        );
      case _TutorPhase.addOnesDigit:
        if (lesson.isAddition) {
          return mathTutorAddOnesDigitMenteLayout(
            context,
            promptLine: lesson.promptLine,
            operandLeft: lesson.operandLeft,
            operandRight: lesson.operandRight,
            onesSum: _onesSum,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lesson.screenWidgets,
        );
      case _TutorPhase.addTensCount:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _tensTotal == 0
                  ? 'Der er ingen tiere:'
                  : _tensTotal == 1
                      ? 'Der er en tier:'
                      : 'Der er $_tensTotal tiere:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            if (_tensTotal > 0) ...[
              const SizedBox(height: 12),
              mathTutorTenCoinsRowOnly(context, _tensTotal),
            ],
          ],
        );
      case _TutorPhase.addResultPraise:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sådan ser hele svaret ud:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 12),
            mathTutorNumberEqualsCoinPile(context, exp),
          ],
        );
      case _TutorPhase.minusBorrowFinalResult:
        final a = lesson.operandLeft;
        final b = lesson.operandRight;
        final completed =
            '$a${lesson.isAddition ? '+' : '-'}$b=$exp';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                completed,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  color: Color(0xFF1B1B1B),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 16),
            mathTutorNumberEqualsCoinPile(context, exp),
          ],
        );
      case _TutorPhase.subTens:
        if (!lesson.isAddition && _minusUsedBorrow) {
          final a = lesson.operandLeft;
          final b = lesson.operandRight;
          return Align(
            alignment: Alignment.topCenter,
            child: mathTutorMinusBorrowTensEquationWithCoins(
              context,
              minuendTensAfterBorrow: a ~/ 10 - 1,
              subtrahendTens: b ~/ 10,
            ),
          );
        }
        if (!lesson.isAddition && !_minusUsedBorrow) {
          final at = lesson.operandLeft ~/ 10;
          final bt = lesson.operandRight ~/ 10;
          if (bt > 0) {
            return Align(
              alignment: Alignment.topCenter,
              child: mathTutorMinusBorrowTappableTensSubtract(
                context,
                minuendTens: at,
                subtrahendTens: bt,
                removedFromMinuend: _minusNoBorrowTensInteractiveRemoved,
                onTapRemoveOneFromMinuend: () {
                  if (_speaking ||
                      _minusNoBorrowTensInteractiveRemoved >= bt) {
                    return;
                  }
                  setState(() => _minusNoBorrowTensInteractiveRemoved++);
                },
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: mathTutorMinusBorrowTensEquationWithCoins(
              context,
              minuendTensAfterBorrow: at,
              subtrahendTens: bt,
            ),
          );
        }
        final tensDigit = exp ~/ 10;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tensDigit == 0
                  ? 'Der er ingen tier i svaret:'
                  : 'Sådan ser tierne i svaret ud:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            if (tensDigit > 0) ...[
              const SizedBox(height: 12),
              mathTutorTenCoinsRowOnly(context, tensDigit),
            ],
          ],
        );
      case _TutorPhase.subOnes:
        final ones = exp % 10;
        if (!lesson.isAddition && ones != 0) {
          final a = lesson.operandLeft;
          final b = lesson.operandRight;
          final ao = a % 10;
          final bo = b % 10;
          final leftOnes = _minusUsedBorrow ? 10 + ao : ao;
          return Align(
            alignment: Alignment.topCenter,
            child: mathTutorMinusBorrowTappableOnesSubtract(
              context,
              minuendOnesAfterBorrow: leftOnes,
              subtrahendOnes: bo,
              removedFromMinuend: _minusBorrowOnesInteractiveRemoved,
              onTapRemoveOneFromMinuend: () {
                if (_speaking || _minusBorrowOnesInteractiveRemoved >= bo) {
                  return;
                }
                setState(() => _minusBorrowOnesInteractiveRemoved++);
              },
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sådan ser enere i svaret ud:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 12),
            mathTutorNumberEqualsCoinPile(context, ones),
          ],
        );
    }
  }

  Widget _buildAnswerPanel(BuildContext context, {required bool useNumpad}) {
    const pad = EdgeInsets.fromLTRB(16, 10, 60, 14);
    const padIntro = EdgeInsets.fromLTRB(16, 10, 112, 14);
    /// Bundpanel: samme skriftstørrelse for tal og `=` (flugter visuelt).
    const eqPromptStyleIntro = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      height: 1.05,
      color: Color(0xFF1B1B1B),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    const eqEqualsStyleIntro = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: Color(0xFF1B1B1B),
    );
    const eqPromptStyleGuided = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.05,
      color: Color(0xFF1B1B1B),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    const eqEqualsStyleGuided = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      color: Color(0xFF1B1B1B),
    );
    final readOnly = useNumpad;
    final kbType =
        readOnly ? TextInputType.none : TextInputType.number;

    if (_phase == _TutorPhase.minusBorrowWalk ||
        _phase == _TutorPhase.minusBorrowTensWalk) {
      return Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Center(
            child: Text(
              'Lyt til forklaringen …',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
      );
    }

    if (_phase == _TutorPhase.intro) {
      return Material(
        color: Colors.white,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: padIntro,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      widget.lesson.promptLine.trim(),
                      textAlign: TextAlign.center,
                      style: eqPromptStyleIntro,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('=', style: eqEqualsStyleIntro),
                  ),
                  SizedBox(
                    width: 62,
                    child: TextField(
                      controller: _mainAnswerCtrl,
                      focusNode: _mainAnswerFocus,
                      readOnly: readOnly,
                      showCursor: true,
                      keyboardType: kbType,
                      maxLength: 3,
                      textAlign: TextAlign.center,
                      textAlignVertical: TextAlignVertical.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      ],
                      style: eqPromptStyleIntro.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => unawaited(_onDirectOk()),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tutorRoundOkButton(
                      onPressed: _speaking || !_ttsReady
                          ? null
                          : () => unawaited(_onDirectOk()),
                    ),
                    const SizedBox(width: 10),
                    _tutorVidereArrowButton(
                      onPressed: _speaking || !_ttsReady
                          ? null
                          : () => unawaited(_onIntroVidere()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_phase == _TutorPhase.addOnesSum) {
      return Material(
        color: Colors.white,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: pad,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      mathTutorOnesPromptLine(widget.lesson),
                      textAlign: TextAlign.center,
                      style: eqPromptStyleIntro,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('=', style: eqEqualsStyleIntro),
                  ),
                  SizedBox(
                    width: 62,
                    child: TextField(
                      controller: _stepAnswerCtrl,
                      focusNode: _stepFocus,
                      readOnly: readOnly,
                      enabled: !_speaking,
                      showCursor: true,
                      keyboardType: kbType,
                      maxLength: _tutorStepMaxDigits(),
                      textAlign: TextAlign.center,
                      textAlignVertical: TextAlignVertical.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                        LengthLimitingTextInputFormatter(_tutorStepMaxDigits()),
                      ],
                      style: eqPromptStyleIntro.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onSubmitted: (_) => unawaited(_onGuidedOk()),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: _tutorRoundOkButton(
                  onPressed: _speaking || !_ttsReady
                      ? null
                      : () => unawaited(_onGuidedOk()),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_phase == _TutorPhase.addResultPraise ||
        _phase == _TutorPhase.minusBorrowFinalResult) {
      final exp = widget.lesson.expectedAnswer;
      final completedEquation =
          '${widget.lesson.operandLeft}${widget.lesson.isAddition ? '+' : '-'}${widget.lesson.operandRight}=$exp';
      return Material(
        color: Colors.white,
        child: SizedBox(
          height: 96,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 64),
                  child: Center(
                    child: Text(
                      completedEquation,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        color: Color(0xFF1B1B1B),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _tutorRoundOkButton(
                    onPressed: _speaking || !_ttsReady
                        ? null
                        : () => unawaited(_onAddResultOk()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_phase == _TutorPhase.addOnesDigit) {
      final line = mathTutorOnesPromptLine(widget.lesson);
      return Material(
        color: Colors.white,
        child: Padding(
          padding: pad,
          child: Center(
            child: Text(
              '$line =',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: Color(0xFF1B1B1B),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
    }

    final guidedEquationLeft = () {
      if (_phase == _TutorPhase.subTens &&
          !widget.lesson.isAddition &&
          _minusUsedBorrow) {
        return '${widget.lesson.operandLeft ~/ 10 - 1}-'
            '${widget.lesson.operandRight ~/ 10}';
      }
      if (_phase == _TutorPhase.subTens &&
          !widget.lesson.isAddition &&
          !_minusUsedBorrow) {
        return '${widget.lesson.operandLeft ~/ 10}-'
            '${widget.lesson.operandRight ~/ 10}';
      }
      if (_phase == _TutorPhase.subOnes && !widget.lesson.isAddition) {
        return mathTutorOnesPromptLine(widget.lesson);
      }
      return widget.lesson.promptLine.trim();
    }();

    return Material(
      color: Colors.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: pad,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    guidedEquationLeft,
                    textAlign: TextAlign.center,
                    style: eqPromptStyleGuided,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('=', style: eqEqualsStyleGuided),
                ),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _stepAnswerCtrl,
                    focusNode: _stepFocus,
                    enabled: !_speaking,
                    readOnly: readOnly,
                    showCursor: true,
                    keyboardType: kbType,
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      LengthLimitingTextInputFormatter(_tutorStepMaxDigits()),
                    ],
                    style: eqPromptStyleGuided.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => unawaited(_onGuidedOk()),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _tutorRoundOkButton(
                onPressed: _speaking || !_ttsReady
                    ? null
                    : () => unawaited(_onGuidedOk()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final useNumpad = kidUseInAppNumericKeypad();
    final showKeypad = _tutorShowsBottomKeypad(useNumpad);
    return Padding(
      padding: EdgeInsets.only(top: safe.top + 6, bottom: 0),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - safe.top - 8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: Offset(0, -4),
              color: Colors.black26,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
              child: Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: 'Luk',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await _stopTts();
                      if (context.mounted) Navigator.pop(context, false);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: LayoutBuilder(
                  builder: (context, c) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildPhaseContent(context),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildAnswerPanel(context, useNumpad: useNumpad),
            if (showKeypad)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: KidMathNumericKeypad(
                  onDigit: _tutorNumpadDigit,
                  onBackspace: _tutorNumpadBackspace,
                ),
              ),
            SizedBox(height: safe.bottom),
          ],
        ),
      ),
    );
  }
}
