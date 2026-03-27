import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

class AdminAvatarsScreen extends StatelessWidget {
  const AdminAvatarsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatars'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: const [AdminMenuToolbarButton()],
      ),
      body: FutureBuilder(
        future: Supabase.instance.client
            .from('avatars')
            .select('id,name,letter')
            .order('name'),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data as List;
          if (list.isEmpty) {
            return const Center(
              child: Text('Ingen avatars. Tilføj via Supabase dashboard.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final a = list[i] as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(a['name'] as String? ?? ''),
                  subtitle: a['letter'] != null
                      ? Text('Bogstav: ${a['letter']}')
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
