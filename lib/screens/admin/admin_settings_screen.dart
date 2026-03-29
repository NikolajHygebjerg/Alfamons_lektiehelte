import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../providers/profile_role_provider.dart';
import '../../services/parent_code_service.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';
import '../../widgets/admin/admin_users_settings_section.dart';
import '../../widgets/tts_setup_intro_dialog.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileRoleProvider>().refresh();
    });
    _loadApprovalCode();
  }

  Future<void> _loadApprovalCode() async {
    final existing = await ParentCodeService.fetchApprovalCode();
    if (mounted) {
      _codeController.text = existing ?? '';
    }
  }

  Future<void> _saveApprovalCode() async {
    final code = _codeController.text.trim();
    if (!ParentCodeService.isValidFormat(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forældrekode skal være præcis 4 cifre')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ParentCodeService.saveApprovalCode(code);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forældrekode gemt')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny adgangskode'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: p1,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Ny adgangskode'),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return 'Mindst 6 tegn';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: p2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Gentag adgangskode'),
                validator: (v) {
                  if (v != p1.text) return 'Adgangskoder matcher ikke';
                  return null;
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
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Gem'),
          ),
        ],
      ),
    );

    if (save != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: p1.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adgangskode opdateret')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    } finally {
      p1.dispose();
      p2.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showChangeEmailDialog() async {
    final user = Supabase.instance.client.auth.currentUser;
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skift email'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Du kan få en bekræftelsesmail på den nye adresse. Tjek indbakken.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Ny email'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Påkrævet';
                  if (!v.contains('@')) return 'Ugyldig email';
                  return null;
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
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Gem'),
          ),
        ],
      ),
    );

    if (save != true || !mounted) {
      emailCtrl.dispose();
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: emailCtrl.text.trim()),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email opdateret – tjek evt. bekræftelsesmail.'),
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    } finally {
      emailCtrl.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmCtrl = TextEditingController();

    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet konto permanent?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Dette sletter din Alfamon-konto, dine børneprofiler og data der er knyttet til kontoen (opgaver, matematikmapper, bogkæb m.m.). '
                'Det kan ikke fortrydes.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(
                  labelText: 'Skriv SLET for at bekræfte',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              if (confirmCtrl.text.trim().toUpperCase() != 'SLET') {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Skriv præcis SLET for at bekræfte.'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Slet konto'),
          ),
        ],
      ),
    );

    confirmCtrl.dispose();
    if (go != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final details = e.details?.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              details?.isNotEmpty == true
                  ? 'Kunne ikke slette: $details'
                  : 'Kunne ikke slette konto (tjek at serverfunktionen er installeret).',
            ),
          ),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('kidId');
      await prefs.remove('kidStayLoggedIn');
      if (!mounted) return;
      await context.read<AuthProvider>().signOut();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Din konto er slettet.')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) context.go('/auth');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email =
        Supabase.instance.client.auth.currentUser?.email ?? '—';
    final showUserMgmt = context.watch<ProfileRoleProvider>().isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Indstillinger'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: const [AdminMenuToolbarButton()],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (showUserMgmt) ...[
                const AdminUsersSettingsSection(),
                const SizedBox(height: 16),
              ],
              Card(
                color: const Color(0xFFF9C433).withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Konto',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Email'),
                        subtitle: Text(email),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _loading ? null : _showChangeEmailDialog,
                            child: const Text('Skift email'),
                          ),
                          OutlinedButton(
                            onPressed: _loading ? null : _showChangePasswordDialog,
                            child: const Text('Ny adgangskode'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Slet konto',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fjern din konto og tilknyttede data i appen. Kræver netværksforbindelse.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _deleteAccount,
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Slet min konto'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: const Color(0xFFF9C433).withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Forældrekode',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '4 cifre – bruges når børn færdiggør opgaver, ved godkendelse og ved point for læsning. Du satte koden første gang du loggede ind; her kan du ændre den.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Forældrekode',
                          border: OutlineInputBorder(),
                          hintText: 'fx 1234',
                          counterText: '',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loading ? null : _saveApprovalCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5A1A0D),
                          foregroundColor: Colors.white,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Gem forældrekode'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: const Color(0xFFF9C433).withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Matematikhjælp',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Oplæsning af hjælpetekst kræver dansk tekst-til-tale (stemme) '
                        'på enheden.',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.record_voice_over_outlined),
                        title: const Text('Tale og systemstemmer'),
                        subtitle: const Text(
                          'Vejledning og åbn Systemindstillinger (dialog kan blive åben på Mac)',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            TtsSetupIntro.showFromAdminSettings(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const ListTile(
                title: Text('Alfamon-oplåsningskode'),
                subtitle: Text(
                  '4-cifret kode til at låse ABC-bogstaver op. Konfigureres i Supabase.',
                ),
              ),
            ],
          ),
          if (_loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
