import 'package:flutter/material.dart';

/// Én række med cifre 0–9 + valgfri tilbage-knap (indbygget tastatur, ingen systemtastatur).
class KidMathNumericKeypad extends StatelessWidget {
  const KidMathNumericKeypad({
    super.key,
    required this.onDigit,
    this.onBackspace,
    this.height = 54,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback? onBackspace;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      elevation: 8,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        child: SizedBox(
          height: height + (onBackspace != null ? 0 : 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                for (var d = 0; d <= 9; d++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _DigitKey(
                        digit: d,
                        onTap: () => onDigit(d),
                      ),
                    ),
                  ),
                if (onBackspace != null)
                  SizedBox(
                    width: 48,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: _DigitKey(
                        icon: Icons.backspace_outlined,
                        onTap: onBackspace!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({
    this.digit,
    this.icon,
    required this.onTap,
  }) : assert(digit != null || icon != null);

  final int? digit;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF3D3D3D),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 44,
          child: Center(
            child: digit != null
                ? Text(
                    '$digit',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}
