import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

/// På web bruges [dart:io] ikke – fuldt lydbibliotek med optagelse findes på iOS/macOS.
class AdminAudioLibraryScreen extends StatelessWidget {
  const AdminAudioLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lydbibliotek'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/book-builder'),
        ),
        actions: const [
          AdminMenuToolbarButton(lightOnDark: false),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Lydbibliotek med mikrofon og filer understøttes i Alfamon på iPad, iPhone eller macOS – '
            'ikke i Chrome/browser. Kør appen der for at administrere lydfiler.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      ),
    );
  }
}
