import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/task.dart';
import '../utils/kid_task_instances.dart';
import '../utils/recurring_task_schedule.dart';

/// Henter dagens synlige opgave-instanser for et barn (samme regler som opgave-skærmen).
class KidDailyTaskInstancesService {
  KidDailyTaskInstancesService._();

  static Future<List<TaskInstance>> loadTodayVisibleInstances(String kidId) async {
    final now = DateTime.now();
    final today = now.toIso8601String().substring(0, 10);
    final client = Supabase.instance.client;

    final recurring = await client
        .from('recurring_tasks')
        .select(
          'task_id,due_time,allow_upfront,per_day_count,schedule_mode,weekdays,specific_dates',
        )
        .eq('kid_id', kidId);

    final existing = await client
        .from('task_instances')
        .select('task_id')
        .eq('kid_id', kidId)
        .eq('date', today);

    final existingTaskIds = <String>{};
    for (final e in existing as List) {
      existingTaskIds.add(e['task_id'] as String);
    }

    final toCreate = <Map<String, dynamic>>[];
    for (final rt in recurring as List) {
      final row = Map<String, dynamic>.from(rt as Map);
      if (!RecurringTaskSchedule.appliesToDate(row, now)) continue;
      final tid = row['task_id'] as String;
      if (existingTaskIds.contains(tid)) continue;
      final perDay = row['per_day_count'] as int? ?? 1;
      toCreate.add({
        'task_id': tid,
        'kid_id': kidId,
        'date': today,
        'due_time': row['due_time'],
        'allow_upfront': row['allow_upfront'] ?? false,
        'status': 'pending',
        'required_completions': perDay < 1 ? 1 : perDay,
        'completions_done': 0,
      });
    }
    if (toCreate.isNotEmpty) {
      await client.from('task_instances').insert(toCreate);
    }

    final res = await client
        .from('task_instances')
        .select(
          'id,task_id,kid_id,date,due_time,status,required_completions,completions_done,tasks(id,title,mode,points_fixed,points_per_unit,emoji)',
        )
        .eq('date', today)
        .eq('kid_id', kidId)
        .order('due_time', ascending: true, nullsFirst: false);

    final activeToday =
        activeRecurringTaskIdsForDate(recurring as List, now);
    final rawInstances = (res as List)
        .map((e) => TaskInstance.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return filterAndDedupeInstancesForActiveRecurring(
      rawInstances,
      activeToday,
    );
  }
}
