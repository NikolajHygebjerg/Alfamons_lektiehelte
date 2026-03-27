import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pil / log ud: på barnets **hjem** → forsiden (vælg admin/barn); ellers `pop` eller [fallbackLocation].
class KidSessionNavButton extends StatelessWidget {
  const KidSessionNavButton({
    super.key,
    required this.kidId,
    this.isHome = false,
    this.fallbackLocation,
  });

  final String kidId;
  final bool isHome;
  /// Bruges når `canPop` er false (fx direkte deep link). Fx `/kid/spil/$kidId`.
  final String? fallbackLocation;

  void _onPressed(BuildContext context) {
    if (isHome) {
      context.go('/');
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    final fallback = fallbackLocation ?? '/kid/today/$kidId';
    context.go(fallback);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: isHome ? 'Til forsiden' : 'Tilbage',
        icon: isHome
            ? Transform.flip(
                flipX: true,
                child: const Icon(
                  Icons.logout,
                  color: Colors.white,
                  size: 22,
                ),
              )
            : const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 22,
              ),
        onPressed: () => _onPressed(context),
      ),
    );
  }
}
