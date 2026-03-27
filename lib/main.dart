import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/auth_provider.dart';
import 'providers/profile_role_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/admin_kids_screen.dart';
import 'screens/admin/admin_kid_edit_screen.dart';
import 'models/kid.dart';
import 'screens/admin/admin_tasks_screen.dart';
import 'screens/admin/admin_math_screen.dart';
import 'screens/admin/admin_avatars_screen.dart';
import 'screens/admin/admin_settings_screen.dart';
import 'screens/admin/admin_approvals_screen.dart';
import 'screens/admin/admin_audio_library_screen.dart';
import 'screens/admin/admin_book_builder_screen.dart';
import 'screens/admin/admin_book_editor_screen.dart';
import 'screens/admin/admin_bogbutik_screen.dart';
import 'screens/kid/kid_select_screen.dart';
import 'screens/kid/kid_today_screen.dart';
import 'screens/kid/kid_tasks_screen.dart';
import 'screens/kid/kid_math_browse_screen.dart';
import 'screens/kid/kid_math_play_screen.dart';
import 'screens/kid/kid_week_screen.dart';
import 'screens/kid/kid_library_screen.dart';
import 'screens/kid/kid_library_group_screen.dart';
import 'screens/kid/kid_alfamons_screen.dart';
import 'screens/kid/kid_book_reader_screen.dart';
import 'screens/kid/kid_achievements_screen.dart';
import 'screens/kid/kid_spil_screen.dart';
import 'screens/kid/kid_spil_pvp_screen.dart';
import 'screens/kid/kid_spil_mode_screen.dart';
import 'screens/kid/kid_spil_ven_screen.dart';
import 'services/audio_cache_service.dart';
import 'services/supabase_service.dart';
import 'services/kid_invitation_service.dart';
import 'services/kid_turn_notification_service.dart';
import 'services/notification_service.dart';
import 'widgets/pending_challenge_handler.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
String? _startupKidId;
bool _startupKidStayLoggedIn = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  await SupabaseService.init();

  // Hvis bruger valgte "Forbliv ikke logget ind", log ud ved app-start
  final prefs = await SharedPreferences.getInstance();
  final stayLoggedIn = prefs.getBool('stayLoggedIn') ?? true;
  if (!stayLoggedIn && Supabase.instance.client.auth.currentSession != null) {
    await Supabase.instance.client.auth.signOut();
  }

  // Hvis barn valgte "Forbliv ikke logget ind", ryd gemt barn ved app-start
  final kidStayLoggedIn = prefs.getBool('kidStayLoggedIn') ?? true;
  if (!kidStayLoggedIn) {
    await prefs.remove('kidId');
  }
  _startupKidStayLoggedIn = kidStayLoggedIn;
  _startupKidId = kidStayLoggedIn ? prefs.getString('kidId') : null;

  final authProvider = AuthProvider();
  KidInvitationService.init(_navigatorKey);
  if (Supabase.instance.client.auth.currentSession != null) {
    unawaited(AudioCacheService.syncAll());
  }
  KidTurnNotificationService.init(_navigatorKey);
  await NotificationService.init();
  runApp(AlfamonApp(authProvider: authProvider));
}

class AlfamonApp extends StatelessWidget {
  const AlfamonApp({super.key, required this.authProvider});
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
      child: PendingChallengeHandler(
        navigatorKey: _navigatorKey,
        child: MaterialApp.router(
          title: 'Alfamon',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF9C433)),
            useMaterial3: true,
          ),
          routerConfig: _router(authProvider),
        ),
      ),
    );
  }
}

GoRouter _router(AuthProvider authProvider) => GoRouter(
  navigatorKey: _navigatorKey,
  initialLocation: '/',
  refreshListenable: authProvider,
  redirect: (context, state) {
    final auth = context.read<AuthProvider>();
    final isAuth = auth.isAuthenticated;
    final isAuthRoute = state.matchedLocation == '/auth';

    if (!isAuth && !isAuthRoute) return '/auth';
    if (isAuth && isAuthRoute) return '/';
    return null;
  },
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final path = state.matchedLocation;
        var kidId = state.pathParameters['kidId'];
        if (kidId == null && path.startsWith('/kid/') && path != '/kid/select') {
          final match = RegExp(r'^/kid/[^/]+/([^/]+)').firstMatch(path);
          kidId = match?.group(1);
        }

        KidTurnNotificationService.updateCurrentRoute(path);

        if (path == '/auth' || path.startsWith('/admin')) {
          KidInvitationService.stop();
          KidTurnNotificationService.stop();
        } else if (path.startsWith('/kid/') && path != '/kid/select' && kidId != null) {
          KidInvitationService.start(kidId);
          KidTurnNotificationService.start(kidId);
        } else if (path == '/' || path == '/kid/select') {
          final storedKidId = _startupKidId;
          final stayLoggedIn = _startupKidStayLoggedIn;
          if (storedKidId != null && stayLoggedIn) {
            KidInvitationService.start(storedKidId);
            KidTurnNotificationService.start(storedKidId);
          } else {
            KidInvitationService.stop();
            KidTurnNotificationService.stop();
          }
        } else if (path.startsWith('/kid/') && path != '/kid/select' && kidId == null) {
          // Fail-safe: undgå stale subscriptions når ruten ikke giver kidId.
          KidInvitationService.stop();
          KidTurnNotificationService.stop();
        } else if (!path.startsWith('/kid/')) {
          KidInvitationService.stop();
          KidTurnNotificationService.stop();
        }
        return child;
      },
      routes: [
    GoRoute(
      path: '/auth',
      builder: (_, __) => const AuthScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/admin',
      builder: (_, __) => const AdminDashboard(),
      routes: [
        GoRoute(
          path: 'kids',
          builder: (_, __) => const AdminKidsScreen(),
          routes: [
            GoRoute(
              path: 'edit/:kidId',
              builder: (context, state) {
                final kidId = state.pathParameters['kidId']!;
                final kid = state.extra as Kid?;
                if (kid == null) {
                  return const Scaffold(
                    body: Center(child: Text('Barn ikke fundet')),
                  );
                }
                return AdminKidEditScreen(kid: kid);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'tasks',
          builder: (_, __) => const AdminTasksScreen(),
        ),
        GoRoute(
          path: 'math',
          builder: (_, __) => const AdminMathScreen(),
          routes: [
            GoRoute(
              path: 'folder/:folderId',
              builder: (context, state) => AdminMathScreen(
                folderId: state.pathParameters['folderId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'avatars',
          builder: (_, __) => const AdminAvatarsScreen(),
        ),
        GoRoute(
          path: 'settings',
          builder: (_, __) => const AdminSettingsScreen(),
        ),
        GoRoute(
          path: 'approvals',
          builder: (_, __) => const AdminApprovalsScreen(),
        ),
        GoRoute(
          path: 'bogbutik',
          builder: (_, __) => const AdminBogbutikScreen(),
        ),
        GoRoute(
          path: 'book-builder',
          builder: (_, __) => const AdminBookBuilderScreen(),
          routes: [
            GoRoute(
              path: 'lydbibliotek',
              builder: (_, __) => const AdminAudioLibraryScreen(),
            ),
            GoRoute(
              path: 'edit/:bookId',
              builder: (context, state) {
                final bookId = state.pathParameters['bookId']!;
                return AdminBookEditorScreen(bookId: bookId);
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/kid/select',
      builder: (_, __) => const KidSelectScreen(),
    ),
    GoRoute(
      path: '/kid/today/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidTodayScreen(kidId: kidId);
      },
    ),
    GoRoute(
      path: '/kid/tasks/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidTasksScreen(kidId: kidId);
      },
    ),
    GoRoute(
      path: '/kid/math/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidMathBrowseScreen(kidId: kidId);
      },
      routes: [
        GoRoute(
          path: 'folder/:folderId',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            final folderId = state.pathParameters['folderId']!;
            return KidMathBrowseScreen(kidId: kidId, folderId: folderId);
          },
        ),
        GoRoute(
          path: 'play/:folderId',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            final folderId = state.pathParameters['folderId']!;
            return KidMathPlayScreen(kidId: kidId, folderId: folderId);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/kid/week/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidWeekScreen(kidId: kidId);
      },
    ),
    GoRoute(
      path: '/kid/alfamons/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidAlfamonsScreen(kidId: kidId);
      },
    ),
    GoRoute(
      path: '/kid/library/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidLibraryScreen(kidId: kidId);
      },
      routes: [
        GoRoute(
          path: 'book/:bookId',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            final bookId = state.pathParameters['bookId']!;
            return KidBookReaderScreen(kidId: kidId, bookId: bookId);
          },
        ),
        GoRoute(
          path: 'group/:groupId',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            final groupId = state.pathParameters['groupId']!;
            return KidLibraryGroupScreen(kidId: kidId, groupId: groupId);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/kid/achievements/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidAchievementsScreen(kidId: kidId);
      },
    ),
    GoRoute(
      path: '/kid/spil/:kidId',
      builder: (context, state) {
        final kidId = state.pathParameters['kidId']!;
        return KidSpilModeScreen(kidId: kidId);
      },
      routes: [
        GoRoute(
          path: 'computer',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            final computerMatchId = state.uri.queryParameters['matchId'];
            return KidSpilScreen(kidId: kidId, computerMatchId: computerMatchId);
          },
        ),
        GoRoute(
          path: 'ven',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            return KidSpilVenScreen(kidId: kidId);
          },
        ),
        GoRoute(
          path: 'pvp/:matchId',
          builder: (context, state) {
            final kidId = state.pathParameters['kidId']!;
            final matchId = state.pathParameters['matchId']!;
            return KidSpilPvpScreen(kidId: kidId, matchId: matchId);
          },
        ),
      ],
    ),
      ],
    ),
  ],
);
