import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Simpelt regnestykke med præcis én + eller – mellem to heltal (prompt uden =svar).
class MathAddSubParts {
  const MathAddSubParts({
    required this.left,
    required this.operator,
    required this.right,
  });

  final String left;
  final String operator;
  final String right;
}

/// Fx `26+53`, `12 - 5` → kan vises i søjler. Alt andet → null.
MathAddSubParts? tryParseSingleAddSub(String prompt) {
  final s = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
  final m = RegExp(r'^(\d+)\s*([+\-])\s*(\d+)$').firstMatch(s);
  if (m == null) return null;
  return MathAddSubParts(
    left: m.group(1)!,
    operator: m.group(2)!,
    right: m.group(3)!,
  );
}

/// Bredde af søjlen med cifre (samme som tekstlinjerne) — til svarbokse under stregen.
double mathVerticalColumnWidth(MathAddSubParts parts, double digitFontSize) {
  final maxLen = parts.left.length > parts.right.length
      ? parts.left.length
      : parts.right.length;
  final topLine = ' ${parts.left.padLeft(maxLen)}';
  final bottomLine = '${parts.operator}${parts.right.padLeft(maxLen)}';
  return digitFontSize *
      0.65 *
      math.max(topLine.length, bottomLine.length);
}

/// Ca. bredde ét ciffer i opgavens font — til at lineære svarfelter op med tallene.
double mathVerticalDigitCellWidth(double digitFontSize) =>
    digitFontSize * 0.72;

/// Én [line.tegn] pr. celle med ens bredde, så flere rækker (mentetalsrække vs. tal)
/// lander i **samme søjler** uanset fontvægt.
Widget mathAlignedDigitRow({
  required String line,
  required double columnWidth,
  required TextStyle style,
}) {
  final n = line.length;
  if (n == 0) return const SizedBox.shrink();
  final w = columnWidth / n;
  return SizedBox(
    width: columnWidth,
    child: Row(
      children: [
        for (var i = 0; i < n; i++)
          SizedBox(
            width: w,
            child: Text(
              line[i],
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
      ],
    ),
  );
}

/// Mente-ciffer for lodret **addition** (+), placeres over operand-cifre.
class AdditionCarrySlot {
  const AdditionCarrySlot({
    required this.digit,
    required this.leading,
    required this.columnFromLeft,
    required this.revealAfterCorrectFromRight,
  });

  /// Mente-værdi (typisk 1).
  final int digit;
  /// `true` = ny plads til venstre for hele opstillingen (fx 56+47 → 103).
  final bool leading;
  /// Operand-søjle fra venstre (0 = venstre ciffer), ignoreres hvis [leading].
  final int columnFromLeft;
  /// Vis når mindst dette antal **korrekte** svarcifre fra højre er udfyldt.
  final int revealAfterCorrectFromRight;
}

int _operandMaxLen(MathAddSubParts parts) =>
    parts.left.length > parts.right.length
        ? parts.left.length
        : parts.right.length;

/// Ciffer i pad’et operandstreng; mellemrum eller ugyldigt → 0 (fx `" 75"`).
int _operandDigitAt(String padded, int index) {
  if (index < 0 || index >= padded.length) return 0;
  final u = padded.codeUnitAt(index);
  if (u >= 48 && u <= 57) return u - 48;
  return 0;
}

/// Mente fra højre mod venstre for plus; tom hvis ingen mente undervejs.
/// Mentecifferet placeres i søjlen **til venstre** for den plads man lige har lagt sammen
/// (samme vandrette position som cifrene i den søjle – oven over øverste linje).
List<AdditionCarrySlot> additionCarrySlotsForAdd(MathAddSubParts parts) {
  if (parts.operator != '+') return [];
  final maxLen = _operandMaxLen(parts);
  final l = parts.left.padLeft(maxLen);
  final r = parts.right.padLeft(maxLen);
  var carry = 0;
  final out = <AdditionCarrySlot>[];
  for (var c = maxLen - 1; c >= 0; c--) {
    final sum = _operandDigitAt(l, c) + _operandDigitAt(r, c) + carry;
    carry = sum ~/ 10;
    final stageFromRight = maxLen - c;
    if (carry <= 0) continue;
    if (c > 0) {
      out.add(
        AdditionCarrySlot(
          digit: carry,
          leading: false,
          columnFromLeft: c - 1,
          revealAfterCorrectFromRight: stageFromRight,
        ),
      );
    } else {
      out.add(
        AdditionCarrySlot(
          digit: carry,
          leading: true,
          columnFromLeft: 0,
          revealAfterCorrectFromRight: stageFromRight,
        ),
      );
    }
  }
  return out;
}

/// Linje med samme længde som topoperand-linjen (`' '+ venstre.padLeft(maxLen)`).
/// Returnerer `null` når intet skal vises endnu eller ingen mente findes.
String? additionCarryLineForDisplay(
  MathAddSubParts parts,
  List<AdditionCarrySlot> slots,
  int answerSuffixCorrectFromRight,
) {
  if (parts.operator != '+' || slots.isEmpty) return null;
  final maxLen = _operandMaxLen(parts);
  final chars = List.filled(1 + maxLen, ' ');
  var any = false;
  for (final s in slots) {
    if (answerSuffixCorrectFromRight < s.revealAfterCorrectFromRight) {
      continue;
    }
    any = true;
    if (s.leading) {
      chars[0] = '${s.digit}';
    } else {
      chars[1 + s.columnFromLeft] = '${s.digit}';
    }
  }
  if (!any) return null;
  return chars.join();
}

/// Lodret opstilling som på skolepapir: første tal, operator + andet tal, dobbelt streg.
/// [carryRowAbove] valgfri række med mente (fx tynd skrift) oven over øverste tal.
/// [belowDoubleRule] placeres med det samme højrejusterede underlag som cifrene (fx svarbokse).
class MathVerticalAddSubView extends StatelessWidget {
  const MathVerticalAddSubView({
    super.key,
    required this.parts,
    this.digitFontSize = 30,
    this.carryRowAbove,
    this.belowDoubleRule,
  });

  final MathAddSubParts parts;
  final double digitFontSize;
  final Widget? carryRowAbove;
  final Widget? belowDoubleRule;

  @override
  Widget build(BuildContext context) {
    final maxLen = parts.left.length > parts.right.length
        ? parts.left.length
        : parts.right.length;
    final topLine = ' ${parts.left.padLeft(maxLen)}';
    final bottomLine = '${parts.operator}${parts.right.padLeft(maxLen)}';

    final style = TextStyle(
      fontSize: digitFontSize,
      fontWeight: FontWeight.w700,
      height: 1.05,
      color: Colors.black87,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final columnW = mathVerticalColumnWidth(parts, digitFontSize);

    return Align(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (carryRowAbove != null) ...[
            SizedBox(width: columnW, child: carryRowAbove),
            const SizedBox(height: 4),
          ],
          mathAlignedDigitRow(
            line: topLine,
            columnWidth: columnW,
            style: style,
          ),
          const SizedBox(height: 4),
          mathAlignedDigitRow(
            line: bottomLine,
            columnWidth: columnW,
            style: style,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: columnW,
            child: const Column(
              children: [
                Divider(height: 1, thickness: 2, color: Colors.black87),
                SizedBox(height: 6),
                Divider(height: 1, thickness: 2, color: Colors.black87),
              ],
            ),
          ),
          if (belowDoubleRule != null) ...[
            const SizedBox(height: 10),
            SizedBox(width: columnW, child: belowDoubleRule),
          ],
        ],
      ),
    );
  }
}
