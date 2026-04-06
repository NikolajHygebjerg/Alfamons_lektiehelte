import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Kiste + antal guldmønter (nederst til **højre** på fx «I dag» – brug `kidZoneHorizontalPadding` (20) fra `kid_layout_constants.dart`).
/// Tryk åbner Alfamons-siden. [onAfterAlfamonsRoute] køres når man kommer tilbage (fx opfrisk guld).
/// Bruger [kiste.webp] — ingen Alfamon-forhåndsvisning her (kun statisk kiste + tal).
class KidGoldTreasuryCorner extends StatelessWidget {
  const KidGoldTreasuryCorner({
    super.key,
    required this.kidId,
    required this.goldCoins,
    this.onAfterAlfamonsRoute,
  });

  final String kidId;
  final int goldCoins;
  final Future<void> Function()? onAfterAlfamonsRoute;

  Future<void> _openAlfamons(BuildContext context) async {
    await context.push('/kid/alfamons/$kidId');
    if (!context.mounted) return;
    await onAfterAlfamonsRoute?.call();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final chestW = (screenW * 0.2).clamp(72.0, 220.0);

    const textShadows = [
      Shadow(
        offset: Offset(1, 1),
        blurRadius: 4,
        color: Colors.black87,
      ),
    ];

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.none,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAlfamons(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/kiste.webp',
              width: chestW,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => SizedBox(
                width: chestW,
                height: chestW * 0.85,
                child: Icon(
                  Icons.inventory_2,
                  size: chestW * 0.5,
                  color: Colors.amber,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: chestW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$goldCoins',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: textShadows,
                      ),
                    ),
                  ),
                  Text(
                    'GULDMØNTER',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
