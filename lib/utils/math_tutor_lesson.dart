import 'package:flutter/material.dart';

import 'math_vertical_prompt.dart';

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

double _coinSizeFor(BuildContext context) =>
    (MediaQuery.sizeOf(context).shortestSide / 12).clamp(28.0, 44.0);

/// Stort regnestykke øverst i hjælp-popup (kun visuelt).
Widget mathTutorEquationHeader(String promptLine) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        promptLine,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.12,
          color: Colors.grey.shade900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

Widget _coinTen(double s) => Image.asset(
      'assets/10moent.png',
      width: s,
      height: s,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.looks_one, size: s, color: const Color(0xFFF9C433)),
    );

Widget _coinOne(double s) => Image.asset(
      'assets/1moent.png',
      width: s,
      height: s,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.circle, size: s * 0.5, color: const Color(0xFFF9C433)),
    );

/// Viser tier-mønter og enermønter for ét tal.
Widget mathTutorCoinPileForNumber(
  BuildContext context,
  int n, {
  String? caption,
}) {
  final s = _coinSizeFor(context);
  final tens = n ~/ 10;
  final ones = n % 10;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
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
        spacing: 6,
        runSpacing: 6,
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
    spacing: 6,
    runSpacing: 6,
    children: [for (var i = 0; i < tenCoinCount; i++) _coinTen(s)],
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
  final leftBlock = Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: mathTutorTenCoinsRowOnly(context, operandLeft ~/ 10),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: mathTutorTenCoinsRowOnly(context, operandRight ~/ 10),
      ),
    ],
  );

  final midBlock = mathTutorMenteExchangeFlow(context, onesSum);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      mathTutorEquationHeader(promptLine),
      const SizedBox(height: 16),
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
              Expanded(flex: 2, child: leftBlock),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
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
    mathTutorEquationHeader(promptLine),
    const SizedBox(height: 20),
    mathTutorCoinPileForNumber(context, a, caption: null),
    const SizedBox(height: 12),
    mathTutorCoinPileForNumber(context, b, caption: null),
  ];

  final int expected;
  if (parts.operator == '+') {
    expected = a + b;
  } else if (parts.operator == '-') {
    expected = a - b;
    w.add(const SizedBox(height: 12));
    w.add(mathTutorCoinPileForNumber(context, expected, caption: null));
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
