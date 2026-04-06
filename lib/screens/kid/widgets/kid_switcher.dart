import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/alfamon_evolution.dart';

class KidInfo {
  final String id;
  final String name;
  final String? pinCode;

  KidInfo({required this.id, required this.name, this.pinCode});

  factory KidInfo.fromJson(Map<String, dynamic> json) {
    return KidInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      pinCode: json['pin_code'] as String?,
    );
  }
}

class KidSwitcher extends StatefulWidget {
  final List<KidInfo> kids;
  final String kidId;
  final void Function(String?) onChanged;

  const KidSwitcher({
    super.key,
    required this.kids,
    required this.kidId,
    required this.onChanged,
  });

  @override
  State<KidSwitcher> createState() => _KidSwitcherState();
}

class _KidSwitcherState extends State<KidSwitcher> {
  final Map<String, String> _avatarUrls = {};

  @override
  void initState() {
    super.initState();
    _loadAvatars();
  }

  Future<void> _loadAvatars() async {
    for (final kid in widget.kids) {
      final active = await Supabase.instance.client
          .from('kid_active_avatar')
          .select('avatar_id,points_current')
          .eq('kid_id', kid.id)
          .maybeSingle();

      if (active != null && active['avatar_id'] != null) {
        final avatarId = active['avatar_id'] as String;

        final libRes = await Supabase.instance.client
            .from('kid_avatar_library')
            .select('points_current')
            .eq('kid_id', kid.id)
            .eq('avatar_id', avatarId)
            .maybeSingle();

        final points = libRes != null
            ? AlfamonEvolution.pointsFromJson(libRes['points_current'])
            : AlfamonEvolution.pointsFromJson(active['points_current']);

        final stagesRes = await Supabase.instance.client
            .from('avatar_stages')
            .select('stage_index')
            .eq('avatar_id', avatarId)
            .order('stage_index');

        final sorted =
            AlfamonEvolution.sortedStageIndicesFromRows(stagesRes as List);
        final stageIndex = AlfamonEvolution.stageIndexFromPoints(points, sorted);

        final stage = await Supabase.instance.client
            .from('avatar_stages')
            .select('image_url')
            .eq('avatar_id', avatarId)
            .eq('stage_index', stageIndex)
            .maybeSingle();

        if (stage != null && stage['image_url'] != null) {
          setState(() => _avatarUrls[kid.id] = stage['image_url'] as String);
        }
      }
    }
  }

  Future<void> _selectKid(String id) async {
    final kid = widget.kids.firstWhere((k) => k.id == id);
    bool stayLoggedIn = true;
    if (kid.pinCode != null && kid.pinCode!.isNotEmpty) {
      final controller = TextEditingController();
      bool stayLoggedInValue = true;
      final result = await showDialog<({bool ok, bool stayLoggedIn})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Indtast PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: '4-cifret PIN',
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: stayLoggedInValue,
                  onChanged: (v) => setState(() => stayLoggedInValue = v ?? true),
                  title: const Text('Forbliv logget ind'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, (ok: false, stayLoggedIn: false)),
                child: const Text('Annuller'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, (ok: true, stayLoggedIn: stayLoggedInValue)),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      if (result == null || !result.ok) return;
      if (controller.text != kid.pinCode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Forkert PIN')),
          );
        }
        return;
      }
      stayLoggedIn = result.stayLoggedIn;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kidId', id);
    await prefs.setBool('kidStayLoggedIn', stayLoggedIn);

    if (mounted) {
      context.go('/kid/today/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: widget.kids.map((k) {
          final selected = widget.kidId == k.id;
          final url = _avatarUrls[k.id];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: selected ? Colors.green.shade100 : Colors.white24,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _selectKid(k.id),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: url != null ? NetworkImage(url) : null,
                        child: url == null ? const Icon(Icons.person) : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        k.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selected ? Colors.green.shade900 : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
