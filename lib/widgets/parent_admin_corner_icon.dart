import 'package:flutter/material.dart';

/// Voksen/forældre-admin — billede: `assets/foraeldreadminikon.webp`.
class ParentAdminCornerIcon extends StatelessWidget {
  const ParentAdminCornerIcon({
    super.key,
    required this.onPressed,
    this.size = 44,
  });

  final VoidCallback onPressed;
  final double size;

  static const String _assetPng = 'assets/foraeldreadminikon.webp';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Voksen-admin',
        icon: Image.asset(
          _assetPng,
          width: size * 0.58,
          height: size * 0.58,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.admin_panel_settings_outlined,
            color: Colors.white,
            size: size * 0.5,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
