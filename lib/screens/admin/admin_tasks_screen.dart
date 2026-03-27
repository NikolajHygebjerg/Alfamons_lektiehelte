import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/task.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';
import '../../widgets/admin/task_emoji_picker_sheet.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key});

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  List<Task> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _parentId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    return profile?['id'] as String?;
  }

  Future<void> _load() async {
    final parentId = await _parentId();
    if (parentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final res = await Supabase.instance.client
        .from('tasks')
        .select('id,title,description,mode,points_fixed,points_per_unit,emoji')
        .eq('parent_id', parentId)
        .order('created_at');

    if (!mounted) return;
    setState(() {
      _tasks = (res as List).map((e) => Task.fromJson(Map<String, dynamic>.from(e))).toList();
      _loading = false;
    });
  }

  /// Bottom sheet så tastatur ikke skjuler point-feltet (AlertDialog-problem på mobil).
  Future<void> _openTaskEditor({Task? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final pointsStr = existing == null
        ? '10'
        : (existing.mode == 'fixed'
            ? '${existing.pointsFixed ?? 10}'
            : '${existing.pointsPerUnit ?? 10}');
    final pointsController = TextEditingController(text: pointsStr);
    var mode = existing?.mode ?? 'fixed';
    String? selectedEmoji = existing?.emoji;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: bottomInset + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      existing == null ? 'Opret opgave' : 'Rediger opgave',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Titel',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Beskrivelse (valgfri)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    const Text('Emoji på barnets skærm'),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        () {
                          final e = selectedEmoji?.trim();
                          return (e != null && e.isNotEmpty) ? e : '📋';
                        }(),
                        style: const TextStyle(fontSize: 36),
                      ),
                      title: Text(
                        () {
                          final e = selectedEmoji?.trim();
                          return (e != null && e.isNotEmpty)
                              ? 'Valgt emoji'
                              : 'Standard (📋) – tryk for at vælge';
                        }(),
                        style: Theme.of(ctx).textTheme.bodyLarge,
                      ),
                      subtitle: const Text(
                        'Vises stort øverst på opgavekortet for barnet',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final r = await showTaskEmojiPickerSheet(
                            ctx,
                            currentEmoji: selectedEmoji,
                          );
                          if (!ctx.mounted) return;
                          if (r == null) return;
                          setModal(() {
                            selectedEmoji = r.trim().isEmpty ? null : r.trim();
                          });
                        },
                        child: const Text('Vælg'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Type'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Fast point'),
                          selected: mode == 'fixed',
                          onSelected: (_) => setModal(() => mode = 'fixed'),
                        ),
                        ChoiceChip(
                          label: const Text('Tæller (point per enhed)'),
                          selected: mode == 'counter',
                          onSelected: (_) => setModal(() => mode = 'counter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pointsController,
                      decoration: InputDecoration(
                        labelText: mode == 'fixed' ? 'Antal point' : 'Point per enhed',
                        border: const OutlineInputBorder(),
                        helperText: mode == 'fixed'
                            ? 'Fast beløb når opgaven er færdig'
                            : 'Ganges med antal (fx skridt)',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuller'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Angiv en titel')),
                                );
                                return;
                              }
                              final pts = int.tryParse(pointsController.text);
                              if (pts == null || pts < 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Angiv et gyldigt antal point')),
                                );
                                return;
                              }
                              Navigator.pop(ctx, true);
                            },
                            child: Text(existing == null ? 'Opret' : 'Gem'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final title = titleController.text.trim();
    final desc = descController.text.trim();
    final pointsParsed = int.tryParse(pointsController.text);

    titleController.dispose();
    descController.dispose();
    pointsController.dispose();

    if (saved != true || !mounted) return;

    final parentId = await _parentId();
    if (parentId == null) return;

    final points = pointsParsed ?? 10;
    final emojiDb = selectedEmoji?.trim();
    final emojiPayload =
        (emojiDb != null && emojiDb.isNotEmpty) ? emojiDb : null;

    try {
      if (existing == null) {
        await Supabase.instance.client.from('tasks').insert({
          'parent_id': parentId,
          'title': title,
          'description': desc.isEmpty ? null : desc,
          'mode': mode,
          'points_fixed': mode == 'fixed' ? points : null,
          'points_per_unit': mode == 'counter' ? points : null,
          'emoji': emojiPayload,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Opgave oprettet')),
          );
        }
      } else {
        await Supabase.instance.client.from('tasks').update({
          'title': title,
          'description': desc.isEmpty ? null : desc,
          'mode': mode,
          'points_fixed': mode == 'fixed' ? points : null,
          'points_per_unit': mode == 'counter' ? points : null,
          'emoji': emojiPayload,
        }).eq('id', existing.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Opgave opdateret')),
          );
        }
      }
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _deleteTask(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet opgave?'),
        content: Text(
          '«${t.title}» slettes. Tildelinger til børn fjernes. '
          'Historik for tidligere udførte opgaver kan gøre sletning umulig – prøv igen eller kontakt support.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuller')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await Supabase.instance.client.from('recurring_tasks').delete().eq('task_id', t.id);
      await Supabase.instance.client.from('tasks').delete().eq('id', t.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opgave slettet')),
        );
        _load();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.contains('foreign key') || e.code == '23503'
                  ? 'Kan ikke slette: der findes stadig opgave-historik. Kontakt udvikler for at rydde databasen.'
                  : e.message,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opgaver'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: const [AdminMenuToolbarButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Ingen opgaver endnu.\nTryk + for at oprette.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks.length,
                  itemBuilder: (_, i) {
                    final t = _tasks[i];
                    final points = t.mode == 'fixed'
                        ? t.pointsFixed ?? 0
                        : t.pointsPerUnit ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(
                          t.displayEmoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                        title: Text(t.title),
                        subtitle: Text(
                          '${t.mode == "fixed" ? "Fast" : "Tæller"} • $points point'
                          '${t.description != null && t.description!.isNotEmpty ? '\n${t.description}' : ''}',
                        ),
                        isThreeLine: t.description != null && t.description!.isNotEmpty,
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) {
                            if (v == 'edit') _openTaskEditor(existing: t);
                            if (v == 'delete') _deleteTask(t);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'edit', child: Text('Rediger')),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Slet', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTaskEditor(),
        backgroundColor: const Color(0xFFF9C433),
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
