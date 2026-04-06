import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/kid.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';
import '../../widgets/asset_or_network_image.dart';

class AdminKidsScreen extends StatefulWidget {
  const AdminKidsScreen({super.key});

  @override
  State<AdminKidsScreen> createState() => _AdminKidsScreenState();
}

class _AdminKidsScreenState extends State<AdminKidsScreen> {
  List<Kid> _kids = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() {
        _kids = [];
        _loading = false;
      });
      return;
    }

    final profile = await client
        .from('profiles')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    final parentId = profile?['id'] as String?;

    if (parentId == null) {
      setState(() {
        _kids = [];
        _loading = false;
      });
      return;
    }

    final res = await client
        .from('kids')
        .select('id,name,avatar_url,pin_code')
        .eq('parent_id', parentId)
        .order('created_at');

    if (!mounted) return;
    setState(() {
      _kids = (res as List).map((e) => Kid.fromJson(e)).toList();
      _loading = false;
    });
  }

  Future<void> _addKid() async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tilføj barn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Navn'),
            ),
            TextField(
              controller: pinController,
              decoration: const InputDecoration(
                labelText: 'PIN (valgfrit, 4 cifre)',
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuller'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tilføj'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    final parentId = profile?['id'];
    if (parentId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil ikke fundet. Opret venligst en profil først.')),
        );
      }
      return;
    }

    final pin = pinController.text.trim();
    await Supabase.instance.client.from('kids').insert({
      'parent_id': parentId,
      'name': nameController.text.trim(),
      'pin_code': pin.isEmpty ? null : pin,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barn tilføjet')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Børn'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: const [AdminMenuToolbarButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _kids.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      color: const Color(0xFFF9E8B0),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => context.go('/kid/select'),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.swap_horiz, color: Color(0xFF5A1A0D)),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Skift barn',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF5A1A0D),
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Color(0xFF5A1A0D)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final k = _kids[i - 1];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: ClipOval(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: k.avatarUrl != null && k.avatarUrl!.trim().isNotEmpty
                            ? AssetOrNetworkImage(
                                src: k.avatarUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : const ColoredBox(
                                color: Color(0xFFE0E0E0),
                                child: Icon(Icons.person, color: Colors.black45),
                              ),
                      ),
                    ),
                    title: Text(k.name),
                    subtitle: k.pinCode != null ? const Text('PIN beskyttet') : null,
                    onTap: () => context.push('/admin/kids/edit/${k.id}', extra: k),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addKid,
        backgroundColor: const Color(0xFFF9C433),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
