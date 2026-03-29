import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/kid.dart';
import '../../services/math_tasks_service.dart';
import '../../utils/math_task_parse.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

class AdminMathScreen extends StatefulWidget {
  const AdminMathScreen({super.key, this.folderId});

  /// `null` = rodniveau under `/admin/math`; ellers undermappe-id.
  final String? folderId;

  @override
  State<AdminMathScreen> createState() => _AdminMathScreenState();
}

class _AdminMathScreenState extends State<AdminMathScreen> {
  String? _profileId;
  List<MathFolderRow> _folders = [];
  List<MathTaskRow> _tasks = [];
  List<Kid> _kids = [];
  MathFolderRow? _currentFolderMeta;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profileId = await MathTasksService.currentProfileId();
      if (!mounted) return;
      if (profileId == null) {
        setState(() {
          _profileId = null;
          _loading = false;
        });
        return;
      }

      final user = Supabase.instance.client.auth.currentUser;
      final kidsRes = user == null
          ? <dynamic>[]
          : await Supabase.instance.client
              .from('kids')
              .select('id,name,pin_code,avatar_url')
              .eq('parent_id', profileId)
              .order('created_at');

      final folders = await MathTasksService.fetchChildFolders(
        profileId: profileId,
        parentId: widget.folderId,
      );
      List<MathTaskRow> tasks = [];
      MathFolderRow? meta;
      if (widget.folderId != null) {
        tasks = await MathTasksService.fetchTasks(widget.folderId!);
        final row = await Supabase.instance.client
            .from('math_folders')
            .select(
              'id,parent_id,title,gold_coins_per_task,math_help_gold_cost,sort_order',
            )
            .eq('id', widget.folderId!)
            .maybeSingle();
        if (row != null) {
          meta = Map<String, dynamic>.from(row);
        }
      }

      if (!mounted) return;
      setState(() {
        _profileId = profileId;
        _folders = folders;
        _tasks = tasks;
        _kids = [
          for (final e in kidsRes) Kid.fromJson(Map<String, dynamic>.from(e)),
        ];
        _currentFolderMeta = meta;
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('AdminMathScreen._load: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _folders = [];
        _tasks = [];
        _kids = [];
        _currentFolderMeta = null;
        _loadError = MathTasksService.describeLoadError(e);
        _loading = false;
      });
    }
  }

  String _folderTitle() {
    if (widget.folderId == null) return 'Matematik';
    return _currentFolderMeta?['title'] as String? ?? 'Mappe';
  }

  Future<void> _addFolder() async {
    final profileId = _profileId;
    if (profileId == null) return;
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny mappe'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Navn',
            hintText: 'Fx Plusopgaver',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuller')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Opret'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await MathTasksService.createFolder(
        profileId: profileId,
        title: name,
        parentId: widget.folderId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mappe oprettet')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fejl: $e')));
      }
    }
  }

  Future<void> _addTask() async {
    if (widget.folderId == null) return;
    final c = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tilføj opgaver'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Én opgave per linje med lighedstegn, fx:\n'
                '1+1=2\n'
                '12 - 3 = 9\n\n'
                'Du kan indsætte mange linjer på én gang.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                decoration: const InputDecoration(
                  labelText: 'Opgaver',
                  hintText: '1+2=3\n3+4=7',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                autofocus: true,
                keyboardType: TextInputType.multiline,
                minLines: 8,
                maxLines: 18,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuller')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Gem'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    final bulk = parseMathTaskPaste(raw);
    if (bulk.tasks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingen gyldige linjer. Brug: regnestykke=svar (med =) pr. linje.'),
          ),
        );
      }
      return;
    }
    try {
      await MathTasksService.addTasks(
        folderId: widget.folderId!,
        items: [
          for (final t in bulk.tasks) (prompt: t.prompt, answer: t.answer),
        ],
      );
      await _load();
      if (!mounted) return;
      final n = bulk.tasks.length;
      var msg = '$n opgave${n == 1 ? '' : 'r'} tilføjet';
      if (bulk.invalidCount > 0) {
        final extra = bulk.invalidSamples.isEmpty
            ? ''
            : ' — fx: ${bulk.invalidSamples.take(2).join('; ')}';
        final more = bulk.invalidCount > bulk.invalidSamples.length ? ' …' : '';
        msg += '. ${bulk.invalidCount} linje${bulk.invalidCount == 1 ? '' : 'r'} ugyldig$extra$more';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fejl: $e')));
      }
    }
  }

  Future<void> _openFolderSettings(String folderId) async {
    final profileId = _profileId;
    if (profileId == null) return;
    final allFolders = await MathTasksService.fetchAllFolders(profileId);
    final folderById = <String, MathFolderRow>{
      for (final f in allFolders) f['id'] as String: f,
    };
    final row = folderById[folderId];
    if (row == null) return;
    final title = row['title'] as String? ?? '';

    final existingGold = (row['gold_coins_per_task'] as num?)?.toInt();
    final existingHelp = (row['math_help_gold_cost'] as num?)?.toInt();
    final goldController = TextEditingController(
      text: existingGold == null ? '' : '$existingGold',
    );
    final helpCostController = TextEditingController(
      text: existingHelp == null ? '' : '$existingHelp',
    );
    var selected = await MathTasksService.fetchFolderKidIds(folderId);
    selected = List<String>.from(selected);
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final effectiveGold =
              MathTasksService.effectiveGoldPerTask(folderId, folderById);
          final effectiveHelp =
              MathTasksService.effectiveMathHelpGoldCost(folderId, folderById);
          return AlertDialog(
            title: Text('Indstillinger: $title'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Uden matematikhjælp får barnet det fulde beløb pr. rigtig opgave '
                      '(ved Afslut). Har det brugt hjælp på opgaven, trækkes «omkostning».',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: goldController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Guld uden hjælp (pr. opgave, valgfrit)',
                        hintText: 'Standard / nuværende effekt: $effectiveGold',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: helpCostController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Fradrag ved matematikhjælp (valgfrit)',
                        hintText: 'Standard / nuværende effekt: $effectiveHelp',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Foreslået: 2 guld uden hjælp, 1 i fradrag med hjælp (netto 1). '
                      'Tom felt på en mappe = arv fra overmappe (rod: 2 og 1).',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text('Børn der må se denne mappe (og undermapper):',
                        style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._kids.map((k) {
                      final on = selected.contains(k.id);
                      return CheckboxListTile(
                        value: on,
                        title: Text(k.name),
                        onChanged: (v) {
                          setModal(() {
                            if (v == true) {
                              selected = [...selected, k.id];
                            } else {
                              selected = selected.where((id) => id != k.id).toList();
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuller')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Gem'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true) return;
    final gRaw = goldController.text.trim();
    final gVal = gRaw.isEmpty ? null : int.tryParse(gRaw);
    if (gRaw.isNotEmpty && gVal == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ugyldigt tal for guld uden hjælp')),
        );
      }
      return;
    }
    final hRaw = helpCostController.text.trim();
    final hVal = hRaw.isEmpty ? null : int.tryParse(hRaw);
    if (hRaw.isNotEmpty && hVal == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ugyldigt tal for hjælp-fradrag')),
        );
      }
      return;
    }
    try {
      await MathTasksService.updateFolderGold(
        folderId: folderId,
        goldCoinsPerTask: gVal,
        mathHelpGoldCost: hVal,
      );
      await MathTasksService.setFolderKids(folderId: folderId, kidIds: selected);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gemt')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fejl: $e')));
      }
    }
  }

  Future<void> _renameFolder(String folderId, String currentTitle) async {
    final c = TextEditingController(text: currentTitle);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Omdøb mappe'),
        content: TextField(
          controller: c,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuller')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Gem'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await MathTasksService.renameFolder(folderId: folderId, title: name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fejl: $e')));
      }
    }
  }

  Future<void> _deleteFolder(String folderId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet mappe?'),
        content: Text('Sletter "$title" og alt indhold. Det kan ikke fortrydes.'),
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
    if (ok != true) return;
    try {
      await MathTasksService.deleteFolder(folderId);
      if (mounted && widget.folderId == folderId) {
        context.pop();
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fejl: $e')));
      }
    }
  }

  Future<void> _deleteTask(String taskId, String prompt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet opgave?'),
        content: Text(prompt),
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
    if (ok != true) return;
    try {
      await MathTasksService.deleteTask(taskId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fejl: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_folderTitle()),
          actions: const [
            AdminMenuToolbarButton(lightOnDark: false),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Matematik'),
          actions: const [
            AdminMenuToolbarButton(lightOnDark: false),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Prøv igen'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_profileId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Matematik'),
          actions: const [
            AdminMenuToolbarButton(lightOnDark: false),
          ],
        ),
        body: const Center(child: Text('Ikke logget ind')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_folderTitle()),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: const [AdminMenuToolbarButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.folderId != null) ...[
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _addTask,
                    icon: const Icon(Icons.add),
                    label: const Text('Tilføj opgave'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _openFolderSettings(widget.folderId!),
                    icon: const Icon(Icons.settings),
                    label: const Text('Indstillinger'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.tonalIcon(
              onPressed: _addFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Ny undermappe'),
            ),
            const SizedBox(height: 24),
            if (_folders.isNotEmpty) ...[
              Text('Mapper', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._folders.map((f) {
                final id = f['id'] as String;
                final t = f['title'] as String? ?? '';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(t),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings),
                          tooltip: 'Indstillinger',
                          onPressed: () => _openFolderSettings(id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.drive_file_rename_outline),
                          tooltip: 'Omdøb',
                          onPressed: () => _renameFolder(id, t),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Slet',
                          onPressed: () => _deleteFolder(id, t),
                        ),
                      ],
                    ),
                    onTap: () => context.push('/admin/math/folder/$id'),
                  ),
                );
              }),
            ],
            if (_tasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Opgaver', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._tasks.map((t) {
                final id = t['id'] as String;
                final prompt = t['prompt'] as String? ?? '';
                final ans = t['answer'] as String? ?? '';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.calculate),
                    title: Text(prompt),
                    subtitle: Text('Svar: $ans'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteTask(id, prompt),
                    ),
                  ),
                );
              }),
            ],
            if (_folders.isEmpty && _tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(
                  child: Text('Ingen mapper eller opgaver her endnu.'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
