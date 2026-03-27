import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Går til app-hovedmenu (`/`). Bruges i admin-området.
class AdminMenuToolbarButton extends StatelessWidget {
  const AdminMenuToolbarButton({
    super.key,
    this.lightOnDark = true,
  });

  /// `true` når AppBar har mørk brun baggrund og hvid [foregroundColor].
  final bool lightOnDark;

  @override
  Widget build(BuildContext context) {
    final c = lightOnDark ? Colors.white : null;
    return TextButton.icon(
      onPressed: () => context.go('/'),
      icon: Icon(Icons.home_outlined, size: 20, color: c),
      label: Text('Menu', style: TextStyle(color: c)),
    );
  }
}
