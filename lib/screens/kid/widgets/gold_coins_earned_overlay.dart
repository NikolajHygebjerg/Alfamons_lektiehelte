import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fuldskærm: bunke af [moent.png] + antal guldmønter.
/// PNG bruges fordi flutter_svg ikke tegner indlejret raster i .svg korrekt.
class GoldCoinsEarnedOverlay extends StatelessWidget {
  const GoldCoinsEarnedOverlay({
    super.key,
    required this.amount,
  });

  final int amount;

  @override
  Widget build(BuildContext context) {
    if (amount < 1) return const SizedBox.shrink();

    final rng = math.Random(42);
    const coinSize = 44.0;
    final visualCount = math.min(amount, 24);

    final screenW = MediaQuery.sizeOf(context).width;
    final stackW = math.min(screenW * 0.92, 420.0);
    const stackH = 220.0;
    final cx = stackW / 2;
    final cy = stackH / 2;

    final coins = <Widget>[];
    for (var i = 0; i < visualCount; i++) {
      final col = i % 6;
      final row = i ~/ 6;
      final dx = (col - 2.5) * 22.0 + rng.nextDouble() * 14 - 7;
      final dy = (row - 1.5) * 18.0 + rng.nextDouble() * 12 - 6;
      final rot = rng.nextDouble() * 0.55 - 0.275;
      coins.add(
        Positioned(
          left: cx - coinSize / 2 + dx,
          top: cy - coinSize / 2 + dy,
          child: Transform.rotate(
            angle: rot,
            child: Image.asset(
              'assets/moent.webp',
              width: coinSize,
              height: coinSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Icon(
                Icons.monetization_on,
                size: coinSize,
                color: const Color(0xFFF9C433),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.black54,
      clipBehavior: Clip.none,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: stackW,
                  height: stackH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: coins,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '+ $amount',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFF9C433),
                    shadows: [
                      Shadow(
                        offset: Offset(2, 2),
                        blurRadius: 6,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),
                const Text(
                  'GULDMØNTER',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 4,
                        color: Colors.black87,
                      ),
                    ],
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
