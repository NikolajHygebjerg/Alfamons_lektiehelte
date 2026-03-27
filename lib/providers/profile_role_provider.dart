import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// [app_role] fra [profiles]: `admin` = bogbuilder + brugerstyring, ellers almindelig forælder-admin.
class ProfileRoleProvider extends ChangeNotifier {
  ProfileRoleProvider() {
    _sync();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => _sync());
  }

  String _role = 'user';
  bool _loaded = false;

  bool get isAdmin => _role == 'admin';
  bool get loaded => _loaded;

  Future<void> refresh() => _sync();

  Future<void> _sync() async {
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null) {
      if (kDebugMode) {
        debugPrint('ProfileRoleProvider: ingen currentUser → rolle=user');
      }
      _role = 'user';
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      String? r;
      var via = 'profiles';
      try {
        final res =
            await Supabase.instance.client.rpc('get_my_app_role');
        r = res?.toString().toLowerCase().trim();
        via = 'get_my_app_role';
      } catch (rpcErr, rpcSt) {
        if (kDebugMode) {
          debugPrint(
            'ProfileRoleProvider: RPC get_my_app_role fejlede, prøver profiles: $rpcErr\n$rpcSt',
          );
        }
        final row = await Supabase.instance.client
            .from('profiles')
            .select('app_role')
            .eq('auth_user_id', u.id)
            .maybeSingle();
        r = row?['app_role']?.toString().toLowerCase().trim();
      }
      _role = r == 'admin' ? 'admin' : 'user';
      if (kDebugMode) {
        debugPrint(
          'ProfileRoleProvider: supabaseUrl=${SupabaseConfig.url} '
          'uid=${u.id} email=${u.email} rawAppRole=${r ?? "(null)"} '
          'isAdmin=$isAdmin via=$via',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ProfileRoleProvider: kunne ikke læse app_role: $e\n$st');
      }
      _role = 'user';
    }
    _loaded = true;
    notifyListeners();
  }
}
