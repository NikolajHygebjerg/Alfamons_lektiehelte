import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Smal skærm (typisk telefon). Samme tærskel som øvrige kid-layouts (600 dp).
bool isPhoneLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide < 600;
}

/// Hele appen kører i landskab (venstre/højre) — fastholdes ved ruteskift.
Future<void> applyPhoneAuthAdminOrientations(
  BuildContext context,
  String _,
) async {
  if (kIsWeb) return;
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
