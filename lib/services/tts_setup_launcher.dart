import 'package:android_intent_plus/android_intent.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';

/// Åbner bedst mulige system-skærm for tale/tekst-til-tale (platformafhængigt).
/// Returnerer `true` hvis vi mente, et skridt blev udført (åbning forsøgt).
Future<bool> openTtsOrSpeechSettings() async {
  if (kIsWeb) return false;

  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        // Nyere macOS: «Læs og tal» / Read & Speak (panelet hed tidligere «Talt indhold»).
        final candidates = [
          Uri.parse(
            'x-help-action://openPrefPane?bundleId=com.apple.Accessibility-Settings.extension?TextToSpeech',
          ),
          Uri.parse(
            'x-apple.systempreferences:com.apple.Accessibility-Settings.extension',
          ),
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.universalaccess',
          ),
        ];
        for (final uri in candidates) {
          try {
            final ok =
                await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (ok) return true;
          } catch (_) {}
        }
        return false;
      case TargetPlatform.windows:
        final primary = Uri.parse('ms-settings:speech');
        if (await canLaunchUrl(primary)) {
          return await launchUrl(primary, mode: LaunchMode.externalApplication);
        }
        final voices = Uri.parse('ms-settings:speech-voices');
        if (await canLaunchUrl(voices)) {
          return await launchUrl(voices, mode: LaunchMode.externalApplication);
        }
        return false;
      case TargetPlatform.android:
        await const AndroidIntent(
          action: 'android.settings.TTS_SETTINGS',
        ).launch();
        return true;
      case TargetPlatform.iOS:
        // iOS: åbn appens indstillinger; systemets stemmer findes under
        // Tilgængelighed → Talt indhold (se dialogtekst).
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  } catch (_) {
    return false;
  }
}
