import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'math_tutor_lesson.dart';

/// Forhåndsindspillet matematiktutor — første skærm.
///
/// **Sætninger** som lydfiler: hele den talte tekst, ord med `_`, små bogstaver,
/// æøå som ae/oe/aa — genereres med [mathTutorAudioFilenameSlug].
/// Der prøves også ældre alias (fx `1_1`, `11`, `m_14`).
///
/// Se de faste danske strenge i [kIntroOpgavenEr] m.fl.
const String kMathTutorAudioDir = 'assets/matematiktutor';
const String kMathTutorAudioExt = '.mp3';

const String kIntroOpgavenEr = 'Opgaven er';
const String kIntroDetFoersteTalEr = 'Det første tal er';
const String kIntroDetAndetTalEr = 'Det andet tal er';
const String kIntroKanDuSelv = 'Kan du selv regne ud hvad svaret er skal du skrive '
    'det i feltet herunder. Hvis ikke, kan du trykke videre.';

/// Primært lydfilnavn (uden `.mp3`) for [kIntroKanDuSelv] — matcher [mathTutorAudioFilenameSlug].
const String kIntroKanDuSelvAudioBasename =
    'kan_du_selv_regne_ud_hvad_svaret_er_skal_du_skrive_det_i_feltet_herunder_hvis_ikke_kan_du_trykke_videre';

const String kIntroSvaretEr = 'Svaret er';

/// Mønt 11–19 (foretrukket): `det_svarer_til_en_guldmoent_paa_ti_og` → ener-ciffer → `guldmoenter_paa_en` (ellers `enere`).
/// I intro: `det_foerste_tal_er` / `det_andet_tal_er` + heltal afspilles før mønt-kæden.
/// Alternativ: det_svarer_til → en/1 → guldmoent → … → enere.
/// Tier 2–8: `det_svarer_til_{to…otte}_guldmoenter_paa_ti` (+ valgfri `guldmoenter_paa_en` ved én en) → ener → `enere`.
const String kCoinDetSvarerTil = 'det_svarer_til';
const String kCoinGuldmoent = 'guldmoent';
/// Hvis `guldmoent.mp3` mangler, kan dette klip bruges i stedet («… guldmønt på ti og») — da udelades ekstra `paa_ti_og`.
const String kCoinGuldmoentPaaTiOg = 'guldmoent_paa_ti_og';
/// Ét klip: «Det svarer til en guldmønt på ti og» — derefter ener-ciffer + `enere`.
const String kCoinDetSvarerTilEnGuldmoentPaaTiOg =
    'det_svarer_til_en_guldmoent_paa_ti_og';
/// Valgfrit **ét** klip for «Det svarer til en guldmønt.» uden «på ti og».
const String kCoinDetSvarerTilEnGuldmoent = 'det_svarer_til_en_guldmoent';
/// Valgfri bro før ener-ciffer **1** efter flere tier (`det_svarer_til_*_guldmoenter_paa_ti`).
const String kCoinGuldmoenterPaaEn = 'guldmoenter_paa_en';
/// Valgfrit mellem guldmønt og enere-ciffer («på ti og»).
const String kCoinPaaTiOg = 'paa_ti_og';
/// **10** kr kun tier: «Det er en guldmønt på ti.»
const String kCoinDetErEnGuldmoentPaaTi = 'det_er_en_guldmoent_paa_ti';

List<String> _coinGuldmoentClipCandidates() => [
      kCoinGuldmoent,
      kCoinGuldmoentPaaTiOg,
    ];
const String kCoinEnereWord = 'enere';

/// Guidet trin: «Godt det giver altså» derefter svar-tal.
const String kGuidedGodtDetGiverAltsaa = 'godt_det_giver_altsaa';

/// Forkert svar på guidet trin: `nej_det_er_ikke_rigtigt_proev_igen.mp3`.
const String kGuidedNejIkkeRigtigtProevIgen = 'nej_det_er_ikke_rigtigt_proev_igen';

/// Forkert svar uden matematikhjælp: `oev_proev_igen.mp3` (kort «øv, prøv igen»).
const String kOevProevIgen = 'oev_proev_igen';

/// Ord-klip (ét ord i filnavnet).
const String kWordSkriv = 'skriv';
const String kWordEn = 'en';
/// Mellem talsprog dele, fx *fem* **og** *tyve* (25).
const String kWordOg = 'og';

/// Mente: «Det giver …» + midt (10 / 11 / 12–18) — flere klip for 12–18.
const String kMenteDetGiver = 'det_giver';
const String kMenteViGemmerDe = 'vi_gemmer_de';
/// «Vi har 10 som vi lægger til tierne» (kun **ene-sum 10**).
const String kMenteViHar10 = 'vi_har_10_som_vi_lae_gger_til_tierne';
/// «Vi gemmer én en» derefter [kMenteOgHar10] (**ene-sum 11**).
const String kMenteViGemmerEnEn = 'vi_gemmer_en_en';
/// «og har 10 som vi lægger til tierne» (**ene-sum 11** og **12–18**).
const String kMenteOgHar10 = 'og_har_10_som_vi_lae_gger_til_tierne';

/// Kort pause mellem mønt-/mente-/intro-kæder (ikke inde i sammensatte tal — der bruges gapless concat).
const Duration kMathTutorNumberToCoinPause = Duration(milliseconds: 28);

String mathTutorPrerecordedAssetPath(String basenameWithoutExt) =>
    '$kMathTutorAudioDir/$basenameWithoutExt$kMathTutorAudioExt';

/// Finder rigtig asset-sti for et **basename uden endelse** (inkl. almindelige fejl:
/// `.mp3.mp3`, mellemrum før `.mp3` som i `…_og .mp3`). Returnerer `null` hvis intet matcher.
Future<String?> mathTutorResolvePrerecordedPath(String basenameWithoutExt) async {
  if (basenameWithoutExt.isEmpty) {
    return null;
  }
  final t = basenameWithoutExt.trim();
  final stems = <String>{
    basenameWithoutExt,
    t,
    '$t ',
  };
  for (final stem in stems) {
    if (stem.isEmpty) {
      continue;
    }
    final pMp3 = '$kMathTutorAudioDir/$stem.mp3';
    try {
      await rootBundle.load(pMp3);
      return pMp3;
    } catch (_) {}
    final pDouble = '$kMathTutorAudioDir/$stem.mp3.mp3';
    try {
      await rootBundle.load(pDouble);
      return pDouble;
    } catch (_) {}
  }
  return null;
}

Future<bool> mathTutorPrerecordedAssetExists(String assetPath) async {
  try {
    await rootBundle.load(assetPath);
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> _firstExistingBasename(List<String> candidates) async {
  for (final c in candidates) {
    if (c.isEmpty) {
      continue;
    }
    if (await mathTutorResolvePrerecordedPath(c) != null) {
      return c;
    }
  }
  return null;
}

Future<void> _playBasename(AudioPlayer player, String b) async {
  final path = await mathTutorResolvePrerecordedPath(b);
  if (path == null) {
    throw StateError('Matematiktutor: mangler lydfil for: $b');
  }
  await player.setAudioSource(
    AudioSource.asset(path),
    preload: true,
  );
  final done = player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .first;
  await player.play();
  await done.timeout(const Duration(minutes: 2));
}

Future<void> _playFirstOf(
  AudioPlayer player,
  List<String> candidates,
) async {
  final b = await _firstExistingBasename(candidates);
  if (b == null) {
    throw StateError(
      'Matematiktutor: mangler lydfil for: ${candidates.join(' | ')}',
    );
  }
  await _playBasename(player, b);
}

/// Ét klip pr. heltal (korte navne).
String? mathTutorSingleNumberBasename(int n) {
  if (n < 0 || n > 100) {
    return null;
  }
  if (n == 0) {
    return '0';
  }
  if (n <= 9) {
    return '$n';
  }
  if (n <= 20) {
    return '$n';
  }
  if (n == 100) {
    return '100';
  }
  if (n % 10 == 0) {
    return '$n';
  }
  return null;
}

List<String> mathTutorNumberPlayBasenames(int n) {
  if (n < 0 || n > 100) {
    return [];
  }
  final single = mathTutorSingleNumberBasename(n);
  if (single != null) {
    return [single];
  }
  final ones = n % 10;
  final tens = (n ~/ 10) * 10;
  final o = mathTutorSingleNumberBasename(ones);
  final t = mathTutorSingleNumberBasename(tens);
  if (o == null || t == null) {
    return [];
  }
  return [o, t];
}

List<String> _digitClipCandidates(String basename) {
  if (basename == '100') {
    return ['100', '1_100'];
  }
  if (basename == '1') {
    // «En» (som i «en og tyve», «… enere»), ikke nødvendigvis cifferet «1».
    return [kWordEn, '1'];
  }
  return [basename];
}

Future<void> _playNumberClips(AudioPlayer player, int n) async {
  final parts = mathTutorNumberPlayBasenames(n);
  if (parts.isEmpty) {
    return;
  }
  if (parts.length == 1) {
    await _playFirstOf(player, _digitClipCandidates(parts[0]));
    return;
  }
  final sources = <AudioSource>[];
  for (var i = 0; i < parts.length; i++) {
    final found = await _firstExistingBasename(_digitClipCandidates(parts[i]));
    if (found == null) {
      throw StateError(
        'Matematiktutor tal: mangler lydfil for del «${parts[i]}» '
        'i ${parts.join('+')}',
      );
    }
    final pathA = await mathTutorResolvePrerecordedPath(found);
    if (pathA == null) {
      throw StateError('Matematiktutor tal: kunne ikke resolve «$found»');
    }
    sources.add(AudioSource.asset(pathA));
    if (i < parts.length - 1) {
      final ogB = await _firstExistingBasename([kWordOg]);
      if (ogB != null) {
        final pathOg = await mathTutorResolvePrerecordedPath(ogB);
        if (pathOg != null) {
          sources.add(AudioSource.asset(pathOg));
        }
      }
    }
  }
  await player.setAudioSource(
    ConcatenatingAudioSource(children: sources),
    preload: true,
  );
  final done = player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .first;
  await player.play();
  await done.timeout(const Duration(minutes: 2));
}

String _coinSentenceSlug(int value) =>
    mathTutorAudioFilenameSlug(mathTutorTtsDescribeCoinsForNumber(value));

List<String> _coin11to19OpeningCombinedCandidates() => [
      kCoinDetSvarerTilEnGuldmoentPaaTiOg,
      mathTutorAudioFilenameSlug('Det svarer til en guldmønt på ti og'),
      kCoinDetSvarerTilEnGuldmoent,
      mathTutorAudioFilenameSlug('Det svarer til en guldmønt'),
      mathTutorAudioFilenameSlug('Det svarer til en guldmønt.'),
    ];

bool _coin11to19OpeningSkipsExtraPaaTiOgBridge(String basename) {
  if (basename == kCoinDetSvarerTilEnGuldmoentPaaTiOg) {
    return true;
  }
  return basename.contains('paa_ti_og');
}

/// Åbning til den korte 11–19-møntkæde (slug varianter matcher fil uden mellemrum i navnet).
List<String> _coin11to19FluentOpeningCandidates() => [
      kCoinDetSvarerTilEnGuldmoentPaaTiOg,
      mathTutorAudioFilenameSlug('Det svarer til en guldmønt på ti og'),
      mathTutorAudioFilenameSlug('Det svarer til en guldmønt på ti og.'),
    ];

Future<bool> _coin11to19FluentChainPresent(int value) async {
  if (value < 11 || value > 19) {
    return false;
  }
  if (await _firstExistingBasename(_coin11to19FluentOpeningCandidates()) ==
      null) {
    return false;
  }
  final ones = value % 10;
  for (final part in mathTutorNumberPlayBasenames(ones)) {
    if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
      return false;
    }
  }
  if (await _firstExistingBasename([kCoinGuldmoenterPaaEn, kCoinEnereWord]) ==
      null) {
    return false;
  }
  return true;
}

Future<void> _playCoin11to19FluentChain(AudioPlayer player, int value) async {
  final ones = value % 10;
  await _playFirstOf(player, _coin11to19FluentOpeningCandidates());
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, ones);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playFirstOf(player, [kCoinGuldmoenterPaaEn, kCoinEnereWord]);
}

/// `det_svarer_til_to_guldmoenter_paa_ti` … `det_svarer_til_otte_guldmoenter_paa_ti` (tier 2–8).
String? _coinMultiTenOpeningBasename(int tens) {
  final w = mathTutorDanishTensCountWord(tens);
  if (w == null || tens < 2 || tens > 8) {
    return null;
  }
  return 'det_svarer_til_${w}_guldmoenter_paa_ti';
}

Future<bool> _coinMultiTenExactOpeningPresent(int tens) async {
  final b = _coinMultiTenOpeningBasename(tens);
  if (b == null) {
    return false;
  }
  return await _firstExistingBasename([b]) != null;
}

Future<void> _playCoinMultiTenExactOpening(
  AudioPlayer player,
  int tens,
) async {
  final b = _coinMultiTenOpeningBasename(tens);
  if (b == null) {
    throw StateError('Matematiktutor: ingen tier-åbning for $tens');
  }
  await _playFirstOf(player, [b]);
}

Future<bool> _coinMultiTenWithOnesAssetsPresent(int tens, int ones) async {
  if (tens < 2 || tens > 8 || ones < 1 || ones > 9) {
    return false;
  }
  final open = _coinMultiTenOpeningBasename(tens);
  if (open == null || await _firstExistingBasename([open]) == null) {
    return false;
  }
  if (await _firstExistingBasename([kCoinEnereWord]) == null) {
    return false;
  }
  for (final part in mathTutorNumberPlayBasenames(ones)) {
    if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
      return false;
    }
  }
  return true;
}

Future<void> _playCoinMultiTenWithOnesComposite(
  AudioPlayer player,
  int value,
) async {
  final tens = value ~/ 10;
  final ones = value % 10;
  final open = _coinMultiTenOpeningBasename(tens)!;
  await _playFirstOf(player, [open]);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  final paaEn = await _firstExistingBasename([kCoinGuldmoenterPaaEn]);
  if (paaEn != null && ones == 1) {
    await _playBasename(player, paaEn);
    await Future<void>.delayed(kMathTutorNumberToCoinPause);
  }
  await _playNumberClips(player, ones);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playFirstOf(player, [kCoinEnereWord]);
}

/// «en» som ord eller som cifferet 1 (mange mapper har kun `1.mp3`).
Future<String?> _coinWordEnOrDigitOneBasename() =>
    _firstExistingBasename([kWordEn, '1']);

/// Legacy `m_01` … `m_100`, `m_00`.
String _coinLegacyBasename(int n) {
  if (n == 0) {
    return 'm_00';
  }
  if (n >= 1 && n <= 9) {
    return 'm_0$n';
  }
  if (n >= 10 && n <= 99) {
    return 'm_$n';
  }
  if (n == 100) {
    return 'm_100';
  }
  return 'm_00';
}

Future<bool> _coin11to19SplitOpeningPresent() async {
  if (await _firstExistingBasename([kCoinDetSvarerTil]) == null) {
    return false;
  }
  if (await _coinWordEnOrDigitOneBasename() == null) {
    return false;
  }
  if (await _firstExistingBasename(_coinGuldmoentClipCandidates()) == null) {
    return false;
  }
  return true;
}

Future<bool> _coin11to19OpeningPresent() async {
  if (await _coin11to19SplitOpeningPresent()) {
    return true;
  }
  return await _firstExistingBasename(_coin11to19OpeningCombinedCandidates()) !=
      null;
}

Future<bool> _coinComposite11To19AssetsPresent() async {
  if (await _firstExistingBasename([kCoinEnereWord]) == null) {
    return false;
  }
  return _coin11to19OpeningPresent();
}

Future<void> _playCoin11To19Composite(AudioPlayer player, int value) async {
  final ones = value % 10;
  final useSplit = await _coin11to19SplitOpeningPresent();
  final openingOneFile =
      await _firstExistingBasename(_coin11to19OpeningCombinedCandidates());
  var skipExtraPaaTiOg = false;
  if (useSplit) {
    await _playFirstOf(player, [kCoinDetSvarerTil]);
    await Future<void>.delayed(kMathTutorNumberToCoinPause);
    final enOr1 = await _coinWordEnOrDigitOneBasename();
    if (enOr1 == null) {
      throw StateError('Matematiktutor mønt 11–19: mangler en/1 klip');
    }
    await _playBasename(player, enOr1);
    await Future<void>.delayed(kMathTutorNumberToCoinPause);
    final guld = await _firstExistingBasename(_coinGuldmoentClipCandidates());
    if (guld == null) {
      throw StateError(
        'Matematiktutor mønt 11–19: mangler guldmoent eller guldmoent_paa_ti_og',
      );
    }
    await _playBasename(player, guld);
    skipExtraPaaTiOg = guld == kCoinGuldmoentPaaTiOg;
  } else if (openingOneFile != null) {
    await _playBasename(player, openingOneFile);
    skipExtraPaaTiOg = _coin11to19OpeningSkipsExtraPaaTiOgBridge(openingOneFile);
  } else {
    throw StateError(
      'Matematiktutor mønt 11–19: mangler åbning (tre klip eller ét kombineret)',
    );
  }
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  if (!skipExtraPaaTiOg) {
    final bridge = await _firstExistingBasename([kCoinPaaTiOg]);
    if (bridge != null) {
      await _playBasename(player, bridge);
      await Future<void>.delayed(kMathTutorNumberToCoinPause);
    }
  }
  await _playNumberClips(player, ones);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playFirstOf(player, [kCoinEnereWord]);
}

Future<void> _playCoinClipOrTts({
  required AudioPlayer player,
  required int value,
  required Future<void> Function(String text) playCoinTtsFallback,
}) async {
  final tens = value ~/ 10;
  final ones = value % 10;

  if (value >= 11 && value <= 19) {
    if (await _coin11to19FluentChainPresent(value)) {
      await _playCoin11to19FluentChain(player, value);
      return;
    }
    if (await _coinComposite11To19AssetsPresent()) {
      await _playCoin11To19Composite(player, value);
      return;
    }
  }

  if (tens >= 2 && tens <= 8 && ones == 0) {
    if (await _coinMultiTenExactOpeningPresent(tens)) {
      await _playCoinMultiTenExactOpening(player, tens);
      return;
    }
  }

  if (tens >= 2 &&
      tens <= 8 &&
      ones >= 1 &&
      await _coinMultiTenWithOnesAssetsPresent(tens, ones)) {
    await _playCoinMultiTenWithOnesComposite(player, value);
    return;
  }

  if (value == 10) {
    final b10 = await _firstExistingBasename([
      kCoinDetErEnGuldmoentPaaTi,
      mathTutorAudioFilenameSlug('Det er en guldmønt på ti.'),
      mathTutorAudioFilenameSlug('Det er en guldmønt på ti'),
    ]);
    if (b10 != null) {
      await _playBasename(player, b10);
      return;
    }
  }

  final slug = _coinSentenceSlug(value);
  final candidates = <String>[
    if (slug.isNotEmpty) slug,
    _coinLegacyBasename(value),
  ];
  final b = await _firstExistingBasename(candidates);
  if (b != null) {
    await _playBasename(player, b);
  } else {
    await playCoinTtsFallback(
      mathTutorPlainTextForTts(mathTutorTtsDescribeCoinsForNumber(value)),
    );
  }
}

List<String> _opgavenErFiles() => [
      mathTutorAudioFilenameSlug(kIntroOpgavenEr),
      '1_1',
    ];

List<String> _detFoersteTalErFiles() => [
      mathTutorAudioFilenameSlug(kIntroDetFoersteTalEr),
      '1_2',
    ];

List<String> _detAndetTalErFiles() => [
      mathTutorAudioFilenameSlug(kIntroDetAndetTalEr),
      '1_3',
    ];

List<String> _kanDuSelvFiles() => [
      kIntroKanDuSelvAudioBasename,
      mathTutorAudioFilenameSlug(kIntroKanDuSelv),
      '1_4',
    ];

List<String> _plusFiles() => [
      'plus',
      'Plus',
      mathTutorAudioFilenameSlug('plus'),
    ];

List<String> _minusFiles() => [
      'minus',
      'Minus',
      mathTutorAudioFilenameSlug('minus'),
    ];

List<String> _svaretErFiles() => [
      mathTutorAudioFilenameSlug(kIntroSvaretEr),
      'Svaret_er',
      'svaret_er',
    ];

Future<bool> _introRequiredAssetsPresent({
  required int a,
  required int b,
  required bool isAddition,
  int? minusAnswer,
}) async {
  if (await _firstExistingBasename(_opgavenErFiles()) == null) {
    return false;
  }
  if (await _firstExistingBasename(isAddition ? _plusFiles() : _minusFiles()) ==
      null) {
    return false;
  }
  if (await _firstExistingBasename(_detFoersteTalErFiles()) == null) {
    return false;
  }
  if (await _firstExistingBasename(_detAndetTalErFiles()) == null) {
    return false;
  }
  if (await _firstExistingBasename(_kanDuSelvFiles()) == null) {
    return false;
  }
  for (final n in [a, b]) {
    for (final part in mathTutorNumberPlayBasenames(n)) {
      if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
        return false;
      }
    }
  }
  if (!isAddition) {
    final ans = minusAnswer;
    if (ans == null) {
      return false;
    }
    if (await _firstExistingBasename(_svaretErFiles()) == null) {
      return false;
    }
    for (final part in mathTutorNumberPlayBasenames(ans)) {
      if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
        return false;
      }
    }
  }
  return true;
}

Future<bool> playMathTutorPrerecordedIntroFirstScreen({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  required bool isAddition,
  int? minusAnswer,
  required Future<void> Function(String text) playCoinTtsFallback,
}) async {
  final a = operandLeft;
  final b = operandRight;
  if (a < 0 || a > 100 || b < 0 || b > 100) {
    return false;
  }
  if (!isAddition) {
    final ans = minusAnswer;
    if (ans == null || ans < 0 || ans > 100) {
      return false;
    }
  }

  if (!await _introRequiredAssetsPresent(
    a: a,
    b: b,
    isAddition: isAddition,
    minusAnswer: minusAnswer,
  )) {
    return false;
  }

  await _playFirstOf(player, _opgavenErFiles());
  await _playNumberClips(player, a);
  await _playFirstOf(player, isAddition ? _plusFiles() : _minusFiles());
  await _playNumberClips(player, b);

  await _playFirstOf(player, _detFoersteTalErFiles());
  await _playNumberClips(player, a);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playCoinClipOrTts(
    player: player,
    value: a,
    playCoinTtsFallback: playCoinTtsFallback,
  );

  await _playFirstOf(player, _detAndetTalErFiles());
  await _playNumberClips(player, b);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playCoinClipOrTts(
    player: player,
    value: b,
    playCoinTtsFallback: playCoinTtsFallback,
  );

  await _playFirstOf(player, _kanDuSelvFiles());

  if (!isAddition) {
    final ans = minusAnswer!;
    await _playFirstOf(player, _svaretErFiles());
    await _playNumberClips(player, ans);
    await Future<void>.delayed(kMathTutorNumberToCoinPause);
    await _playCoinClipOrTts(
      player: player,
      value: ans,
      playCoinTtsFallback: playCoinTtsFallback,
    );
  }

  return true;
}

/// Afspiller `godt_det_giver_altsaa` + svar-tallet. Returnerer `false` hvis stamklippet mangler.
Future<bool> mathTutorTryPlayGodtDetGiverAltsaa({
  required AudioPlayer player,
  required int expectedAnswer,
}) async {
  if (expectedAnswer < 0 || expectedAnswer > 100) {
    return false;
  }
  if (await _firstExistingBasename([kGuidedGodtDetGiverAltsaa]) == null) {
    return false;
  }
  await _playFirstOf(player, [kGuidedGodtDetGiverAltsaa]);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, expectedAnswer);
  return true;
}

/// Mente-hjælp: «skriv» + et ciffer (0–9). Returnerer `false` hvis `skriv.mp3` mangler.
Future<bool> mathTutorTryPlaySkrivOgCiffer({
  required AudioPlayer player,
  required int digit,
}) async {
  if (digit < 0 || digit > 9) {
    return false;
  }
  if (await _firstExistingBasename([kWordSkriv]) == null) {
    return false;
  }
  await _playFirstOf(player, [kWordSkriv]);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, digit);
  return true;
}

Future<String?> _ogTrykOkBasename() => _firstExistingBasename([
      'og_tryk_ok',
      mathTutorAudioFilenameSlug('og tryk ok.'),
    ]);

/// «Skriv» + ciffer + «og tryk ok.» — ét klip pr. del.
Future<bool> mathTutorTryPlaySkrivCifferOgTrykOk({
  required AudioPlayer player,
  required int digit,
}) async {
  if (digit < 0 || digit > 9) {
    return false;
  }
  if (await _firstExistingBasename([kWordSkriv]) == null) {
    return false;
  }
  final ogTryk = await _ogTrykOkBasename();
  if (ogTryk == null) {
    return false;
  }
  for (final part in mathTutorNumberPlayBasenames(digit)) {
    if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
      return false;
    }
  }
  await _playFirstOf(player, [kWordSkriv]);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, digit);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playBasename(player, ogTryk);
  return true;
}

Future<bool> _menteNumberPartsExist(int n) async {
  for (final part in mathTutorNumberPlayBasenames(n)) {
    if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
      return false;
    }
  }
  return true;
}

/// Åbning ved mente (ene-sum 10–18): sammensat af `det_giver` + tal + midtdel + …
///
/// - **12–18:** `det_giver` → sum → `vi_gemmer_de` → ener-ciffer → `enere` → `og_har_10_…`
/// - **10:** `det_giver` → 10 → `vi_har_10_…`
/// - **11:** `det_giver` → 11 → `vi_gemmer_en_en` → `og_har_10_…`
///
/// Mangler en del, returneres `false` (brug hele-sætning-slug eller TTS).
Future<bool> mathTutorTryPlayMenteDetGiverOpening({
  required AudioPlayer player,
  required int onesSum,
}) async {
  if (onesSum < 10 || onesSum > 18) {
    return false;
  }
  final d = onesSum % 10;

  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);

  if (onesSum >= 12 && onesSum <= 18) {
    for (final b in [
      kMenteDetGiver,
      kMenteViGemmerDe,
      kCoinEnereWord,
      kMenteOgHar10,
    ]) {
      if (await _firstExistingBasename([b]) == null) {
        return false;
      }
    }
    if (!await _menteNumberPartsExist(onesSum) || !await _menteNumberPartsExist(d)) {
      return false;
    }
    await _playFirstOf(player, [kMenteDetGiver]);
    await gap();
    await _playNumberClips(player, onesSum);
    await gap();
    await _playFirstOf(player, [kMenteViGemmerDe]);
    await gap();
    await _playNumberClips(player, d);
    await gap();
    await _playFirstOf(player, [kCoinEnereWord]);
    await gap();
    await _playFirstOf(player, [kMenteOgHar10]);
    return true;
  }

  if (onesSum == 10) {
    if (await _firstExistingBasename([kMenteDetGiver]) == null ||
        await _firstExistingBasename([kMenteViHar10]) == null) {
      return false;
    }
    if (!await _menteNumberPartsExist(10)) {
      return false;
    }
    await _playFirstOf(player, [kMenteDetGiver]);
    await gap();
    await _playNumberClips(player, 10);
    await gap();
    await _playFirstOf(player, [kMenteViHar10]);
    return true;
  }

  if (onesSum == 11) {
    for (final b in [kMenteDetGiver, kMenteViGemmerEnEn, kMenteOgHar10]) {
      if (await _firstExistingBasename([b]) == null) {
        return false;
      }
    }
    if (!await _menteNumberPartsExist(11)) {
      return false;
    }
    await _playFirstOf(player, [kMenteDetGiver]);
    await gap();
    await _playNumberClips(player, 11);
    await gap();
    await _playFirstOf(player, [kMenteViGemmerEnEn]);
    await gap();
    await _playFirstOf(player, [kMenteOgHar10]);
    return true;
  }

  return false;
}

/// Ét lydfil for hele sætningen — alias først derefter [mathTutorAudioFilenameSlug].
Future<bool> mathTutorTryPlayGuidedPhraseAsset({
  required AudioPlayer player,
  required String danishSentence,
  List<String> basenameAliases = const [],
}) async {
  final t = danishSentence.trim();
  final slug = t.isEmpty ? '' : mathTutorAudioFilenameSlug(t);
  final found = await _firstExistingBasename([
    ...basenameAliases,
    if (slug.isNotEmpty) slug,
  ]);
  if (found == null) return false;
  await _playBasename(player, found);
  return true;
}

/// «Nej det er ikke rigtigt, prøv igen» — primært [kGuidedNejIkkeRigtigtProevIgen].
Future<bool> mathTutorTryPlayNejIkkeRigtigtProevIgen(AudioPlayer player) {
  return mathTutorTryPlayGuidedPhraseAsset(
    player: player,
    danishSentence: 'Nej det er ikke rigtigt, prøv igen.',
    basenameAliases: const [kGuidedNejIkkeRigtigtProevIgen],
  );
}

/// Kort «øv, prøv igen» på frie opgaver (uden Hjælp-knap); ellers [kGuidedNejIkkeRigtigtProevIgen].
Future<bool> mathTutorTryPlayOevProevIgen(AudioPlayer player) async {
  final found = await _firstExistingBasename([
    kOevProevIgen,
    kGuidedNejIkkeRigtigtProevIgen,
  ]);
  if (found == null) return false;
  try {
    await _playBasename(player, found);
  } catch (_) {
    return false;
  }
  return true;
}

const String kGuidedGodtDerEr = 'godt_der_er';

/// «Godt der er» + tal + «enere».
Future<bool> mathTutorTryPlayGodtDerErEnere({
  required AudioPlayer player,
  required int enereCount,
}) async {
  if (enereCount < 0 || enereCount > 20) {
    return false;
  }
  if (await _firstExistingBasename([kGuidedGodtDerEr]) == null) {
    return false;
  }
  if (await _firstExistingBasename([kCoinEnereWord]) == null) {
    return false;
  }
  await _playFirstOf(player, [kGuidedGodtDerEr]);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, enereCount);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playFirstOf(player, [kCoinEnereWord]);
  return true;
}

Future<bool> mathTutorTryPlayOgTrykOk(AudioPlayer player) {
  return mathTutorTryPlayGuidedPhraseAsset(
    player: player,
    danishSentence: 'og tryk ok.',
    basenameAliases: const ['og_tryk_ok'],
  );
}
