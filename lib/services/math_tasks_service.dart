import 'package:supabase_flutter/supabase_flutter.dart';

typedef MathFolderRow = Map<String, dynamic>;
typedef MathTaskRow = Map<String, dynamic>;

/// Supabase: [math_folders], [math_tasks], [math_folder_kids], [math_progress].
class MathTasksService {
  MathTasksService._();
  static final _client = Supabase.instance.client;

  /// Besked til UI ved fejl mod matematik-tabeller (uden at skjule den rigtige årsag).
  static String describeLoadError(Object error) {
    if (error is PostgrestException) {
      final m = error.message;
      final code = error.code ?? '';
      final lower = m.toLowerCase();
      // KUN tydelige "tabel findes ikke i PostgREST schema cache" – ikke permission/RLS/andre fejl.
      final missingInApiCache = code == 'PGRST205' ||
          lower.contains('could not find the table') ||
          (lower.contains('schema cache') && lower.contains('could not find'));
      if (missingInApiCache) {
        return 'PostgREST kan ikke se matematik-tabellerne endnu.\n\n'
            'Tjek: Table Editor har math_folders / math_tasks. Er SQL kørt i '
            'samme projekt som appens Supabase-URL?\n\n'
            'Prøv: Dashboard → Project Settings → API → reload af schema '
            '(eller kort ventetid efter ny tabel).\n\n'
            'Detalje: $m (kode: $code)';
      }
      return m.isNotEmpty ? '$m\n(kode: $code)' : error.toString();
    }
    final s = error.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'Ingen forbindelse til netværket.';
    }
    return s;
  }

  static Future<String?> _profileId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final profile = await _client
        .from('profiles')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    return profile?['id'] as String?;
  }

  /// Adgang hvis barnet er tildelt mappen, en forfader (hele undertræ) eller en efterkommer
  /// (så overmapper vises når kun en undermappe er tildelt).
  static bool kidHasAccessToFolder({
    required String folderId,
    required Set<String> assignedFolderIds,
    required Map<String, MathFolderRow> folderById,
  }) {
    if (assignedFolderIds.isEmpty) return false;
    // Tildeling på denne mappe eller en forfader → adgang til undermapper.
    var id = folderId;
    final seenUp = <String>{};
    while (id.isNotEmpty && folderById.containsKey(id)) {
      if (seenUp.contains(id)) break;
      seenUp.add(id);
      if (assignedFolderIds.contains(id)) return true;
      final p = folderById[id]?['parent_id'] as String?;
      if (p == null || p.isEmpty) break;
      id = p;
    }
    // Tildeling kun på efterfølger → vis forfædre så barnet kan navigere ned.
    for (final a in assignedFolderIds) {
      var x = a;
      final seen2 = <String>{};
      while (folderById.containsKey(x)) {
        if (seen2.contains(x)) break;
        seen2.add(x);
        if (x == folderId) return true;
        final p = folderById[x]?['parent_id'] as String?;
        if (p == null || p.isEmpty) break;
        x = p;
      }
    }
    return false;
  }

  static int? _coinsOnFolder(MathFolderRow row) =>
      (row['gold_coins_per_task'] as num?)?.toInt();

  /// Effektiv sats: første ikke-null fra mappen og forældre; ellers [fallbackRoot].
  static int effectiveGoldPerTask(
    String folderId,
    Map<String, MathFolderRow> folderById, {
    int fallbackRoot = 1,
  }) {
    var id = folderId;
    final seen = <String>{};
    while (id.isNotEmpty && folderById.containsKey(id)) {
      if (seen.contains(id)) break;
      seen.add(id);
      final row = folderById[id]!;
      final c = _coinsOnFolder(row);
      if (c != null) return c;
      final p = row['parent_id'] as String?;
      if (p == null || p.isEmpty) return fallbackRoot;
      id = p;
    }
    return fallbackRoot;
  }

  static Future<({Map<String, MathFolderRow> folderById, Set<String> assigned})>
      loadKidVisibilityContext(String kidId) async {
    final profileId = await _profileId();
    if (profileId == null) {
      return (folderById: <String, MathFolderRow>{}, assigned: <String>{});
    }
    final folders = await _client
        .from('math_folders')
        .select('id,parent_id,title,gold_coins_per_task,sort_order')
        .eq('profile_id', profileId);
    final folderById = <String, MathFolderRow>{};
    for (final e in folders as List) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = m['id'] as String?;
      if (id != null) folderById[id] = m;
    }
    final assigns = await _client
        .from('math_folder_kids')
        .select('folder_id')
        .eq('kid_id', kidId);
    final assigned = <String>{};
    for (final e in assigns as List) {
      final id = (e as Map)['folder_id'] as String?;
      if (id != null) assigned.add(id);
    }
    return (folderById: folderById, assigned: assigned);
  }

  /// Rodmapper barnet må se (har tildeling på mappen eller forfader).
  static List<MathFolderRow> visibleRootFolders(
    Map<String, MathFolderRow> folderById,
    Set<String> assigned,
  ) {
    final roots = folderById.values.where((r) => r['parent_id'] == null).toList();
    roots.sort((a, b) {
      final oa = (a['sort_order'] as num?)?.toInt() ?? 0;
      final ob = (b['sort_order'] as num?)?.toInt() ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return (a['title'] as String).compareTo(b['title'] as String);
    });
    return roots
        .where(
          (r) => kidHasAccessToFolder(
            folderId: r['id'] as String,
            assignedFolderIds: assigned,
            folderById: folderById,
          ),
        )
        .toList();
  }

  static Future<List<MathFolderRow>> fetchAllFolders(String profileId) async {
    final res = await _client
        .from('math_folders')
        .select('id,parent_id,title,gold_coins_per_task,sort_order')
        .eq('profile_id', profileId)
        .order('sort_order')
        .order('title');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<MathFolderRow>> fetchChildFolders({
    required String profileId,
    required String? parentId,
  }) async {
    final res = await _client
        .from('math_folders')
        .select('id,parent_id,title,gold_coins_per_task,sort_order')
        .eq('profile_id', profileId)
        .order('sort_order')
        .order('title');
    final list =
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return list.where((r) {
      final pId = r['parent_id'] as String?;
      if (parentId == null) return pId == null;
      return pId == parentId;
    }).toList();
  }

  static Future<List<String>> fetchFolderKidIds(String folderId) async {
    final res = await _client
        .from('math_folder_kids')
        .select('kid_id')
        .eq('folder_id', folderId);
    return (res as List)
        .map((e) => (e as Map)['kid_id'] as String)
        .toList();
  }

  static Future<void> setFolderKids({
    required String folderId,
    required List<String> kidIds,
  }) async {
    await _client.from('math_folder_kids').delete().eq('folder_id', folderId);
    if (kidIds.isEmpty) return;
    await _client.from('math_folder_kids').insert(
          kidIds.map((k) => {'folder_id': folderId, 'kid_id': k}).toList(),
        );
  }

  static Future<List<MathTaskRow>> fetchTasks(String folderId) async {
    final res = await _client
        .from('math_tasks')
        .select('id,folder_id,prompt,answer,sort_order')
        .eq('folder_id', folderId)
        .order('sort_order')
        .order('created_at');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<String> createFolder({
    required String profileId,
    required String title,
    String? parentId,
    int? goldCoinsPerTask,
  }) async {
    int sortOrder = 0;
    final siblings = await fetchChildFolders(profileId: profileId, parentId: parentId);
    if (siblings.isNotEmpty) {
      sortOrder = siblings
              .map((s) => (s['sort_order'] as num?)?.toInt() ?? 0)
              .reduce((a, b) => a > b ? a : b) +
          1;
    }
    final row = await _client
        .from('math_folders')
        .insert({
          'profile_id': profileId,
          'parent_id': parentId,
          'title': title,
          'gold_coins_per_task': goldCoinsPerTask,
          'sort_order': sortOrder,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateFolderGold({
    required String folderId,
    required int? goldCoinsPerTask,
  }) async {
    await _client.from('math_folders').update({
      'gold_coins_per_task': goldCoinsPerTask,
    }).eq('id', folderId);
  }

  static Future<void> renameFolder({
    required String folderId,
    required String title,
  }) async {
    await _client.from('math_folders').update({'title': title}).eq('id', folderId);
  }

  static Future<void> deleteFolder(String folderId) async {
    await _client.from('math_folders').delete().eq('id', folderId);
  }

  static Future<void> addTask({
    required String folderId,
    required String prompt,
    required String answer,
  }) async {
    await addTasks(
      folderId: folderId,
      items: [(prompt: prompt, answer: answer)],
    );
  }

  /// Indsæt flere opgaver i rækkefølge (stigende [sort_order]) efter eksisterende.
  static Future<void> addTasks({
    required String folderId,
    required List<({String prompt, String answer})> items,
  }) async {
    if (items.isEmpty) return;
    final existing = await fetchTasks(folderId);
    var nextOrder = existing.isEmpty
        ? 0
        : existing
                .map((t) => (t['sort_order'] as num?)?.toInt() ?? 0)
                .reduce((a, b) => a > b ? a : b) +
            1;
    final rows = <Map<String, dynamic>>[];
    for (final it in items) {
      rows.add({
        'folder_id': folderId,
        'prompt': it.prompt,
        'answer': it.answer,
        'sort_order': nextOrder++,
      });
    }
    await _client.from('math_tasks').insert(rows);
  }

  static Future<void> deleteTask(String taskId) async {
    await _client.from('math_tasks').delete().eq('id', taskId);
  }

  static Future<({int nextIndex, int pendingGold})> fetchProgress({
    required String kidId,
    required String folderId,
  }) async {
    final row = await _client
        .from('math_progress')
        .select('next_task_index,pending_gold_tasks')
        .eq('kid_id', kidId)
        .eq('folder_id', folderId)
        .maybeSingle();
    if (row == null) return (nextIndex: 0, pendingGold: 0);
    return (
      nextIndex: (row['next_task_index'] as num?)?.toInt() ?? 0,
      pendingGold: (row['pending_gold_tasks'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> saveProgress({
    required String kidId,
    required String folderId,
    required int nextTaskIndex,
    required int pendingGoldTasks,
  }) async {
    await _client.from('math_progress').upsert({
      'kid_id': kidId,
      'folder_id': folderId,
      'next_task_index': nextTaskIndex,
      'pending_gold_tasks': pendingGoldTasks,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> resetProgress({
    required String kidId,
    required String folderId,
  }) async {
    await _client.from('math_progress').upsert({
      'kid_id': kidId,
      'folder_id': folderId,
      'next_task_index': 0,
      'pending_gold_tasks': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Udbetal [pendingCount] opgaver á [coinsPerTask]; nulstil pending i DB.
  static Future<int> settlePendingGold({
    required String kidId,
    required String folderId,
    required int pendingCount,
    required int coinsPerTask,
  }) async {
    if (pendingCount <= 0 || coinsPerTask <= 0) {
      final prog = await fetchProgress(kidId: kidId, folderId: folderId);
      await saveProgress(
        kidId: kidId,
        folderId: folderId,
        nextTaskIndex: prog.nextIndex,
        pendingGoldTasks: 0,
      );
      return 0;
    }
    final amount = pendingCount * coinsPerTask;
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
      'source': 'math',
      'delta_points': amount,
      'balance_after': next,
    });
    final prog = await fetchProgress(kidId: kidId, folderId: folderId);
    await saveProgress(
      kidId: kidId,
      folderId: folderId,
      nextTaskIndex: prog.nextIndex,
      pendingGoldTasks: 0,
    );
    return amount;
  }

  /// Synlige undermapper for barn (samme profil-træ).
  static List<MathFolderRow> visibleChildFolders({
    required String parentId,
    required Map<String, MathFolderRow> folderById,
    required Set<String> assigned,
  }) {
    final children =
        folderById.values.where((r) => (r['parent_id'] as String?) == parentId).toList();
    children.sort((a, b) {
      final oa = (a['sort_order'] as num?)?.toInt() ?? 0;
      final ob = (b['sort_order'] as num?)?.toInt() ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return (a['title'] as String).compareTo(b['title'] as String);
    });
    return children
        .where(
          (r) => kidHasAccessToFolder(
            folderId: r['id'] as String,
            assignedFolderIds: assigned,
            folderById: folderById,
          ),
        )
        .toList();
  }

  /// Bruges i admin til at hente profil-id.
  static Future<String?> currentProfileId() => _profileId();
}
