import 'package:supabase_flutter/supabase_flutter.dart';

typedef MathFolderRow = Map<String, dynamic>;
typedef MathTaskRow = Map<String, dynamic>;

/// Standard rode-mappenavne (oprettes automatisk i admin). Rækkefølge = visning hos barnet.
const List<String> kDefaultMathRootFolderTitles = [
  'Plus',
  'Minus',
  'Dividere',
  'Gange',
];

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

  static int? _helpCostOnFolder(MathFolderRow row) =>
      (row['math_help_gold_cost'] as num?)?.toInt();

  /// Effektiv sats uden hjælp: første ikke-null fra mappen og forældre; ellers [fallbackRoot] (standard 2).
  static int effectiveGoldPerTask(
    String folderId,
    Map<String, MathFolderRow> folderById, {
    int fallbackRoot = 2,
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

  /// Effektivt fradrag ved matematikhjælp (arv som [effectiveGoldPerTask]).
  static int effectiveMathHelpGoldCost(
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
      final c = _helpCostOnFolder(row);
      if (c != null) return c.clamp(0, 1 << 30);
      final p = row['parent_id'] as String?;
      if (p == null || p.isEmpty) return fallbackRoot;
      id = p;
    }
    return fallbackRoot;
  }

  /// Guldmønter for én korrekt opgave (klem til 0).
  static int coinsEarnedForMathTask({
    required int baseGoldWithoutHelp,
    required int helpGoldCost,
    required bool usedMathHelp,
  }) {
    final base = baseGoldWithoutHelp < 0 ? 0 : baseGoldWithoutHelp;
    final cost = helpGoldCost < 0 ? 0 : helpGoldCost;
    if (!usedMathHelp) return base;
    final v = base - cost;
    return v < 0 ? 0 : v;
  }

  static Future<({Map<String, MathFolderRow> folderById, Set<String> assigned})>
      loadKidVisibilityContext(String kidId) async {
    final profileId = await _profileId();
    if (profileId == null) {
      return (folderById: <String, MathFolderRow>{}, assigned: <String>{});
    }
    final folders = await _client
        .from('math_folders')
        .select(
          'id,parent_id,title,gold_coins_per_task,math_help_gold_cost,sort_order',
        )
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
        .select(
          'id,parent_id,title,gold_coins_per_task,math_help_gold_cost,sort_order',
        )
        .eq('profile_id', profileId)
        .order('sort_order')
        .order('title');
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Ikon til barnets underste strimmel når mappen er en standardrod med præcis titel.
  static String? kidIconAssetForMathFolderTitle(String title) {
    switch (title.trim()) {
      case 'Plus':
        return 'assets/Plus.png';
      case 'Minus':
        return 'assets/Minus.png';
      case 'Dividere':
        return 'assets/Dividere.png';
      case 'Gange':
        return 'assets/Gange.png';
      default:
        return null;
    }
  }

  /// Plus → Minus → Dividere → Gange først, derefter øvrige rodmappede uændret.
  static List<MathFolderRow> orderedVisibleRootFolders(
    List<MathFolderRow> folders,
  ) {
    if (folders.isEmpty) return folders;
    final inList = List<MathFolderRow>.from(folders);
    final byTitle = <String, MathFolderRow>{
      for (final f in inList)
        ((f['title'] as String?) ?? '').trim(): f,
    };
    final out = <MathFolderRow>[];
    for (final t in kDefaultMathRootFolderTitles) {
      final f = byTitle[t];
      if (f != null) out.add(f);
    }
    for (final f in inList) {
      final t = ((f['title'] as String?) ?? '').trim();
      if (!kDefaultMathRootFolderTitles.contains(t)) {
        out.add(f);
      }
    }
    return out;
  }

  /// Opretter manglende standard rode-mapper (sletter/ændrer ikke eksisterende).
  static Future<void> ensureDefaultMathRootFolders(String profileId) async {
    final existing = await fetchChildFolders(
      profileId: profileId,
      parentId: null,
    );
    final have = existing
        .map((f) => ((f['title'] as String?) ?? '').trim())
        .toSet();
    for (var i = 0; i < kDefaultMathRootFolderTitles.length; i++) {
      final title = kDefaultMathRootFolderTitles[i];
      if (have.contains(title)) continue;
      await _client.from('math_folders').insert({
        'profile_id': profileId,
        'parent_id': null,
        'title': title,
        'sort_order': i,
      });
    }
  }

  static Future<List<MathFolderRow>> fetchChildFolders({
    required String profileId,
    required String? parentId,
  }) async {
    final res = await _client
        .from('math_folders')
        .select(
          'id,parent_id,title,gold_coins_per_task,math_help_gold_cost,sort_order',
        )
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
    required int? mathHelpGoldCost,
  }) async {
    await _client.from('math_folders').update({
      'gold_coins_per_task': goldCoinsPerTask,
      'math_help_gold_cost': mathHelpGoldCost,
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

  /// Sletter alle opgaver i mappen (ikke undermapper eller selve mappen).
  static Future<void> deleteAllTasksInFolder(String folderId) async {
    await _client.from('math_tasks').delete().eq('folder_id', folderId);
  }

  /// [legacyTasksTimesRate]: ved ældre rækker med kun [pending_gold_tasks] > 0 og [pending_gold_coins] == 0.
  static Future<({int nextIndex, int pendingGoldCoins})> fetchProgress({
    required String kidId,
    required String folderId,
    required int legacyTasksTimesRate,
  }) async {
    final row = await _client
        .from('math_progress')
        .select('next_task_index,pending_gold_tasks,pending_gold_coins')
        .eq('kid_id', kidId)
        .eq('folder_id', folderId)
        .maybeSingle();
    if (row == null) return (nextIndex: 0, pendingGoldCoins: 0);
    final nextIndex = (row['next_task_index'] as num?)?.toInt() ?? 0;
    final storedCoins = (row['pending_gold_coins'] as num?)?.toInt() ?? 0;
    final legacyTasks = (row['pending_gold_tasks'] as num?)?.toInt() ?? 0;
    final rate = legacyTasksTimesRate < 1 ? 1 : legacyTasksTimesRate;
    var pendingGold = storedCoins;
    if (pendingGold == 0 && legacyTasks > 0) {
      pendingGold = legacyTasks * rate;
    }
    return (nextIndex: nextIndex, pendingGoldCoins: pendingGold);
  }

  static Future<void> saveProgress({
    required String kidId,
    required String folderId,
    required int nextTaskIndex,
    required int pendingGoldCoins,
  }) async {
    await _client.from('math_progress').upsert({
      'kid_id': kidId,
      'folder_id': folderId,
      'next_task_index': nextTaskIndex,
      'pending_gold_tasks': 0,
      'pending_gold_coins': pendingGoldCoins,
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
      'pending_gold_coins': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Udbetal [pendingGoldCoins] og nulstil pending i DB.
  static Future<int> settlePendingGold({
    required String kidId,
    required String folderId,
    required int pendingGoldCoins,
  }) async {
    if (pendingGoldCoins <= 0) {
      final prog = await fetchProgress(
        kidId: kidId,
        folderId: folderId,
        legacyTasksTimesRate: 1,
      );
      await saveProgress(
        kidId: kidId,
        folderId: folderId,
        nextTaskIndex: prog.nextIndex,
        pendingGoldCoins: 0,
      );
      return 0;
    }
    final amount = pendingGoldCoins;
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
    final prog = await fetchProgress(
      kidId: kidId,
      folderId: folderId,
      legacyTasksTimesRate: 1,
    );
    await saveProgress(
      kidId: kidId,
      folderId: folderId,
      nextTaskIndex: prog.nextIndex,
      pendingGoldCoins: 0,
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
