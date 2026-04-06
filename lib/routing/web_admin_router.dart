import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/auth_screen.dart';
import '../screens/home/home_screen.dart';
import 'admin_routes.dart';

/// Kun login, home (omdirigering) og forældre-admin — ingen barn-ruter.
GoRouter buildWebAdminRouter({
  required AuthProvider authProvider,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path.startsWith('/kid')) {
        return '/admin';
      }

      final auth = context.read<AuthProvider>();
      final isAuth = auth.isAuthenticated;
      final isAuthRoute = state.matchedLocation == '/auth';

      if (!isAuth && !isAuthRoute) return '/auth';
      if (isAuth && isAuthRoute) return '/';
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => child,
        routes: [
          GoRoute(
            path: '/auth',
            builder: (_, __) => const AuthScreen(),
          ),
          GoRoute(
            path: '/',
            builder: (_, __) => const HomeScreen(),
          ),
          adminRootRoute(),
        ],
      ),
    ],
  );
}
