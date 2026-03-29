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
  /// Plus med mente: enere i alt → mente-klip + skærm → tiere i alt → afslutning.
  addOnesSum,
  /// Kun visning under mente-klip (ingen input); derefter automatisk [addTensCount].
  addOnesDigit,
  addTensCount,
  addResultPraise,
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
        minusAnswer:
            widget.lesson.isAddition ? null : widget.lesson.expectedAnswer,
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

  Future<void> _startSubTensGuided() async {
    setState(() {
      _phase = _TutorPhase.subTens;
      _stepAnswerCtrl.clear();
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
      await _startAddOnesGuided();
    } else {
      await _startSubTensGuided();
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
      case _TutorPhase.addOnesSum:
        return 2;
      case _TutorPhase.addOnesDigit:
        return 1;
      case _TutorPhase.addTensCount:
      case _TutorPhase.subTens:
      case _TutorPhase.subOnes:
        return 2;
      case _TutorPhase.addResultPraise:
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

  Future<void> _onGuidedOk() async {
    if (_phase == _TutorPhase.addResultPraise) return;
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
          await _speakNejProevIgenWithAsset();
          return;
        }
        if (!mounted) return;
        setState(() {
          _phase = _TutorPhase.subOnes;
          _stepAnswerCtrl.clear();
        });
        _focusStepField();
        await _speakGuidedWithAsset('Hvor mange enere er der?');
      case _TutorPhase.subOnes:
        if (v != exp % 10) {
          await _speakNejProevIgenWithAsset();
          return;
        }
        await _stopTts();
        if (mounted) Navigator.pop(context, true);
      case _TutorPhase.intro:
      case _TutorPhase.addResultPraise:
        break;
    }
  }

  Future<void> _onAddResultOk() async {
    await _stopTts();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildPhaseContent(BuildContext context) {
    final lesson = widget.lesson;
    final exp = lesson.expectedAnswer;
    switch (_phase) {
      case _TutorPhase.intro:
        final w = lesson.screenWidgets;
        final body = w.length > 2 ? w.sublist(2) : w;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: body,
        );
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
        final tensVal = _tensTotal * 10;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mathTutorEquationHeader(lesson.promptLine),
            const SizedBox(height: 12),
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
            const SizedBox(height: 8),
            mathTutorCoinPileForNumber(context, tensVal, caption: null),
          ],
        );
      case _TutorPhase.addResultPraise:
        final completedEquation =
            '${lesson.operandLeft}${lesson.isAddition ? '+' : '-'}${lesson.operandRight}=$exp';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mathTutorEquationHeader(completedEquation),
            const SizedBox(height: 12),
            Text(
              'Sådan ser hele svaret ud:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            mathTutorCoinPileForNumber(context, exp, caption: null),
          ],
        );
      case _TutorPhase.subTens:
        final tensValue = (exp ~/ 10) * 10;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mathTutorEquationHeader(lesson.promptLine),
            const SizedBox(height: 12),
            Text(
              'Sådan ser tierne i svaret ud:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            mathTutorCoinPileForNumber(context, tensValue, caption: null),
          ],
        );
      case _TutorPhase.subOnes:
        final ones = exp % 10;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mathTutorEquationHeader(lesson.promptLine),
            const SizedBox(height: 12),
            Text(
              'Sådan ser enere i svaret ud:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            mathTutorCoinPileForNumber(context, ones, caption: null),
          ],
        );
    }
  }

  Widget _buildAnswerPanel(BuildContext context, {required bool useNumpad}) {
    const pad = EdgeInsets.fromLTRB(16, 10, 60, 14);
    final readOnly = useNumpad;
    final kbType =
        readOnly ? TextInputType.none : TextInputType.number;

    if (_phase == _TutorPhase.intro) {
      return Material(
        color: Colors.white,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: pad,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      widget.lesson.promptLine.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: Colors.grey.shade900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 4, 4),
                    child: Text(
                      '=',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B1B1B),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _mainAnswerCtrl,
                      focusNode: _mainAnswerFocus,
                      readOnly: readOnly,
                      showCursor: true,
                      keyboardType: kbType,
                      maxLength: 3,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      ],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
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
                child: _tutorRoundOkButton(
                  onPressed: _speaking || !_ttsReady
                      ? null
                      : () => unawaited(_onDirectOk()),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      widget.lesson.promptLine.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: Colors.grey.shade900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 4, 4),
                    child: Text(
                      '=',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B1B1B),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _stepAnswerCtrl,
                      focusNode: _stepFocus,
                      readOnly: readOnly,
                      enabled: !_speaking,
                      showCursor: true,
                      keyboardType: kbType,
                      maxLength: _tutorStepMaxDigits(),
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                        LengthLimitingTextInputFormatter(_tutorStepMaxDigits()),
                      ],
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
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

    if (_phase == _TutorPhase.addResultPraise) {
      return Material(
        color: Colors.white,
        child: SizedBox(
          height: 72,
          child: Stack(
            children: [
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
      return Material(
        color: Colors.white,
        child: Padding(
          padding: pad,
          child: const SizedBox.shrink(),
        ),
      );
    }

    final String hint;
    switch (_phase) {
      case _TutorPhase.addOnesSum:
        hint = '';
      case _TutorPhase.addOnesDigit:
        hint = '';
      case _TutorPhase.addTensCount:
        hint = 'Hvor mange tiere? (tæl guldmønterne ovenfor)';
      case _TutorPhase.subTens:
        hint = 'Hvor mange tiere er der? (tæl guldmønterne på 10)';
      case _TutorPhase.subOnes:
        hint = 'Hvor mange enere er der?';
      case _TutorPhase.intro:
      case _TutorPhase.addResultPraise:
        hint = '';
    }

    return Material(
      color: Colors.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: pad,
            child: TextField(
              controller: _stepAnswerCtrl,
              focusNode: _stepFocus,
              enabled: !_speaking,
              readOnly: readOnly,
              showCursor: true,
              keyboardType: kbType,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                LengthLimitingTextInputFormatter(_tutorStepMaxDigits()),
              ],
              decoration: InputDecoration(
                labelText: hint.isEmpty ? null : hint,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => unawaited(_onGuidedOk()),
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
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildPhaseContent(context),
                    ],
                  ),
                ),
              ),
            ),
            _buildAnswerPanel(context, useNumpad: useNumpad),
            if (showKeypad)
              KidMathNumericKeypad(
                onDigit: _tutorNumpadDigit,
                onBackspace: _tutorNumpadBackspace,
              ),
            SizedBox(height: safe.bottom),
          ],
        ),
      ),
    );
  }
}
