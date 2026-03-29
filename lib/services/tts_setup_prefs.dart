import 'package:shared_preferences/shared_preferences.dart';

/// Gemmer, om den voksne har set TTS-intro og om vi skal minde ved brug af oplæsning.
class TtsSetupPrefs {
  static const _adminIntroDoneKey = 'tts_setup_admin_intro_v1_done';
  static const _remindWhenUsingKey = 'tts_setup_remind_when_using_v1';

  static Future<bool> isAdminIntroDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_adminIntroDoneKey) ?? false;
  }

  static Future<bool> shouldRemindWhenUsing() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_remindWhenUsingKey) ?? false;
  }

  /// Kaldes efter første admin-dialog (alle valg).
  static Future<void> completeAdminIntro({
    required bool remindWhenUsing,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_adminIntroDoneKey, true);
    await p.setBool(_remindWhenUsingKey, remindWhenUsing);
  }

  static Future<void> clearRemindWhenUsing() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_remindWhenUsingKey, false);
  }
}
