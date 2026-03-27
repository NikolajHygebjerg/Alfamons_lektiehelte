import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/profile_role_provider.dart';
import '../../services/admin_app_users_service.dart';

/// Brugerliste + opret/slet/rolle (kun for [ProfileRoleProvider.isAdmin]).
class AdminUsersSettingsSection extends StatefulWidget {
  const AdminUsersSettingsSection({super.key});

  @override
  State<AdminUsersSettingsSection> createState() =>
      _AdminUsersSettingsSectionState();
}

class _AdminUsersSettingsSectionState extends State<AdminUsersSettingsSection> {
  List<AdminAppUserRow> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await AdminAppUsersService.listUsers();
      if (mounted) {
        setState(() {
          _users = list;
          _loading = false;
        });
      }
    } on FunctionException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.details?.toString() ?? e.reasonPhrase ?? '$e';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _createUser() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var role = 'user';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Ny bruger'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Adgangskode (min. 6 tegn)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(
                    labelText: 'Rolle',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'user',
                      child: Text('Almindelig bruger'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrator'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => role = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuller'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Opret'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;

    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;
    if (email.isEmpty || pass.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Udfyld email og adgangskode (min. 6 tegn).')),
        );
      }
      return;
    }

    try {
      await AdminAppUsersService.createUser(
        email: email,
        password: pass,
        appRole: role,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bruger oprettet')),
        );
        await _load();
      }
    } on FunctionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.details?.toString() ?? e.reasonPhrase ?? '$e'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _setRole(AdminAppUserRow row, String newRole) async {
    try {
      await AdminAppUsersService.setRole(
        authUserId: row.authUserId,
        appRole: newRole,
      );
      final selfId = Supabase.instance.client.auth.currentUser?.id;
      if (selfId == row.authUserId && mounted) {
        await context.read<ProfileRoleProvider>().refresh();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rolle opdateret')),
        );
        await _load();
      }
    } on FunctionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.details?.toString() ?? e.reasonPhrase ?? '$e'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(AdminAppUserRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet bruger?'),
        content: Text(
          'Slet konto og tilknyttede data for ${row.email}? Dette kan ikke fortrydes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuller'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await AdminAppUsersService.deleteUser(row.authUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bruger slettet')),
        );
        await _load();
      }
    } on FunctionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.details?.toString() ?? e.reasonPhrase ?? '$e'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF9C433).withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Brugerstyring',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Opdater liste',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Administratorer har adgang til alt (inkl. bogbuilder). '
              'Almindelige brugere har ikke adgang til bogbuilder eller denne liste.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ..._users.map((u) {
                final self =
                    u.authUserId == Supabase.instance.client.auth.currentUser?.id;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(u.email.isEmpty ? '(ingen email)' : u.email),
                    subtitle: Text(
                      u.appRole == 'admin'
                          ? 'Administrator'
                          : 'Almindelig bruger',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<String>(
                          value: u.appRole,
                          items: const [
                            DropdownMenuItem(
                              value: 'user',
                              child: Text('Almindelig'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Admin'),
                            ),
                          ],
                          onChanged: self
                              ? null
                              : (v) {
                                  if (v != null && v != u.appRole) {
                                    _setRole(u, v);
                                  }
                                },
                        ),
                        if (!self)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => _confirmDelete(u),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _loading ? null : _createUser,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Opret bruger'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
