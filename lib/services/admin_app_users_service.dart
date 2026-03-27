import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAppUserRow {
  AdminAppUserRow({
    required this.authUserId,
    required this.email,
    required this.profileId,
    required this.appRole,
  });

  final String authUserId;
  final String email;
  final String? profileId;
  final String appRole;

  factory AdminAppUserRow.fromJson(Map<String, dynamic> m) {
    return AdminAppUserRow(
      authUserId: m['authUserId'] as String? ?? '',
      email: m['email'] as String? ?? '',
      profileId: m['profileId'] as String?,
      appRole: (m['app_role'] as String?) == 'admin' ? 'admin' : 'user',
    );
  }
}

/// Brugerstyring via Edge Function [admin-app-users] (kræver app_role admin).
class AdminAppUsersService {
  AdminAppUsersService._();

  static Future<List<AdminAppUserRow>> listUsers() async {
    final res = await Supabase.instance.client.functions.invoke(
      'admin-app-users',
      body: const {'action': 'list'},
    );
    final data = res.data;
    if (data is! Map) return [];
    final list = data['users'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => AdminAppUserRow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> createUser({
    required String email,
    required String password,
    required String appRole,
  }) async {
    await Supabase.instance.client.functions.invoke(
      'admin-app-users',
      body: {
        'action': 'create',
        'email': email.trim(),
        'password': password,
        'app_role': appRole,
      },
    );
  }

  static Future<void> setRole({
    required String authUserId,
    required String appRole,
  }) async {
    await Supabase.instance.client.functions.invoke(
      'admin-app-users',
      body: {
        'action': 'setRole',
        'authUserId': authUserId,
        'app_role': appRole,
      },
    );
  }

  static Future<void> deleteUser(String authUserId) async {
    await Supabase.instance.client.functions.invoke(
      'admin-app-users',
      body: {
        'action': 'delete',
        'authUserId': authUserId,
      },
    );
  }
}
