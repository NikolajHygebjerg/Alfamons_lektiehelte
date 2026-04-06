import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'parent_admin_corner_icon.dart';
import 'parent_code_verify_dialog.dart';

/// Åbn voksen-admin efter forældrekode (bruges fra barnets skærme).
Future<void> openKidParentAdminRoute(BuildContext context) async {
  final ok = await showParentCodeVerificationDialog(
    context,
    title: 'Voksen-admin',
    explanation:
        'Indtast den 4-cifrede forældrekode for at åbne voksen-administration.',
  );
  if (ok && context.mounted) {
    context.push('/admin');
  }
}

/// Ikon øverst til højre — samme adfærd på tværs af børneflows.
class KidParentAdminCornerButton extends StatelessWidget {
  const KidParentAdminCornerButton({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ParentAdminCornerIcon(
      size: size,
      onPressed: () => unawaited(openKidParentAdminRoute(context)),
    );
  }
}
