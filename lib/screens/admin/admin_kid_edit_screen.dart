import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/kid.dart';
import '../../models/task.dart';
import '../../utils/recurring_task_schedule.dart';
import '../../utils/danish_alfamon_sort.dart';
import '../../widgets/asset_or_network_image.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';
import '../../widgets/admin/recurring_task_schedule_dialog.dart';

/// Admin: Rediger barn – avatar, PIN, opgavetildeling.
class AdminKidEditScreen extends StatefulWidget {
  final Kid kid;

  const AdminKidEditScreen({super.key, required this.kid});

  @override
  State<AdminKidEditScreen> createState() => _AdminKidEditScreenState();
}

class _AdminKidEditScreenState extends State<AdminKidEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _pinController;
  List<Task> _tasks = [];
  Set<String> _assignedTaskIds = {};
  /// Seneste række fra recurring_tasks pr. task_id (til visning og redigering).
  final Map<String, Map<String, dynamic>> _recurringByTaskId = {};
  List<Map<String, dynamic>> _avatars = [];
  String? _selectedAvatarId;
  String? _selectedAvatarImageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.kid.name);
    _pinController = TextEditingController(text: widget.kid.pinCode ?? '');
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;

    final user = client.auth.currentUser;
    if (user == null) return;

    final profile = await client
        .from('profiles')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    final parentId = profile?['id'];
    if (parentId == null) return;

    final tasksRes = await client
        .from('tasks')
        .select('id,title,description,mode,points_fixed,points_per_unit,emoji')
        .eq('parent_id', parentId)
        .order('created_at');

    final recurringRes = await client
        .from('recurring_tasks')
        .select(
          'task_id,due_time,allow_upfront,per_day_count,schedule_mode,weekdays,specific_dates',
        )
        .eq('kid_id', widget.kid.id);

    final activeAvatarRes = await client
        .from('kid_active_avatar')
        .select('avatar_id')
        .eq('kid_id', widget.kid.id)
        .maybeSingle();

    final avatarsRes = await client.from('avatars').select('id,name,letter');

    final stageRes = await client
        .from('avatar_stages')
        .select('avatar_id,stage_index,image_url');

    final stageMap = <String, String>{};
    final stagesList = (stageRes as List)
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) {
        final aidCmp = (a['avatar_id'] as String).compareTo(b['avatar_id'] as String);
        if (aidCmp != 0) return aidCmp;
        return (b['stage_index'] as int).compareTo(a['stage_index'] as int);
      });
    for (final s in stagesList) {
      final aid = s['avatar_id'] as String;
      if (!stageMap.containsKey(aid)) {
        stageMap[aid] = s['image_url'] as String? ?? '';
      }
    }

    final avatars = <Map<String, dynamic>>[];
    for (final a in avatarsRes as List) {
      final name = (a['name'] as String?) ?? 'Alfamon';
      if (isExcludedFromAdminAvatarPicker(name)) continue;
      final avatarId = a['id'] as String;
      avatars.add({
        'id': avatarId,
        'name': name,
        'letter': a['letter'],
        'image_url': stageMap[avatarId],
      });
    }
    avatars.sort(
      (x, y) => compareDanishAlfamonName(
        x['name'] as String? ?? '',
        y['name'] as String? ?? '',
      ),
    );

    if (!mounted) return;
    final recurringMap = <String, Map<String, dynamic>>{};
    for (final r in recurringRes as List) {
      final m = Map<String, dynamic>.from(r as Map);
      recurringMap[m['task_id'] as String] = m;
    }
    setState(() {
      _tasks = (tasksRes as List).map((e) => Task.fromJson(e)).toList();
      _recurringByTaskId
        ..clear()
        ..addAll(recurringMap);
      _assignedTaskIds = recurringMap.keys.toSet();
      _avatars = avatars;
      _selectedAvatarId = activeAvatarRes?['avatar_id'] as String?;
      _selectedAvatarImageUrl = _selectedAvatarId != null
          ? stageMap[_selectedAvatarId]
          : widget.kid.avatarUrl;
      _loading = false;
    });
  }

  Future<void> _saveNameAndPin() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();

    await Supabase.instance.client.from('kids').update({
      'name': name,
      'pin_code': pin.isEmpty ? null : pin,
    }).eq('id', widget.kid.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navn og PIN gemt')),
      );
    }
  }

  Future<void> _selectAvatar(Map<String, dynamic> avatar) async {
    final client = Supabase.instance.client;
    final avatarId = avatar['id'] as String;
    final imageUrl = avatar['image_url'] as String?;

    await client.from('kids').update({
      'avatar_url': imageUrl,
    }).eq('id', widget.kid.id);

    final existingUnlock = await client
        .from('kid_unlocked_alphamons')
        .select('id')
        .eq('kid_id', widget.kid.id)
        .eq('avatar_id', avatarId)
        .maybeSingle();

    var points = 0;
    if (existingUnlock == null) {
      await client.from('kid_unlocked_alphamons').insert({
        'kid_id': widget.kid.id,
        'avatar_id': avatarId,
      });

      final stagesRes = await client
          .from('avatar_stages')
          .select('stage_index')
          .eq('avatar_id', avatarId)
          .order('stage_index')
          .limit(1);
      final initialStage = (stagesRes as List).isNotEmpty
          ? (stagesRes.first['stage_index'] as int)
          : 0;

      await client.from('kid_avatar_library').insert({
        'kid_id': widget.kid.id,
        'avatar_id': avatarId,
        'current_stage_index': initialStage,
        'points_current': 0,
      });
    } else {
      final libRes = await client
          .from('kid_avatar_library')
          .select('points_current')
          .eq('kid_id', widget.kid.id)
          .eq('avatar_id', avatarId)
          .maybeSingle();
      points = libRes?['points_current'] as int? ?? 0;
    }

    await client.from('kid_active_avatar').upsert({
      'kid_id': widget.kid.id,
      'avatar_id': avatarId,
      'points_current': points,
    }, onConflict: 'kid_id');

    if (mounted) {
      setState(() {
        _selectedAvatarId = avatarId;
        _selectedAvatarImageUrl = imageUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar opdateret')),
      );
    }
  }

  Map<String, dynamic> _payloadFromSchedule(RecurringScheduleResult r) {
    return {
      'due_time': r.dueTime,
      'allow_upfront': true,
      'per_day_count': r.perDayCount,
      'schedule_mode': r.scheduleMode,
      'weekdays': r.weekdays,
      'specific_dates': r.specificDatesIso,
    };
  }

  Future<void> _assignOrEditTask(Task task, {required bool isNew}) async {
    final existing = isNew ? null : _recurringByTaskId[task.id];
    final result = await showRecurringTaskScheduleDialog(
      context: context,
      task: task,
      existingRow: existing,
    );
    if (result == null || !mounted) return;

    final client = Supabase.instance.client;
    final payload = {
      'kid_id': widget.kid.id,
      'task_id': task.id,
      ..._payloadFromSchedule(result),
    };

    try {
      if (isNew) {
        await client.from('recurring_tasks').insert(payload);
      } else {
        await client
            .from('recurring_tasks')
            .update(_payloadFromSchedule(result))
            .eq('kid_id', widget.kid.id)
            .eq('task_id', task.id);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isNew ? 'Opgave tildelt' : 'Plan opdateret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kunne ikke gemme. Har du kørt database-migrationen (schedule_mode / weekdays / specific_dates)? $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _onTaskSwitch(Task task, bool assign) async {
    final client = Supabase.instance.client;
    if (!assign) {
      await client
          .from('recurring_tasks')
          .delete()
          .eq('kid_id', widget.kid.id)
          .eq('task_id', task.id);
      // Fjern materialede instanser fra i dag og frem (ellers hænger de på barnets skærm).
      final today =
          DateTime.now().toIso8601String().substring(0, 10);
      await client
          .from('task_instances')
          .delete()
          .eq('kid_id', widget.kid.id)
          .eq('task_id', task.id)
          .gte('date', today);
      if (mounted) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opgave fjernet')),
        );
      }
      return;
    }
    await _assignOrEditTask(task, isNew: true);
  }

  Widget _buildTaskAssignmentSection() {
    if (_tasks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Opgaver',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Ingen opgaver oprettet. Opret opgaver under "Opgaver" først.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    final unassigned =
        _tasks.where((t) => !_assignedTaskIds.contains(t.id)).toList();
    final assigned =
        _tasks.where((t) => _assignedTaskIds.contains(t.id)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Opgaver',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tildelte opgaver vises i listen til højre (bred skærm) eller øverst. Herunder kan du kun tilføje opgaver, der endnu ikke er tildelt. Tryk på en tildelt opgave for at ændre planen.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _UnassignedTaskList(
                      tasks: unassigned,
                      onAssign: (t) => _assignOrEditTask(t, isNew: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 220,
                    child: _AssignedTasksColumn(
                      tasks: assigned,
                      recurringByTaskId: _recurringByTaskId,
                      onEdit: (t) => _assignOrEditTask(t, isNew: false),
                      onRemove: (t) => _onTaskSwitch(t, false),
                    ),
                  ),
                ],
              )
            else ...[
              _AssignedTasksStrip(
                tasks: assigned,
                recurringByTaskId: _recurringByTaskId,
                onEdit: (t) => _assignOrEditTask(t, isNew: false),
                onRemove: (t) => _onTaskSwitch(t, false),
              ),
              const SizedBox(height: 16),
              _UnassignedTaskList(
                tasks: unassigned,
                onAssign: (t) => _assignOrEditTask(t, isNew: true),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Rediger ${widget.kid.name}'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: [
          const AdminMenuToolbarButton(),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveNameAndPin,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Navn og PIN',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Navn',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinController,
                    decoration: const InputDecoration(
                      labelText: 'PIN (4 cifre, valgfrit)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Avatar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _avatars.length,
                      itemBuilder: (_, i) {
                        final a = _avatars[i];
                        final isSelected = _selectedAvatarId == a['id'];
                        final url = a['image_url'] as String?;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: InkWell(
                            onTap: () => _selectAvatar(a),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.amber
                                      : Colors.grey,
                                  width: isSelected ? 3 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: url != null && url.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                    top: Radius.circular(11)),
                                            child: AssetOrNetworkImage(
                                              src: url,
                                              width: double.infinity,
                                              height: double.infinity,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(Icons.person, size: 40),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      a['name'] as String? ?? '',
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildTaskAssignmentSection(),
                ],
              ),
            ),
    );
  }
}

class _AssignedTasksStrip extends StatelessWidget {
  const _AssignedTasksStrip({
    required this.tasks,
    required this.recurringByTaskId,
    required this.onEdit,
    required this.onRemove,
  });

  final List<Task> tasks;
  final Map<String, Map<String, dynamic>> recurringByTaskId;
  final void Function(Task) onEdit;
  final void Function(Task) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tildelte (${tasks.length})',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Text(
            'Ingen endnu — brug listen nedenfor.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          )
        else
          SizedBox(
            height: 122,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tasks.length,
              separatorBuilder: (context, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = tasks[i];
                final row = recurringByTaskId[t.id];
                final planText =
                    row != null ? RecurringTaskSchedule.summary(row) : '';
                return _AssignedTaskCard(
                  task: t,
                  planSummary: planText,
                  compact: true,
                  onTap: () => onEdit(t),
                  onRemove: () => onRemove(t),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AssignedTasksColumn extends StatelessWidget {
  const _AssignedTasksColumn({
    required this.tasks,
    required this.recurringByTaskId,
    required this.onEdit,
    required this.onRemove,
  });

  final List<Task> tasks;
  final Map<String, Map<String, dynamic>> recurringByTaskId;
  final void Function(Task) onEdit;
  final void Function(Task) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tildelte',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Text(
            'Ingen endnu.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          )
        else
          ...tasks.map((t) {
            final row = recurringByTaskId[t.id];
            final planText =
                row != null ? RecurringTaskSchedule.summary(row) : '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AssignedTaskCard(
                task: t,
                planSummary: planText,
                compact: false,
                onTap: () => onEdit(t),
                onRemove: () => onRemove(t),
              ),
            );
          }),
      ],
    );
  }
}

class _AssignedTaskCard extends StatelessWidget {
  const _AssignedTaskCard({
    required this.task,
    required this.planSummary,
    required this.compact,
    required this.onTap,
    required this.onRemove,
  });

  final Task task;
  final String planSummary;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final pointsLine =
        '${task.mode == "fixed" ? "Fast" : "Tæller"} • ${task.mode == "fixed" ? (task.pointsFixed ?? 0) : (task.pointsPerUnit ?? 0)} point';

    if (compact) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    task.displayEmoji,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30, height: 1.1),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onPressed: onRemove,
                        tooltip: 'Fjern tildeling',
                      ),
                    ],
                  ),
                  Text(
                    pointsLine,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (planSummary.isNotEmpty)
                    Text(
                      planSummary,
                      style: const TextStyle(fontSize: 10, color: Colors.black87),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Text(
          task.displayEmoji,
          style: const TextStyle(fontSize: 26),
        ),
        title: Text(task.title),
        subtitle: Text(
          [
            pointsLine,
            if (planSummary.isNotEmpty) 'Plan: $planSummary',
          ].join('\n'),
        ),
        isThreeLine: planSummary.isNotEmpty,
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onRemove,
          tooltip: 'Fjern tildeling',
        ),
        onTap: onTap,
      ),
    );
  }
}

class _UnassignedTaskList extends StatelessWidget {
  const _UnassignedTaskList({
    required this.tasks,
    required this.onAssign,
  });

  final List<Task> tasks;
  final void Function(Task) onAssign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tilføj opgaver',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Text(
            'Alle opgaver er tildelt.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          )
        else
          ...tasks.map((t) {
            final pointsLine =
                '${t.mode == "fixed" ? "Fast" : "Tæller"} • ${t.mode == "fixed" ? (t.pointsFixed ?? 0) : (t.pointsPerUnit ?? 0)} point';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Text(
                  t.displayEmoji,
                  style: const TextStyle(fontSize: 26),
                ),
                title: Text(t.title),
                subtitle: Text(pointsLine),
                trailing: FilledButton.tonal(
                  onPressed: () => onAssign(t),
                  child: const Text('Tildel'),
                ),
              ),
            );
          }),
      ],
    );
  }
}
