import 'package:flutter/foundation.dart' show kIsWeb;

import 'supabase_config_local.dart';

/// Supabase configuration.
/// Anon key kommer fra supabase_config_local.dart – rediger den fil med din key.
class SupabaseConfig {
  static const String url = 'https://bdsnfnwcnfnszgdqbapo.supabase.co';
  static String get anonKey => supabaseAnonKey;

  /// Deeplink efter email-bekræftelse / nulstilling af kodeord (iOS/Android).
  /// Skal tilføjes under Authentication → URL Configuration → Redirect URLs i Supabase
  /// (sammen med evt. Flutter web-URL). Må ikke kun være www.alfamon.dk hvis det er den gamle app.
  static const String authRedirectNative = 'alfamon://login-callback';

  /// redirect_to i bekræftelses- og reset-mail. På web: nuværende origin (hvidlist samme URL i Supabase).
  static String get authEmailRedirectTo =>
      kIsWeb ? Uri.base.origin : authRedirectNative;
}
