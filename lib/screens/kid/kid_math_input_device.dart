import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/widgets.dart';

import '../../utils/phone_layout.dart';

/// Indbygget 0–9-tastatur på iOS/Android (telefon og tablet). Desktop og web: almindeligt tastatur.
bool kidUseInAppNumericKeypad() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Smal skærm (typisk telefon). Bruges til touch-matematik-layout med plads til baggrund og tutor.
bool kidIsPhoneLayout(BuildContext context) => isPhoneLayout(context);
