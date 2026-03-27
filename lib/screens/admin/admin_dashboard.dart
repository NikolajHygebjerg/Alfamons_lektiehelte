import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/profile_role_provider.dart';
import '../../widgets/parent_code_first_setup_dialog.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileRoleProvider>().refresh();
      ParentCodeFirstSetupDialog.showIfNeeded(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canAccessBookBuilder =
        context.watch<ProfileRoleProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: [
          const AdminMenuToolbarButton(),
          TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.logout, color: Colors.white, size: 20),
            label: const Text('Log ud', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A1A0D), Color(0xFFE85A4A)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _AdminTile(
              icon: Icons.child_care,
              title: 'Børn',
              subtitle: 'Administrer børn og PIN-koder',
              onTap: () => context.push('/admin/kids'),
            ),
            _AdminTile(
              icon: Icons.task_alt,
              title: 'Opgaver',
              subtitle: 'Opret og tildel opgaver',
              onTap: () => context.push('/admin/tasks'),
            ),
            _AdminTile(
              icon: Icons.calculate,
              title: 'Matematik',
              subtitle: 'Mapper, opgaver og guldmønter pr. mappe',
              onTap: () => context.push('/admin/math'),
            ),
            _AdminTile(
              icon: Icons.store,
              title: 'Bogbutik',
              subtitle: 'Køb Læs-let bøger til børnene',
              onTap: () => context.push('/admin/bogbutik'),
            ),
            if (canAccessBookBuilder)
              _AdminTile(
                icon: Icons.menu_book,
                title: 'Bogbuilder',
                subtitle: 'Byg Læs-let bøger til bogbutikken',
                onTap: () => context.push('/admin/book-builder'),
              ),
            _AdminTile(
              icon: Icons.verified_user,
              title: 'Godkend opgaver',
              subtitle: 'Godkend afventende opgaver',
              onTap: () => context.push('/admin/approvals'),
            ),
            _AdminTile(
              icon: Icons.settings,
              title: 'Indstillinger',
              subtitle: 'Konto og app',
              onTap: () => context.push('/admin/settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFF9C433).withOpacity(0.9),
      child: ListTile(
        leading: Icon(icon, size: 40),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}
