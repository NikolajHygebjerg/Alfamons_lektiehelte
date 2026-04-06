import 'package:supabase_flutter/supabase_flutter.dart';

import 'alfamon_evolution.dart';

/// Replicates the /api/complete logic from Next.js - runs entirely client-side with Supabase.
class TaskCompletionService {
  static final _client = Supabase.instance.client;

  /// Lægger guldmønter i kisten ([kids.gold_coins]) og logger i [points_ledger].
  /// [balance_after] er altid den nye kistesaldo.
  static Future<int> _addGoldToTreasury(
    String kidId,
    int amount, {
    String? taskCompletionId,
    required String ledgerSource,
  }) async {
    if (amount <= 0) {
      final r = await _client
          .from('kids')
          .select('gold_coins')
          .eq('id', kidId)
          .maybeSingle();
      return (r?['gold_coins'] as num?)?.toInt() ?? 0;
    }
    final row = await _client
        .from('kids')
        .select('gold_coins')
        .eq('id', kidId)
        .maybeSingle();
    final cur = (row?['gold_coins'] as num?)?.toInt() ?? 0;
    final next = cur + amount;
    await _client.from('kids').update({'gold_coins': next}).eq('id', kidId);
    await _client.from('points_ledger').insert({
      'kid_id': kidId,
      'source': ledgerSource,
      'task_completion_id': taskCompletionId,
      'delta_points': amount,
      'balance_after': next,
    });
    return next;
  }

  /// Guldmønter for nye gennemførte bogstaver i Alfamon Trace (ét pr. bogstav).
  /// Bruger [ledgerSource] `gold_earn` (samme som øvrige barn-gevinst uden opgave-række).
  static Future<int> addAlphabetTraceGold(String kidId, int letterCount) async {
    return _addGoldToTreasury(
      kidId,
      letterCount,
      ledgerSource: 'gold_earn',
    );
  }

  static Future<int?> _maybeAwardDailyBonusGold(String kidId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todayInstances = await _client
        .from('task_instances')
        .select('id,status')
        .eq('kid_id', kidId)
        .eq('date', today);

    final list = todayInstances as List;
    if (list.isEmpty) return null;
    final allCompleted = list.every((ti) =>
        ti['status'] == 'completed' || ti['status'] == 'approved');
    final hasPending = list.any((ti) => ti['status'] == 'pending');
    if (!allCompleted || hasPending) return null;

    final existingBonus = await _client
        .from('points_ledger')
        .select('id')
        .eq('kid_id', kidId)
        .eq('source', 'daily_bonus')
        .gte('created_at', '${today}T00:00:00')
        .lt('created_at', '${today}T23:59:59')
        .maybeSingle();

    if (existingBonus != null) return null;

    const bonusPoints = 5;
    await _addGoldToTreasury(kidId, bonusPoints, ledgerSource: 'daily_bonus');
    return bonusPoints;
  }

  /// Flytter guldmønter fra kisten til én Alfamons udvikling.
  static Future<void> transferGoldToAlfamon({
    required String kidId,
    required String avatarId,
    required int amount,
  }) async {
    if (amount < 1) {
      throw Exception('Vælg mindst 1 guldmønt');
    }
    final unlock = await _client
        .from('kid_unlocked_alphamons')
        .select('id')
        .eq('kid_id', kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();
    if (unlock == null) {
      throw Exception('Denne Alfamon er ikke låst op');
    }

    final kidRow = await _client
        .from('kids')
        .select('gold_coins')
        .eq('id', kidId)
        .single();
    final treasury = (kidRow['gold_coins'] as num?)?.toInt() ?? 0;
    if (treasury < amount) {
      throw Exception('Du har ikke nok guldmønter i kisten');
    }

    final newTreasury = treasury - amount;
    await _client.from('kids').update({'gold_coins': newTreasury}).eq('id', kidId);

    final libRes = await _client
        .from('kid_avatar_library')
        .select('points_current')
        .eq('kid_id', kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();
    final curLib = (libRes?['points_current'] as num?)?.toInt() ?? 0;
    final newLib = curLib + amount;

    await _syncKidAvatarLibraryEvolution(
      kidId: kidId,
      avatarId: avatarId,
      workingBalance: newLib,
    );

    final activeRes = await _client
        .from('kid_active_avatar')
        .select('avatar_id')
        .eq('kid_id', kidId)
        .maybeSingle();
    if (activeRes?['avatar_id'] == avatarId) {
      await _client
          .from('kid_active_avatar')
          .update({'points_current': newLib})
          .eq('kid_id', kidId);
    }
  }

  /// Flytter guldmønter tilbage fra Alfamon til kisten (fx hvis der er givet for mange).
  static Future<void> transferGoldFromAlfamon({
    required String kidId,
    required String avatarId,
    required int amount,
  }) async {
    if (amount < 1) {
      throw Exception('Vælg mindst 1 guldmønt');
    }
    final unlock = await _client
        .from('kid_unlocked_alphamons')
        .select('id')
        .eq('kid_id', kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();
    if (unlock == null) {
      throw Exception('Denne Alfamon er ikke låst op');
    }

    final libRes = await _client
        .from('kid_avatar_library')
        .select('points_current')
        .eq('kid_id', kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();
    final curLib = (libRes?['points_current'] as num?)?.toInt() ?? 0;
    if (curLib < amount) {
      throw Exception('Der er ikke flere guldmønter på denne Alfamon');
    }
    final newLib = curLib - amount;

    final kidRow = await _client
        .from('kids')
        .select('gold_coins')
        .eq('id', kidId)
        .single();
    final treasury = (kidRow['gold_coins'] as num?)?.toInt() ?? 0;
    final newTreasury = treasury + amount;
    await _client.from('kids').update({'gold_coins': newTreasury}).eq('id', kidId);

    await _syncKidAvatarLibraryEvolution(
      kidId: kidId,
      avatarId: avatarId,
      workingBalance: newLib,
    );

    final activeRes = await _client
        .from('kid_active_avatar')
        .select('avatar_id')
        .eq('kid_id', kidId)
        .maybeSingle();
    if (activeRes?['avatar_id'] == avatarId) {
      await _client
          .from('kid_active_avatar')
          .update({'points_current': newLib})
          .eq('kid_id', kidId);
    }
  }

  /// Opdaterer [kid_avatar_library] med stadie ud fra faste tærskler (0,10,40,80,130).
  static Future<void> _syncKidAvatarLibraryEvolution({
    required String kidId,
    required String avatarId,
    required int workingBalance,
  }) async {
    final libRes = await _client
        .from('kid_avatar_library')
        .select('id')
        .eq('kid_id', kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();

    final stagesRes = await _client
        .from('avatar_stages')
        .select('stage_index')
        .eq('avatar_id', avatarId)
        .order('stage_index');

    final stages = stagesRes as List;
    if (stages.isEmpty) return;

    final sorted = AlfamonEvolution.sortedStageIndicesFromRows(stages);
    final maxStageIndex = sorted.last;
    final currentStage =
        AlfamonEvolution.stageIndexFromPoints(workingBalance, sorted);

    if (libRes != null) {
      await _client.from('kid_avatar_library').update({
        'current_stage_index': currentStage,
        'points_current': workingBalance,
      }).eq('id', libRes['id']);
    } else {
      await _client.from('kid_avatar_library').insert({
        'kid_id': kidId,
        'avatar_id': avatarId,
        'current_stage_index': currentStage,
        'points_current': workingBalance,
      });
    }

    if (currentStage >= maxStageIndex) {
      await _client.from('kid_avatar_history').insert({
        'kid_id': kidId,
        'avatar_id': avatarId,
        'total_points': workingBalance,
      });
    }
  }

  static Future<CompleteResult> complete({
    required String taskInstanceId,
    required String kidId,
    int? count,
  }) async {
    // Fetch instance + task
    final instanceRes = await _client
        .from('task_instances')
        .select('id,status,task_id,required_completions,completions_done')
        .eq('id', taskInstanceId)
        .single();

    if (instanceRes['status'] != 'pending') {
      throw Exception('Already completed');
    }

    final taskRes = await _client
        .from('tasks')
        .select('mode,points_fixed,points_per_unit,require_approval')
        .eq('id', instanceRes['task_id'])
        .single();

    final mode = taskRes['mode'] as String;
    final pointsFixed = taskRes['points_fixed'] as int?;
    final pointsPerUnit = taskRes['points_per_unit'] as int?;
    final requireApproval = taskRes['require_approval'] as bool? ?? false;

    final points = mode == 'fixed'
        ? (pointsFixed ?? 0)
        : (pointsPerUnit ?? 0) * (count ?? 0);

    final req = (instanceRes['required_completions'] as int?) ?? 1;
    var done = (instanceRes['completions_done'] as int?) ?? 0;

    // Insert completion
    final completionRes = await _client.from('task_completions').insert({
      'task_instance_id': taskInstanceId,
      'kid_id': kidId,
      'count_entered': mode == 'counter' ? count : null,
      'points_awarded': points,
    }).select('id').single();

    if (requireApproval) {
      await _client.from('task_instances').update({
        'status': 'needs_approval',
      }).eq('id', taskInstanceId);
      return CompleteResult(points: points, dailyBonus: null);
    }

    done++;
    final newStatus = done >= req ? 'completed' : 'pending';
    await _client.from('task_instances').update({
      'status': newStatus,
      'completions_done': done,
    }).eq('id', taskInstanceId);

    int? dailyBonus;
    if (points > 0) {
      await _addGoldToTreasury(
        kidId,
        points,
        taskCompletionId: completionRes['id'] as String,
        ledgerSource: 'gold_earn',
      );
    }
    dailyBonus = await _maybeAwardDailyBonusGold(kidId);

    return CompleteResult(points: points, dailyBonus: dailyBonus);
  }

  /// Godkender en opgave (needs_approval -> approved) og tildeler point.
  /// Kræver at forældrekoden matcher.
  static Future<ApproveResult> approve({
    required String taskInstanceId,
    required String kidId,
    required String parentCode,
  }) async {
    final instanceRes = await _client
        .from('task_instances')
        .select('id,status,task_id,required_completions,completions_done')
        .eq('id', taskInstanceId)
        .single();

    if (instanceRes['status'] != 'needs_approval') {
      throw Exception('Opgaven kan ikke godkendes');
    }

    final settingsRes = await _client
        .from('settings')
        .select('value')
        .eq('key', 'approval_code')
        .maybeSingle();

    final storedCode = settingsRes?['value'] as String? ?? '';
    if (storedCode.isEmpty || parentCode.trim() != storedCode.trim()) {
      throw Exception('Forkert forældrekode');
    }

    final completionRows = await _client
        .from('task_completions')
        .select('id,points_awarded')
        .eq('task_instance_id', taskInstanceId)
        .order('created_at', ascending: false)
        .limit(1);

    final completionList = completionRows as List;
    if (completionList.isEmpty) {
      throw Exception('Ingen fuldførelse fundet');
    }
    final completionRes =
        Map<String, dynamic>.from(completionList.first as Map);

    final points = completionRes['points_awarded'] as int? ?? 0;

    final req = (instanceRes['required_completions'] as int?) ?? 1;
    var done = (instanceRes['completions_done'] as int?) ?? 0;
    done++;
    final newStatus = done >= req ? 'approved' : 'pending';

    await _client.from('task_instances').update({
      'status': newStatus,
      'completions_done': done,
    }).eq('id', taskInstanceId);

    int? dailyBonus;
    if (points > 0) {
      await _addGoldToTreasury(
        kidId,
        points,
        taskCompletionId: completionRes['id'] as String,
        ledgerSource: 'gold_earn',
      );
    }
    dailyBonus = await _maybeAwardDailyBonusGold(kidId);

    return ApproveResult(points: points, dailyBonus: dailyBonus);
  }

  /// Tildeler point for læst bog. Kræver forældrekode. 1 point pr. side.
  static Future<BookPointsResult> awardBookPoints({
    required String kidId,
    required int points,
    required String parentCode,
  }) async {
    final settingsRes = await _client
        .from('settings')
        .select('value')
        .eq('key', 'approval_code')
        .maybeSingle();

    final storedCode = settingsRes?['value'] as String? ?? '';
    if (storedCode.isEmpty || parentCode.trim() != storedCode.trim()) {
      throw Exception('Forkert forældrekode');
    }

    if (points < 1) {
      return BookPointsResult(points: 0, dailyBonus: null);
    }

    await _addGoldToTreasury(
      kidId,
      points,
      ledgerSource: 'gold_earn',
    );
    final dailyBonus = await _maybeAwardDailyBonusGold(kidId);

    return BookPointsResult(points: points, dailyBonus: dailyBonus);
  }
}

class BookPointsResult {
  final int points;
  final int? dailyBonus;

  BookPointsResult({required this.points, this.dailyBonus});
}

class ApproveResult {
  final int points;
  final int? dailyBonus;

  ApproveResult({required this.points, this.dailyBonus});
}

class CompleteResult {
  final int points;
  final int? dailyBonus;

  CompleteResult({required this.points, this.dailyBonus});
}
