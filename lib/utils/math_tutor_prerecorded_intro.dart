import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
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

/// Mønt 11–19 (foretrukket): `det_svarer_til_en_guldmoent_paa_ti_og` → ener-ciffer → **`guldmoent`** (1) / **`guldmoenter`** (2–9) → `paa_en`.
/// I intro: `det_foerste_tal_er` / `det_andet_tal_er` + heltal afspilles før mønt-kæden.
/// Alternativ: det_svarer_til → en/1 → guldmoent (én tier-mønt) → … → enere.
/// Tier 2–8: `det_svarer_til_{to…otte}_guldmoenter_paa_ti` → ener; derefter **1**: `en`→`guldmoent`→`paa_en`; **2–9**: tal→**`guldmoenter`**→`paa_en`.
const String kCoinDetSvarerTil = 'det_svarer_til';
const String kCoinGuldmoent = 'guldmoent';
/// Efter ener-ciffer **2–9** («… på en»): **`guldmoenter.mp3`** (flertal).
const String kCoinGuldmoenter = 'guldmoenter';
/// Hvis `guldmoent.mp3` mangler, kan dette klip bruges i stedet («… guldmønt på ti og») — da udelades ekstra `paa_ti_og`.
const String kCoinGuldmoentPaaTiOg = 'guldmoent_paa_ti_og';
/// Ét klip: «Det svarer til en guldmønt på ti og» — derefter ener-ciffer + `enere`.
const String kCoinDetSvarerTilEnGuldmoentPaaTiOg =
    'det_svarer_til_en_guldmoent_paa_ti_og';
/// Valgfrit **ét** klip for «Det svarer til en guldmønt.» uden «på ti og».
const String kCoinDetSvarerTilEnGuldmoent = 'det_svarer_til_en_guldmoent';
/// Valgfrit mellem guldmønt og enere-ciffer («på ti og»).
const String kCoinPaaTiOg = 'paa_ti_og';
/// Efter `det_svarer_til` i 11–19 split-åbning: «på en» (fx `paa_en.mp3`).
const String kCoinPaaEn = 'paa_en';
/// **10** kr kun tier: «Det er en guldmønt på ti.»
const String kCoinDetErEnGuldmoentPaaTi = 'det_er_en_guldmoent_paa_ti';

List<String> _coinGuldmoentClipCandidates() => [
      kCoinGuldmoent,
      kCoinGuldmoentPaaTiOg,
    ];

/// Efter afspillet ener-antaller på ener-pladsen: **1** mønt → ental; **2–9** → flertal (`guldmoenter`).
List<String> _coinGuldmoentClipCandidatesForOnesCount(int onesDigit) {
  if (onesDigit < 1 || onesDigit > 9) {
    return _coinGuldmoentClipCandidates();
  }
  if (onesDigit == 1) {
    return _coinGuldmoentClipCandidates();
  }
  return [
    kCoinGuldmoenter,
    mathTutorAudioFilenameSlug('guldmønter'),
    ..._coinGuldmoentClipCandidates(),
  ];
}

List<String> _coinPaaEnClipCandidates() => [
      kCoinPaaEn,
      mathTutorAudioFilenameSlug('paa en'),
      mathTutorAudioFilenameSlug('på en'),
    ];

const String kCoinEnereWord = 'enere';

// --- Minus: pladsværdi-forklaring (efter forkert svar / «videre») ---

const String kMinusDerEr = 'der_er';
/// Efter korrekt ener-svar (uden lån): «Så går vi til tierne, der er …».
const String kMinusSaaGaarViTilTierneDerEr = 'saa_gaar_vi_til_tierne_der_er';
const String kMinusHvisDuBruger = 'hvis_du_bruger';
const String kMinusHvorMangeEnereSaaTilbage =
    'hvor_mange_enere_har_du_saa_tilbage';
const String kMinusHvorMangeTiereSaaTilbage =
    'hvor_mange_tiere_har_du_saa_tilbage';

// --- Minus: lån (tier → enere) ---
const String kMinusManglerDuJo = 'mangler_du_jo';
const String kMinusDuHarForFaaEnere = 'du_har_for_faa_enere_til_at_traekke';
const String kMinusFraWord = 'fra';
const String kMinusFraDuSkalHaveFlereEnere = 'fra_du_skal_have_flere_enere';
const String kMinusDuSkalHaveFlereEnere = 'du_skal_have_flere_enere';
const String kMinusViTager = 'vi_tager';
const String kMinusEnTierFraTierne = 'en_tier_fra_tierne';
const String kMinusNuHarDuNokEnere = 'nu_har_du_nok_enere';
const String kMinusNuKanDuTraekkeEnereFra = 'nu_kan_du_traekke_enere_fra';
const String kMinusEnereFra = 'enere_fra';
const String kMinusFaarDuAntalEnere = 'faar_du_antal_enere';
const String kMinusHvorMangeEnereErDer = 'hvor_mange_enere_er_der';
const String kMinusTierneErEnMindre = 'tierne_er_en_mindre';
const String kMinusPaaTierpladsenErDerNu = 'paa_tierpladsen_er_der_nu';

List<String> _minusSaaGaarViTilTierneDerErCandidates() => [
      kMinusSaaGaarViTilTierneDerEr,
      mathTutorAudioFilenameSlug('så går vi til tierne der er'),
    ];

List<String> _minusHvisDuBrugerCandidates() => [
      kMinusHvisDuBruger,
      mathTutorAudioFilenameSlug('hvis du bruger'),
      mathTutorAudioFilenameSlug('hvis du bruger.'),
    ];

List<String> _minusManglerDuJoCandidates() => [
      kMinusManglerDuJo,
      mathTutorAudioFilenameSlug('mangler du jo'),
      mathTutorAudioFilenameSlug('mangler du jo.'),
    ];

List<String> _minusFraWordCandidates() => [
      kMinusFraWord,
      mathTutorAudioFilenameSlug('fra'),
      mathTutorAudioFilenameSlug('fra.'),
    ];

List<String> _minusDuSkalHaveFlereEnereCandidates() => [
      kMinusDuSkalHaveFlereEnere,
      kMinusFraDuSkalHaveFlereEnere,
      mathTutorAudioFilenameSlug('du skal have flere enere'),
      mathTutorAudioFilenameSlug('fra du skal have flere enere'),
    ];

List<String> _minusEnTierFraTierneCandidates() => [
      kMinusEnTierFraTierne,
      mathTutorAudioFilenameSlug('en tier fra tierne'),
      mathTutorAudioFilenameSlug('en tier fra tierne.'),
    ];

List<String> _minusNuKanDuTraekkeCandidates() => [
      'nu_kan_du_traekke',
      kMinusNuKanDuTraekkeEnereFra,
      mathTutorAudioFilenameSlug('nu kan du trække'),
      mathTutorAudioFilenameSlug('nu kan du trække enere fra'),
    ];

List<String> _minusEnereFraCandidates() => [
      kMinusEnereFra,
      mathTutorAudioFilenameSlug('enere fra'),
      mathTutorAudioFilenameSlug('enere fra.'),
    ];

List<String> _minusFaarDuAntalEnereCandidates() => [
      kMinusFaarDuAntalEnere,
      mathTutorAudioFilenameSlug('får du antal enere'),
      mathTutorAudioFilenameSlug('faar du antal enere'),
    ];

List<String> _minusHvorMangeEnereErDerCandidates() => [
      kMinusHvorMangeEnereErDer,
      mathTutorAudioFilenameSlug('hvor mange enere er der'),
      mathTutorAudioFilenameSlug('hvor mange enere er der.'),
    ];

List<String> _minusEnereTilbageCandidates() => [
      kMinusHvorMangeEnereSaaTilbage,
      mathTutorAudioFilenameSlug(
        'Hvor mange enere har du så tilbage',
      ),
      mathTutorAudioFilenameSlug(
        'Hvor mange enere har du så tilbage.',
      ),
    ];

List<String> _minusTiereTilbageCandidates() => [
      kMinusHvorMangeTiereSaaTilbage,
      mathTutorAudioFilenameSlug(
        'Hvor mange tiere har du så tilbage',
      ),
      mathTutorAudioFilenameSlug(
        'Hvor mange tiere har du så tilbage.',
      ),
    ];

List<String> _minusTierneErEnMindreCandidates() => [
      kMinusTierneErEnMindre,
      mathTutorAudioFilenameSlug('tierne er en mindre'),
    ];

List<String> _minusPaaTierpladsenCandidates() => [
      kMinusPaaTierpladsenErDerNu,
      mathTutorAudioFilenameSlug('paa tierpladsen er der nu'),
      mathTutorAudioFilenameSlug('på tierpladsen er der nu'),
    ];

List<String> _minusViStarterMedEnerneCandidates() => [
      'vi_starter_med_enerne_det_vil_sige',
      mathTutorAudioFilenameSlug('Vi starter med enerne det vil sige.'),
      mathTutorAudioFilenameSlug('Vi starter med enerne det vil sige'),
    ];

List<String> _minusDetKanIkkeLaaneEnTierCandidates() => [
      'det_kan_vi_ikke_for_saa_bliver_det_et_minus_tal_vi_maa_derfor_laane_en_tier',
      mathTutorAudioFilenameSlug(
        'det kan vi ikke for så bliver det et minus tal vi må derfor låne en tier',
      ),
      mathTutorAudioFilenameSlug(
        'det kan vi ikke for saa bliver det et minus tal vi maa derfor laane en tier',
      ),
    ];

List<String> _minusViVekslerTierTilTiEnereCandidates() => [
      'vi_veksler_en_tier_til_ti_enere',
      mathTutorAudioFilenameSlug('vi veksler en tier til ti enere'),
      mathTutorAudioFilenameSlug('Vi veksler en tier til ti enere.'),
    ];

List<String> _minusSaaHarViCandidates() => [
      'saa_har_vi',
      mathTutorAudioFilenameSlug('så har vi'),
      mathTutorAudioFilenameSlug('Så har vi.'),
    ];

List<String> _minusSkrivSvaretIBoksenCandidates() => [
      'skriv_svaret_i_boksen',
      mathTutorAudioFilenameSlug('skriv svaret i boksen'),
      mathTutorAudioFilenameSlug('Skriv svaret i boksen.'),
    ];

List<String> _minusDuSkalAltsaaTraekkeCandidates() => [
      'du_skal_altsaa_traekke',
      mathTutorAudioFilenameSlug('du skal altså trække'),
      mathTutorAudioFilenameSlug('Du skal altså trække.'),
    ];

List<String> _minusGuldmoenterFraCandidates() => [
      'guldmoenter_fra',
      mathTutorAudioFilenameSlug('guldmoenter fra'),
      mathTutorAudioFilenameSlug('guldmønter fra'),
    ];

List<String> _minusTrykPaaCandidates() => [
      'Tryk_paa',
      'tryk_paa',
      mathTutorAudioFilenameSlug('Tryk på'),
      mathTutorAudioFilenameSlug('tryk på'),
      mathTutorAudioFilenameSlug('Tryk på.'),
    ];

List<String> _minusGuldmoenterForAtFjerneCandidates() => [
      'guldmoenter_for_at_fjerne_dem_og_se_resultatet',
      mathTutorAudioFilenameSlug(
        'guldmoenter for at fjerne dem og se resultatet',
      ),
      mathTutorAudioFilenameSlug(
        'guldmønter for at fjerne dem og se resultatet',
      ),
    ];

List<String> _minusDerVarCandidates() => [
      'der_var',
      mathTutorAudioFilenameSlug('der var'),
      mathTutorAudioFilenameSlug('Der var.'),
    ];

List<String> _minusTiereWordCandidates() => [
      'tiere',
      mathTutorAudioFilenameSlug('tiere'),
      mathTutorAudioFilenameSlug('Tiere.'),
    ];

List<String> _minusMenViBrugteDenEneCandidates() => [
      'men_vi_brugte_den_ene_saa_nu_er_der_kun',
      mathTutorAudioFilenameSlug(
        'men vi brugte den ene så nu er der kun',
      ),
      mathTutorAudioFilenameSlug(
        'men vi brugte den ene saa nu er der kun',
      ),
    ];

List<String> _minusSvaretErClipCandidates() => [
      'svaret_er',
      mathTutorAudioFilenameSlug('svaret er'),
      mathTutorAudioFilenameSlug('Svaret er.'),
    ];

List<String> _minusGodtGaaetClipCandidates() => [
      'godt_gaaet',
      mathTutorAudioFilenameSlug('godt gået'),
      mathTutorAudioFilenameSlug('Godt gået.'),
    ];

/// Efter korrekt tier-svar ved minus med lån: «svaret er» → svar-tal → «godt gået».
Future<bool> mathTutorTryPlayMinusBorrowFinalResultPraise({
  required AudioPlayer player,
  required int expectedAnswer,
}) async {
  if (expectedAnswer < 0 || expectedAnswer > 100) {
    return false;
  }
  try {
    Future<void> gap() =>
        Future<void>.delayed(kMathTutorNumberToCoinPause);

    await _playFirstOf(player, _minusSvaretErClipCandidates());
    await gap();
    await _playNumberClips(player, expectedAnswer);
    await gap();
    await _playFirstOf(player, _minusGodtGaaetClipCandidates());
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus afslutning svaret er: $e\n$st');
    return false;
  }
}

Future<void> _minusOnesSimpleGuidedChain({
  required AudioPlayer player,
  required int minuendOnes,
  required int subtrahendOnes,
}) async {
  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);

  await _playFirstOf(player, [kMinusDerEr]);
  await gap();
  await _playNumberClips(player, minuendOnes);
  await gap();
  await _playFirstOf(player, _minusHvisDuBrugerCandidates());
  await gap();
  await _playNumberClips(player, subtrahendOnes);
  await gap();
  await _playFirstOf(player, _minusEnereTilbageCandidates());
}

Future<void> _minusOnesBorrowGuidedChain({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  Future<void> Function()? afterEnTierFraTierne,
}) async {
  final ao = operandLeft % 10;
  final bo = operandRight % 10;
  final adj = 10 + ao;
  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);

  await _playFirstOf(player, [kMinusDerEr]);
  await gap();
  await _playNumberClips(player, ao);
  await gap();
  await _playFirstOf(player, _minusHvisDuBrugerCandidates());
  await gap();
  await _playNumberClips(player, bo);
  await gap();
  await _playFirstOf(player, _minusManglerDuJoCandidates());
  await gap();
  await _playNumberClips(player, ao);
  await gap();
  await _playFirstOf(player, [
    kMinusDuHarForFaaEnere,
    mathTutorAudioFilenameSlug(
      'du har for faa enere til at trække',
    ),
  ]);
  await gap();
  await _playNumberClips(player, ao);
  await gap();
  await _playFirstOf(player, _minusFraWordCandidates());
  await gap();
  await _playNumberClips(player, bo);
  await gap();
  await _playFirstOf(player, _minusDuSkalHaveFlereEnereCandidates());
  await gap();
  await _playFirstOf(player, [
    kMinusViTager,
    mathTutorAudioFilenameSlug('vi tager'),
  ]);
  await gap();
  await _playFirstOf(player, _minusEnTierFraTierneCandidates());
  if (afterEnTierFraTierne != null) {
    await afterEnTierFraTierne();
  }
  await gap();
  await _playFirstOf(player, [
    kMinusNuHarDuNokEnere,
    mathTutorAudioFilenameSlug('nu har du nok enere'),
  ]);
  await gap();
  await _playFirstOf(player, _minusNuKanDuTraekkeCandidates());
  await gap();
  await _playNumberClips(player, bo);
  await gap();
  await _playFirstOf(player, _minusEnereFraCandidates());
  await gap();
  await _playNumberClips(player, adj);
  await gap();
  await _playFirstOf(player, _minusFaarDuAntalEnereCandidates());
  await gap();
  await _playFirstOf(player, _minusHvorMangeEnereErDerCandidates());
}

Future<void> _minusOnesBorrowDetailedWalkChain({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  Future<void> Function(int step)? onVisualStep,
}) async {
  final ao = operandLeft % 10;
  final bo = operandRight % 10;
  final adj = 10 + ao;
  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);

  if (onVisualStep != null) {
    await onVisualStep(0);
  }
  await _playFirstOf(player, _minusViStarterMedEnerneCandidates());
  await gap();
  await _playNumberClips(player, ao);
  await gap();
  await _playFirstOf(player, _minusFiles());
  await gap();
  await _playNumberClips(player, bo);
  await gap();
  await _playFirstOf(player, _minusDetKanIkkeLaaneEnTierCandidates());
  if (onVisualStep != null) {
    await onVisualStep(1);
  }
  await gap();
  await _playFirstOf(player, _minusViVekslerTierTilTiEnereCandidates());
  if (onVisualStep != null) {
    await onVisualStep(2);
  }
  await gap();
  await _playFirstOf(player, _minusSaaHarViCandidates());
  await gap();
  await _playNumberClips(player, adj);
  if (onVisualStep != null) {
    await onVisualStep(3);
  }
  await gap();
  await _playFirstOf(player, _minusFiles());
  await gap();
  await _playNumberClips(player, bo);
  await gap();
  await _playFirstOf(player, _minusSkrivSvaretIBoksenCandidates());
}

/// Minus enere (uden lån): `der_er` → ener-cifre → `hvis_du_bruger` → … → `hvor_mange_enere_har_du_saa_tilbage`.
Future<bool> mathTutorTryPlayMinusOnesExplanation({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  try {
    await _minusOnesSimpleGuidedChain(
      player: player,
      minuendOnes: operandLeft % 10,
      subtrahendOnes: operandRight % 10,
    );
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus enere-kæde: $e\n$st');
    return false;
  }
}

/// Minus enere **uden** lån (ener − ener går ud): `vi_starter_med_enerne` → ener → `minus` → ener — før interaktive mønter.
Future<bool> mathTutorTryPlayMinusOnesNoBorrowViStarterOpening({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  if (mathTutorMinusNeedsBorrowTenToOnes(operandLeft, operandRight)) {
    return false;
  }
  try {
    final ao = operandLeft % 10;
    final bo = operandRight % 10;
    Future<void> gap() =>
        Future<void>.delayed(kMathTutorNumberToCoinPause);

    await _playFirstOf(player, _minusViStarterMedEnerneCandidates());
    await gap();
    await _playNumberClips(player, ao);
    await gap();
    await _playFirstOf(player, _minusFiles());
    await gap();
    await _playNumberClips(player, bo);
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus enere uden lån vi starter: $e\n$st');
    return false;
  }
}

/// Minus **tiere** uden lån efter korrekt ener-svar:
/// `saa_gaar_vi_til_tierne_der_er` → [minuend tier-ciffer] → `minus` → [subtrahend tier-ciffer].
Future<bool> mathTutorTryPlayMinusNoBorrowTensAfterOnesOpening({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  if (mathTutorMinusNeedsBorrowTenToOnes(operandLeft, operandRight)) {
    return false;
  }
  try {
    final at = operandLeft ~/ 10;
    final bt = operandRight ~/ 10;
    Future<void> gap() =>
        Future<void>.delayed(kMathTutorNumberToCoinPause);

    await _playFirstOf(player, _minusSaaGaarViTilTierneDerErCandidates());
    await gap();
    await _playNumberClips(player, at);
    await gap();
    await _playFirstOf(player, _minusFiles());
    await gap();
    await _playNumberClips(player, bt);
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus tier uden lån efter ener: $e\n$st');
    return false;
  }
}

/// Minus enere med lån: vekslingsgennemgang (ener + tier + 10 enere + «så har vi» + slutspørgsmål).
Future<bool> mathTutorTryPlayMinusBorrowOnesDetailedWalkthrough({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  Future<void> Function(int step)? onVisualStep,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  if (!mathTutorMinusNeedsBorrowTenToOnes(operandLeft, operandRight)) {
    return false;
  }
  try {
    await _minusOnesBorrowDetailedWalkChain(
      player: player,
      operandLeft: operandLeft,
      operandRight: operandRight,
      onVisualStep: onVisualStep,
    );
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus lån detaljeret: $e\n$st');
    return false;
  }
}

/// Interaktivt ener-trin efter lån: spoken vejledning til at trykke mønter væk (ingen tekst på skærmen).
Future<bool> mathTutorTryPlayMinusBorrowInteractiveOnesInstruction({
  required AudioPlayer player,
  required int subtrahendOnes,
}) async {
  if (subtrahendOnes < 0 || subtrahendOnes > 9) {
    return false;
  }
  try {
    Future<void> gap() =>
        Future<void>.delayed(kMathTutorNumberToCoinPause);

    await _playFirstOf(player, _minusDuSkalAltsaaTraekkeCandidates());
    await gap();
    await _playNumberClips(player, subtrahendOnes);
    await gap();
    await _playFirstOf(player, _minusGuldmoenterFraCandidates());
    await gap();
    await _playFirstOf(player, _minusTrykPaaCandidates());
    await gap();
    await _playNumberClips(player, subtrahendOnes);
    await gap();
    await _playFirstOf(player, _minusGuldmoenterForAtFjerneCandidates());
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus interaktiv ener-instruktion: $e\n$st');
    return false;
  }
}

Future<void> _minusBorrowTensAfterOnesWalkChain({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  Future<void> Function(int step)? onVisualStep,
}) async {
  final a0 = operandLeft ~/ 10;
  final a1 = operandLeft ~/ 10 - 1;
  final bt = operandRight ~/ 10;
  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);

  await _playFirstOf(player, _minusDerVarCandidates());
  await gap();
  await _playNumberClips(player, a0);
  await gap();
  await _playFirstOf(player, _minusTiereWordCandidates());
  await gap();
  await _playFirstOf(player, _minusMenViBrugteDenEneCandidates());
  if (onVisualStep != null) {
    await onVisualStep(1);
  }
  await gap();
  await _playNumberClips(player, a1);
  await gap();
  await _playFirstOf(player, _minusFiles());
  await gap();
  await _playNumberClips(player, bt);
  await gap();
  await _playFirstOf(player, _minusSkrivSvaretIBoksenCandidates());
}

/// Efter korrekt ener-svar ved lån: tier med gennemstregning → [minuend tiere] − [subtrahend tiere] + skriv svar.
Future<bool> mathTutorTryPlayMinusBorrowTensAfterOnesWalkthrough({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  Future<void> Function(int step)? onVisualStep,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  if (!mathTutorMinusNeedsBorrowTenToOnes(operandLeft, operandRight)) {
    return false;
  }
  if (operandLeft ~/ 10 < 1) {
    return false;
  }
  try {
    await _minusBorrowTensAfterOnesWalkChain(
      player: player,
      operandLeft: operandLeft,
      operandRight: operandRight,
      onVisualStep: onVisualStep,
    );
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus tier efter ener: $e\n$st');
    return false;
  }
}

/// Minus enere med lån (én-tier → enere): én sammenhængende lydfil-kæde som i tutor-teksten.
Future<bool> mathTutorTryPlayMinusOnesBorrowFullChain({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  Future<void> Function()? afterEnTierFraTierne,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  try {
    await _minusOnesBorrowGuidedChain(
      player: player,
      operandLeft: operandLeft,
      operandRight: operandRight,
      afterEnTierFraTierne: afterEnTierFraTierne,
    );
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus enere lån-kæde: $e\n$st');
    return false;
  }
}

/// Minus tier-kæde (samme mønster som enere). [useBorrowTierPreamble]: efter lån på enerplads.
Future<bool> mathTutorTryPlayMinusTensExplanation({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  bool useBorrowTierPreamble = false,
}) async {
  if (operandLeft < 0 || operandLeft > 100 || operandRight < 0 || operandRight > 100) {
    return false;
  }
  try {
    Future<void> gap() =>
        Future<void>.delayed(kMathTutorNumberToCoinPause);

    final aTens = useBorrowTierPreamble
        ? operandLeft ~/ 10 - 1
        : operandLeft ~/ 10;
    final bTens = operandRight ~/ 10;

    if (useBorrowTierPreamble) {
      await _playFirstOf(player, _minusTierneErEnMindreCandidates());
      await gap();
      await _playFirstOf(player, _minusPaaTierpladsenCandidates());
      await gap();
    }

    await _playFirstOf(player, [kMinusDerEr]);
    await gap();
    await _playNumberClips(player, aTens);
    await gap();
    await _playFirstOf(player, _minusHvisDuBrugerCandidates());
    await gap();
    await _playNumberClips(player, bTens);
    await gap();
    await _playFirstOf(player, _minusTiereTilbageCandidates());
    return true;
  } catch (e, st) {
    debugPrint('mathTutor minus tiere-kæde: $e\n$st');
    return false;
  }
}

/// Guidet trin: «Godt det giver altså» derefter svar-tal.
const String kGuidedGodtDetGiverAltsaa = 'godt_det_giver_altsaa';

/// Forkert svar på guidet trin: `nej_det_er_ikke_rigtigt_proev_igen.mp3`.
const String kGuidedNejIkkeRigtigtProevIgen = 'nej_det_er_ikke_rigtigt_proev_igen';

/// Forkert svar uden matematikhjælp: `oev_proev_igen.mp3` (kort «øv, prøv igen»).
const String kOevProevIgen = 'oev_proev_igen';

/// Første matematikskærm (rod): «åbn en mappe nedenfor».
const String kAabenEnMappeNedenfor = 'aaben_en_mappe_nedenfor';

/// Mappe med undermapper/opgaver: vælg hvilken opgave.
const String kVaelgHvilkenOpgave = 'vaelg_hvilken_opgave';

/// Ord-klip (ét ord i filnavnet).
const String kWordSkriv = 'skriv';
const String kWordEn = 'en';
/// Mellem talsprog dele, fx *fem* **og** *tyve* (25).
const String kWordOg = 'og';

/// Efter ener-ciffer (1–9) i «det svarer til … på ti»-kæden: **`guldmoent`** (1) eller **`guldmoenter`** (2–9) → **paa_en**.
Future<bool> _coinDetSvarerTilOnesTailAssetsPresent(int onesDigit) async {
  if (onesDigit < 1 || onesDigit > 9) {
    return false;
  }
  if (await _firstExistingBasename(_coinPaaEnClipCandidates()) == null) {
    return false;
  }
  for (final part in mathTutorNumberPlayBasenames(onesDigit)) {
    if (await _firstExistingBasename(_digitClipCandidates(part)) == null) {
      return false;
    }
  }
  return await _firstExistingBasename(
        _coinGuldmoentClipCandidatesForOnesCount(onesDigit),
      ) !=
      null;
}

/// Kalds **efter** `_playNumberClips(ones)` (1–9).
Future<void> _playCoinDetSvarerTilOnesTailAfterDigit(
  AudioPlayer player,
  int onesDigit,
) async {
  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playFirstOf(
    player,
    _coinGuldmoentClipCandidatesForOnesCount(onesDigit),
  );
  await gap();
  await _playFirstOf(player, _coinPaaEnClipCandidates());
}

/// Efter vist **antal ener-mønter** (én-plads): **1** → `en`/`en.mp3` først, derefter `enere` hvis `en` mangler.
List<String> _coinEnereUnitWordCandidates(int onesOrEnereCount0to9) {
  if (onesOrEnereCount0to9 == 1) {
    return [kWordEn, 'en', kCoinEnereWord, 'enere'];
  }
  return [kCoinEnereWord, 'enere'];
}

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
  /// Hele tal som ét klip: `21.mp3` … `39.mp3` (40 via `n % 10 == 0`).
  if (n >= 21 && n <= 39) {
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
  return _coinDetSvarerTilOnesTailAssetsPresent(ones);
}

Future<void> _playCoin11to19FluentChain(AudioPlayer player, int value) async {
  final ones = value % 10;
  await _playFirstOf(player, _coin11to19FluentOpeningCandidates());
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, ones);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playCoinDetSvarerTilOnesTailAfterDigit(player, ones);
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
  if (ones == 1) {
    if (await _coinWordEnOrDigitOneBasename() == null) {
      return false;
    }
  }
  return _coinDetSvarerTilOnesTailAssetsPresent(ones);
}

Future<void> _playCoinMultiTenWithOnesComposite(
  AudioPlayer player,
  int value,
) async {
  Future<void> gap() =>
      Future<void>.delayed(kMathTutorNumberToCoinPause);
  final tens = value ~/ 10;
  final ones = value % 10;
  final open = _coinMultiTenOpeningBasename(tens)!;
  await _playFirstOf(player, [open]);
  await gap();
  if (ones == 1) {
    final enB = await _coinWordEnOrDigitOneBasename();
    if (enB == null) {
      throw StateError('Matematiktutor 21–91: mangler en/1 til ener-plads');
    }
    await _playBasename(player, enB);
    await gap();
    await _playFirstOf(
      player,
      _coinGuldmoentClipCandidatesForOnesCount(ones),
    );
    await gap();
    await _playFirstOf(player, _coinPaaEnClipCandidates());
    return;
  }
  await _playNumberClips(player, ones);
  await gap();
  await _playFirstOf(
    player,
    _coinGuldmoentClipCandidatesForOnesCount(ones),
  );
  await gap();
  await _playFirstOf(player, _coinPaaEnClipCandidates());
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

Future<bool> _coinComposite11To19AssetsPresent(int value) async {
  if (value < 11 || value > 19) {
    return false;
  }
  if (!await _coin11to19OpeningPresent()) {
    return false;
  }
  return _coinDetSvarerTilOnesTailAssetsPresent(value % 10);
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
    final paaEnBare = await _firstExistingBasename(_coinPaaEnClipCandidates());
    if (paaEnBare != null) {
      await _playBasename(player, paaEnBare);
      await Future<void>.delayed(kMathTutorNumberToCoinPause);
    }
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
  await _playCoinDetSvarerTilOnesTailAfterDigit(player, ones);
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
    if (await _coinComposite11To19AssetsPresent(value)) {
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

  /// Ét klip for hele tallet (fx `21.mp3`) — kun hvis den fulde guld-møntkæde mangler
  /// (ellers lyder «21» to gange: efter «det første tal er» *og* som møntforklaring).
  if (value >= 21 && value <= 40) {
    final one = await _firstExistingBasename(['$value']);
    if (one != null) {
      await _playBasename(player, one);
      return;
    }
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

Future<bool> _introRequiredAssetsPresent({
  required int a,
  required int b,
  required bool isAddition,
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
  return true;
}

Future<bool> playMathTutorPrerecordedIntroFirstScreen({
  required AudioPlayer player,
  required int operandLeft,
  required int operandRight,
  required bool isAddition,
  required Future<void> Function(String text) playCoinTtsFallback,
}) async {
  final a = operandLeft;
  final b = operandRight;
  if (a < 0 || a > 100 || b < 0 || b > 100) {
    return false;
  }

  if (!await _introRequiredAssetsPresent(
    a: a,
    b: b,
    isAddition: isAddition,
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

/// «Åbn en mappe nedenfor» på matematik-roden (fallback hvis fil mangler).
Future<bool> mathTutorTryPlayAabenEnMappeNedenfor(AudioPlayer player) async {
  final found = await _firstExistingBasename([
    kAabenEnMappeNedenfor,
    'Aaben_en_mappe_nedenfor',
  ]);
  if (found == null) return false;
  try {
    await _playBasename(player, found);
  } catch (_) {
    return false;
  }
  return true;
}

/// «Vælg hvilken opgave» på mappe med valg (undermapper / Spil — ingen skærmtekst).
Future<bool> mathTutorTryPlayVaelgHvilkenOpgave(AudioPlayer player) async {
  final found = await _firstExistingBasename([
    kVaelgHvilkenOpgave,
    mathTutorAudioFilenameSlug('Vælg hvilken opgave'),
    mathTutorAudioFilenameSlug('Vælg hvilken opgave.'),
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

/// «Godt der er» + tal + **én** ener som `en`, ellers `enere`.
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
  if (await _firstExistingBasename(
        _coinEnereUnitWordCandidates(enereCount),
      ) ==
      null) {
    return false;
  }
  await _playFirstOf(player, [kGuidedGodtDerEr]);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playNumberClips(player, enereCount);
  await Future<void>.delayed(kMathTutorNumberToCoinPause);
  await _playFirstOf(player, _coinEnereUnitWordCandidates(enereCount));
  return true;
}

Future<bool> mathTutorTryPlayOgTrykOk(AudioPlayer player) {
  return mathTutorTryPlayGuidedPhraseAsset(
    player: player,
    danishSentence: 'og tryk ok.',
    basenameAliases: const ['og_tryk_ok'],
  );
}
