import 'package:flutter/material.dart';

import 'math_vertical_prompt.dart';

class _MathTutorRedCoinStrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.11).clamp(3.0, 5.0);
    final p = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.12, h * 0.88), Offset(w * 0.88, h * 0.12), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _coinTenStruck(double s) => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _coinTen(s),
        CustomPaint(
          size: Size(s, s),
          painter: _MathTutorRedCoinStrikePainter(),
        ),
      ],
    );

/// Filnavn ud fra den talte sætning: små bogstaver, æøå → ae/oe/aa, ord adskilt med `_`.
/// Bruges til `assets/matematiktutor/<slug>.mp3`.
String mathTutorAudioFilenameSlug(String spokenSentence) {
  var t = spokenSentence
      .replaceAll('æ', 'ae')
      .replaceAll('Æ', 'Ae')
      .replaceAll('ø', 'oe')
      .replaceAll('Ø', 'Oe')
      .replaceAll('å', 'aa')
      .replaceAll('Å', 'Aa')
      .replaceAll('é', 'e')
      .replaceAll('É', 'E');
  t = t.toLowerCase();
  t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) {
    return '';
  }
  return t.replaceAll(' ', '_');
}

/// Fjern tegn der lyder mærkeligt i TTS (bevar æøå) — bruges fx af cloud-TTS.
String mathTutorPlainTextForTts(String text) {
  return text
      .replaceAll('💛', '')
      .replaceAll('💪', '')
      .replaceAll('–', '-')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Plus/minus-hjælp: mønter og metadata til svar-trin i bundarket.
/// Oplæsning af første skærm: forhåndsindspillede filer i `assets/matematiktutor/`.
class MathTutorLesson {
  MathTutorLesson({
    required this.screenWidgets,
    required this.expectedAnswer,
    required this.promptLine,
    required this.isAddition,
    required this.operandLeft,
    required this.operandRight,
  });

  final List<Widget> screenWidgets;
  final int expectedAnswer;
  final String promptLine;
  final bool isAddition;
  final int operandLeft;
  final int operandRight;
}

/// Ener-del af regnestykket til guidet «enere i alt»-trin (fx 9+6 ud fra 19+16).
String mathTutorOnesPromptLine(MathTutorLesson lesson) {
  final a = lesson.operandLeft % 10;
  final b = lesson.operandRight % 10;
  final op = lesson.isAddition ? '+' : '-';
  return '$a$op$b';
}

double _coinSizeFor(BuildContext context) =>
    (MediaQuery.sizeOf(context).shortestSide / 13.5).clamp(26.0, 40.0);

/// Luft mellem møntrækker i tutor (konsistent på tværs af skærme).
const double kMathTutorCoinBlockGap = 14.0;

Widget _coinTen(double s) => Image.asset(
      'assets/10moent.webp',
      width: s,
      height: s,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.looks_one, size: s, color: const Color(0xFFF9C433)),
    );

Widget _coinOne(double s) => Image.asset(
      'assets/1moent.webp',
      width: s,
      height: s,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.circle, size: s * 0.5, color: const Color(0xFFF9C433)),
    );

List<Widget> _coinWidgetsForNumber(double s, int n) {
  final tens = n ~/ 10;
  final ones = n % 10;
  return [
    for (var i = 0; i < tens; i++) _coinTen(s),
    for (var i = 0; i < ones; i++) _coinOne(s),
  ];
}

/// «19 =» foran mønthob – tutor. Ved **0** intet (ingen `0=` og ingen ekstra «Nul»-linje).
Widget mathTutorNumberEqualsCoinPile(BuildContext context, int n) {
  final s = _coinSizeFor(context);
  final numStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.1,
    color: Colors.grey.shade900,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  if (n == 0) {
    return const SizedBox.shrink();
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text('$n=', style: numStyle),
      const SizedBox(width: 12),
      Expanded(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          children: _coinWidgetsForNumber(s, n),
        ),
      ),
    ],
  );
}

/// Viser tier-mønter og enermønter for ét tal.
Widget mathTutorCoinPileForNumber(
  BuildContext context,
  int n, {
  String? caption,
  bool numberEqualsPrefix = false,
}) {
  if (numberEqualsPrefix && caption == null) {
    return mathTutorNumberEqualsCoinPile(context, n);
  }
  final s = _coinSizeFor(context);
  final tens = n ~/ 10;
  final ones = n % 10;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            caption,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Color(0xFF1B1B1B),
            ),
          ),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < tens; i++) _coinTen(s),
          for (var i = 0; i < ones; i++) _coinOne(s),
        ],
      ),
    ],
  );
}

/// Kun tier-mønter (antal 10-kroner).
Widget mathTutorTenCoinsRowOnly(BuildContext context, int tenCoinCount) {
  final s = _coinSizeFor(context);
  if (tenCoinCount <= 0) {
    return Text(
      'Ingen tier her',
      style: TextStyle(
        fontSize: 13,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
      ),
    );
  }
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [for (var i = 0; i < tenCoinCount; i++) _coinTen(s)],
  );
}

/// Tier-mønter som ved lån: den **sidste** har rød gennemstregning (lånt til enere).
Widget mathTutorMinusBorrowTensWithBorrowStruck(
  BuildContext context, {
  required int originalTenCount,
}) {
  final s = _coinSizeFor(context);
  if (originalTenCount <= 0) {
    return const SizedBox.shrink();
  }
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: [
      for (var i = 0; i < originalTenCount; i++)
        if (i == originalTenCount - 1)
          _coinTenStruck(s)
        else
          _coinTen(s),
    ],
  );
}

/// Tier-pladser efter lån: [minuendTensAfterBorrow] − [subtrahendTens] med guld-tier mønter.
Widget mathTutorMinusBorrowTensEquationWithCoins(
  BuildContext context, {
  required int minuendTensAfterBorrow,
  required int subtrahendTens,
}) {
  final s = _coinSizeFor(context);
  final numStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF1B1B1B),
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$minuendTensAfterBorrow − $subtrahendTens',
        style: numStyle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (minuendTensAfterBorrow <= 0)
                  const SizedBox.shrink()
                else
                  for (var i = 0; i < minuendTensAfterBorrow; i++) _coinTen(s),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('−', style: numStyle.copyWith(fontSize: 30)),
          ),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (subtrahendTens <= 0)
                  const SizedBox.shrink()
                else
                  for (var i = 0; i < subtrahendTens; i++) _coinTen(s),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

/// Kun små en-mønter (ingen tier), fx 10 efter veksling eller 11−4-trinnet.
Widget mathTutorOnlyOnesCoinsWrap(BuildContext context, int count) {
  final s = _coinSizeFor(context);
  if (count <= 0) {
    return const SizedBox.shrink();
  }
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: [for (var i = 0; i < count; i++) _coinOne(s)],
  );
}

/// Minus (enerdel): tal-linje [minuendOnes] − [subtrahendOnes] og mønthob (kun enere).
Widget mathTutorMinusBorrowOnesEquationWithCoins(
  BuildContext context, {
  required int minuendOnes,
  required int subtrahendOnes,
}) {
  final s = _coinSizeFor(context);
  final numStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF1B1B1B),
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$minuendOnes − $subtrahendOnes',
        style: numStyle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _coinWidgetsForNumber(s, minuendOnes),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('−', style: numStyle.copyWith(fontSize: 30)),
          ),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _coinWidgetsForNumber(s, subtrahendOnes),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Én tier-mønt over ener-minus (lån: skridt 1).
Widget mathTutorMinusBorrowTierAboveOnesBlock(
  BuildContext context, {
  required int minuendOnes,
  required int subtrahendOnes,
}) {
  final s = _coinSizeFor(context);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Center(child: _coinTen(s)),
      const SizedBox(height: kMathTutorCoinBlockGap),
      mathTutorMinusBorrowOnesEquationWithCoins(
        context,
        minuendOnes: minuendOnes,
        subtrahendOnes: subtrahendOnes,
      ),
    ],
  );
}

/// Tier = 10 enermønter (veksling, skridt 2 — øverst). Under: samme ener-linje som før.
Widget mathTutorMinusBorrowTierEqualsTenOnesColumn(
  BuildContext context, {
  required int minuendOnes,
  required int subtrahendOnes,
}) {
  final s = _coinSizeFor(context);
  final eqStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: Colors.grey.shade900,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _coinTen(s),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('=', style: eqStyle),
          ),
          Flexible(child: mathTutorOnlyOnesCoinsWrap(context, 10)),
        ],
      ),
      const SizedBox(height: kMathTutorCoinBlockGap),
      mathTutorMinusBorrowOnesEquationWithCoins(
        context,
        minuendOnes: minuendOnes,
        subtrahendOnes: subtrahendOnes,
      ),
    ],
  );
}

/// Efter «så har vi 11»: kun små mønter (10+minuendOnes) − subtrahendOnes.
Widget mathTutorMinusBorrowFinalOnesSubtract(
  BuildContext context, {
  required int minuendOnesAfterBorrow,
  required int subtrahendOnes,
}) {
  final left = minuendOnesAfterBorrow;
  final right = subtrahendOnes;
  final numStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF1B1B1B),
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$left − $right',
        style: numStyle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(child: mathTutorOnlyOnesCoinsWrap(context, left)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('−', style: numStyle.copyWith(fontSize: 30)),
          ),
          Flexible(child: mathTutorOnlyOnesCoinsWrap(context, right)),
        ],
      ),
    ],
  );
}

/// Samme som [mathTutorMinusBorrowFinalOnesSubtract], men ved **ét tryk** forsvinder **én mønt på hver side**
/// af minus (indtil [removedFromMinuend] == [subtrahendOnes]).
Widget mathTutorMinusBorrowTappableOnesSubtract(
  BuildContext context, {
  required int minuendOnesAfterBorrow,
  required int subtrahendOnes,
  required int removedFromMinuend,
  required VoidCallback onTapRemoveOneFromMinuend,
}) {
  final leftStart = minuendOnesAfterBorrow;
  final rightStart = subtrahendOnes;
  final removed = removedFromMinuend.clamp(0, subtrahendOnes);
  final visibleLeft = (leftStart - removed).clamp(0, leftStart);
  final visibleRight = (rightStart - removed).clamp(0, rightStart);
  final canRemove = removed < subtrahendOnes;
  final tapsComplete = !canRemove;
  final s = _coinSizeFor(context);
  final tapExtent = (s + 14).clamp(44.0, 52.0);
  final numStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF1B1B1B),
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Widget tappableOnesWrap(int visible) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < visible; i++)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canRemove ? onTapRemoveOneFromMinuend : null,
              borderRadius: BorderRadius.circular(tapExtent / 2),
              child: SizedBox(
                width: tapExtent,
                height: tapExtent,
                child: Center(child: _coinOne(s)),
              ),
            ),
          ),
      ],
    );
  }

  final eqOrMinusStyle = numStyle.copyWith(fontSize: 30);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        tapsComplete ? '$leftStart = $visibleLeft' : '$leftStart − $rightStart',
        style: numStyle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      if (tapsComplete)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('=', style: eqOrMinusStyle),
            ),
            Flexible(child: tappableOnesWrap(visibleLeft)),
          ],
        )
      else
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: tappableOnesWrap(visibleLeft)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('−', style: eqOrMinusStyle),
            ),
            Flexible(child: tappableOnesWrap(visibleRight)),
          ],
        ),
    ],
  );
}

/// Som [mathTutorMinusBorrowTappableOnesSubtract], men med **tier**-mønter
/// (fx 2 − 1 tiere ved 23−12).
Widget mathTutorMinusBorrowTappableTensSubtract(
  BuildContext context, {
  required int minuendTens,
  required int subtrahendTens,
  required int removedFromMinuend,
  required VoidCallback onTapRemoveOneFromMinuend,
}) {
  final leftStart = minuendTens;
  final rightStart = subtrahendTens;
  final removed = removedFromMinuend.clamp(0, subtrahendTens);
  final visibleLeft = (leftStart - removed).clamp(0, leftStart);
  final visibleRight = (rightStart - removed).clamp(0, rightStart);
  final canRemove = removed < subtrahendTens;
  final tapsComplete = !canRemove;
  final s = _coinSizeFor(context);
  final tapExtent = (s + 14).clamp(44.0, 52.0);
  final numStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: const Color(0xFF1B1B1B),
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Widget tappableTensWrap(int visible) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < visible; i++)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canRemove ? onTapRemoveOneFromMinuend : null,
              borderRadius: BorderRadius.circular(tapExtent / 2),
              child: SizedBox(
                width: tapExtent,
                height: tapExtent,
                child: Center(child: _coinTen(s)),
              ),
            ),
          ),
      ],
    );
  }

  final eqOrMinusStyle = numStyle.copyWith(fontSize: 30);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        tapsComplete ? '$leftStart = $visibleLeft' : '$leftStart − $rightStart',
        style: numStyle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      if (tapsComplete)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text('=', style: eqOrMinusStyle),
            ),
            Flexible(child: tappableTensWrap(visibleLeft)),
          ],
        )
      else
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: tappableTensWrap(visibleLeft)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('−', style: eqOrMinusStyle),
            ),
            Flexible(child: tappableTensWrap(visibleRight)),
          ],
        ),
    ],
  );
}

/// Efter mente: pil mod tierne, én tier fra 10 enere, kort afstand, rest-enere.
/// [onesSum] er ene-summen 10–18 (fx 11 for 18+13).
Widget mathTutorMenteExchangeFlow(BuildContext context, int onesSum) {
  if (onesSum < 10 || onesSum > 18) {
    return const SizedBox.shrink();
  }
  final s = _coinSizeFor(context);
  final rest = onesSum % 10;
  const arrowColor = Color(0xFF2B9348);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.arrow_back, size: 30, color: arrowColor),
        const SizedBox(width: 2),
        _coinTen(s),
        const SizedBox(width: 3),
        if (rest > 0)
          Wrap(
            spacing: 5,
            runSpacing: 5,
            alignment: WrapAlignment.center,
            children: [for (var i = 0; i < rest; i++) _coinOne(s)],
          )
        else
          const SizedBox(height: 8, width: 8),
      ],
    ),
  );
}

/// Skærm efter korrekt «enere i alt» ved mente: tierpar til venstre, midt bytte 10→1 tier + rest.
Widget mathTutorAddOnesDigitMenteLayout(
  BuildContext context, {
  required String promptLine,
  required int operandLeft,
  required int operandRight,
  required int onesSum,
}) {
  final tensLeft = operandLeft ~/ 10;
  final tensRight = operandRight ~/ 10;
  final leftBlock = Align(
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mathTutorTenCoinsRowOnly(context, tensLeft),
        const SizedBox(width: 6),
        mathTutorTenCoinsRowOnly(context, tensRight),
      ],
    ),
  );

  final midBlock = mathTutorMenteExchangeFlow(context, onesSum);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftBlock,
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: midBlock,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftBlock,
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: midBlock,
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}

/// Danske ord for antal **tier** (2–9): to, tre, …, ni — til mønt-tekst og lydfiler.
String? mathTutorDanishTensCountWord(int tens) {
  switch (tens) {
    case 2:
      return 'to';
    case 3:
      return 'tre';
    case 4:
      return 'fire';
    case 5:
      return 'fem';
    case 6:
      return 'seks';
    case 7:
      return 'syv';
    case 8:
      return 'otte';
    case 9:
      return 'ni';
    default:
      return null;
  }
}

/// Kort TTS-tekst til mønter — bruges når `m_*.mp3` mangler i [matematiktutor].
/// Formulering følger de forhåndsindspillede fraser («på ti», ordtal for tier).
String mathTutorTtsDescribeCoinsForNumber(int n) {
  if (n == 0) {
    return 'Det er nul.';
  }
  final tens = n ~/ 10;
  final ones = n % 10;
  if (tens == 0) {
    if (ones == 1) return 'Det er en en.';
    return 'Det er $ones enere.';
  }
  if (ones == 0) {
    if (tens == 1) {
      return 'Det er en guldmønt på ti.';
    }
    final w = mathTutorDanishTensCountWord(tens);
    if (w != null) {
      return 'Det er $w guldmønter på ti.';
    }
    return 'Det er $tens guldmønter på ti.';
  }
  if (tens == 1) {
    return 'Det svarer til en guldmønt på ti og $ones enere.';
  }
  final w = mathTutorDanishTensCountWord(tens);
  if (w != null) {
    return 'Det svarer til $w guldmønter på ti og $ones enere.';
  }
  return 'Det svarer til $tens guldmønter på ti og $ones enere.';
}

/// Minus med **lån af én tier til enere**: minuendens ener-ciffer < subtrahendens, og der er mindst én tier at låne fra.
bool mathTutorMinusNeedsBorrowTenToOnes(int minuend, int subtrahend) {
  if (minuend < 0 || minuend > 100 || subtrahend < 0 || subtrahend > 100) {
    return false;
  }
  return minuend % 10 < subtrahend % 10 && minuend ~/ 10 >= 1;
}

MathTutorLesson? buildMathTutorLesson(
  BuildContext context,
  MathAddSubParts parts,
) {
  final a = int.tryParse(parts.left);
  final b = int.tryParse(parts.right);
  if (a == null || b == null) return null;

  final promptLine = '${parts.left} ${parts.operator} ${parts.right}'
      .replaceAll('  ', ' ')
      .trim();

  final w = <Widget>[
    const SizedBox(height: 4),
    mathTutorNumberEqualsCoinPile(context, a),
    SizedBox(height: kMathTutorCoinBlockGap),
    mathTutorNumberEqualsCoinPile(context, b),
  ];

  final int expected;
  if (parts.operator == '+') {
    expected = a + b;
  } else if (parts.operator == '-') {
    expected = a - b;
    // Kun de to tal i stykket (minuend + subtrahend), ikke svar som møntlinje.
  } else {
    return null;
  }

  return MathTutorLesson(
    screenWidgets: w,
    expectedAnswer: expected,
    promptLine: promptLine,
    isAddition: parts.operator == '+',
    operandLeft: a,
    operandRight: b,
  );
}
