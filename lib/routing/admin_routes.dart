import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/kid.dart';
import '../screens/admin/admin_audio_library_screen.dart';
import '../screens/admin/admin_avatars_screen.dart';
import '../screens/admin/admin_bogbutik_screen.dart';
import '../screens/admin/admin_book_builder_screen.dart';
import '../screens/admin/admin_book_editor_screen.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/admin/admin_kid_edit_screen.dart';
import '../screens/admin/admin_kids_screen.dart';
import '../screens/admin/admin_math_screen.dart';
import '../screens/admin/admin_settings_screen.dart';
import '../screens/admin/admin_tasks_screen.dart';

/// Delt admin-træ til native-app og web-admin.
GoRoute adminRootRoute() {
  return GoRoute(
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
  );
}
