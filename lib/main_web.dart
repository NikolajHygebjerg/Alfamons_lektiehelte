import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/auth_provider.dart';
import 'providers/profile_role_provider.dart';
import 'routing/web_admin_router.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

/// Web: kun forælder-admin (ingen Alfamon Trace, ingen barn-UI, intet Riverpod trace-storage).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseService.init();

  final prefs = await SharedPreferences.getInstance();
  final stayLoggedIn = prefs.getBool('stayLoggedIn') ?? true;
  if (!stayLoggedIn && Supabase.instance.client.auth.currentSession != null) {
    await Supabase.instance.client.auth.signOut();
  }

  final authProvider = AuthProvider();
  await NotificationService.init();

  runApp(
    ProviderScope(
      child: AlfamonWebApp(authProvider: authProvider),
    ),
  );
}

class AlfamonWebApp extends StatelessWidget {
  const AlfamonWebApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ProfileRoleProvider>(
          create: (_) => ProfileRoleProvider(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Alfamons lektiehelte – admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF9C433)),
          useMaterial3: true,
        ),
        routerConfig: buildWebAdminRouter(
          authProvider: authProvider,
          navigatorKey: _navigatorKey,
        ),
      ),
    );
  }
}
