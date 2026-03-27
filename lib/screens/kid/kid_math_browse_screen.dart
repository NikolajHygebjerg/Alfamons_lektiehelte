import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/math_tasks_service.dart';
import 'kid_layout_constants.dart';
import 'widgets/kid_gold_treasury_corner.dart';
import 'widgets/kid_math_black_popup_card.dart';
import 'widgets/kid_session_nav_button.dart';

/// Mapper til matematik – rod eller undermappe.
class KidMathBrowseScreen extends StatefulWidget {
  const KidMathBrowseScreen({
    super.key,
    required this.kidId,
    this.folderId,
  });

  final String kidId;
  final String? folderId;

  @override
  State<KidMathBrowseScreen> createState() => _KidMathBrowseScreenState();
}

class _KidMathBrowseScreenState extends State<KidMathBrowseScreen> {
  List<MathFolderRow> _folders = [];
  Map<String, int> _taskCounts = {};
  String? _title;
  bool _loading = true;
  String? _loadError;
  int _playTaskCount = 0;
  /// [math_progress.next_task_index] for den viste mappe (0 hvis ingen mappe/opgaver).
  int _playNextIndex = 0;
  int _kidGoldCoins = 0;

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
      final ctx = await MathTasksService.loadKidVisibilityContext(widget.kidId);
      final folderById = ctx.folderById;
      final assigned = ctx.assigned;
      List<MathFolderRow> folders;
      String title;
      if (widget.folderId == null) {
        folders = MathTasksService.visibleRootFolders(folderById, assigned);
        title = 'Matematik';
      } else {
        folders = MathTasksService.visibleChildFolders(
          parentId: widget.folderId!,
          folderById: folderById,
          assigned: assigned,
        );
        final row = folderById[widget.folderId!];
        title = row?['title'] as String? ?? 'Matematik';
      }
      final ids = folders.map((f) => f['id'] as String).toList();
      final counts = await _fetchTaskCounts(ids);
      var playN = 0;
      var nextIdx = 0;
      if (widget.folderId != null) {
        playN = await _taskCountInFolder(widget.folderId!);
        if (playN > 0) {
          final prog = await MathTasksService.fetchProgress(
            kidId: widget.kidId,
            folderId: widget.folderId!,
          );
          nextIdx = prog.nextIndex;
        }
      }
      final goldRow = await Supabase.instance.client
          .from('kids')
          .select('gold_coins')
          .eq('id', widget.kidId)
          .maybeSingle();
      final gold = (goldRow?['gold_coins'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _taskCounts = counts;
        _title = title;
        _playTaskCount = playN;
        _playNextIndex = nextIdx;
        _kidGoldCoins = gold;
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('KidMathBrowseScreen._load: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loadError = MathTasksService.describeLoadError(e);
        _folders = [];
        _taskCounts = {};
        _playTaskCount = 0;
        _playNextIndex = 0;
        _kidGoldCoins = 0;
        _loading = false;
      });
    }
  }

  bool get _folderFullySolved =>
      widget.folderId != null &&
      _playTaskCount > 0 &&
      _playNextIndex >= _playTaskCount;

  Future<void> _restartFolder() async {
    if (widget.folderId == null) return;
    await MathTasksService.resetProgress(
      kidId: widget.kidId,
      folderId: widget.folderId!,
    );
    if (!mounted) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Du kan starte opgaverne forfra.')),
      );
    }
  }

  Future<Map<String, int>> _fetchTaskCounts(List<String> folderIds) async {
    if (folderIds.isEmpty) return {};
    try {
      final client = Supabase.instance.client;
      final res =
          await client.from('math_tasks').select('folder_id').inFilter('folder_id', folderIds);
      final map = <String, int>{};
      for (final id in folderIds) {
        map[id] = 0;
      }
      for (final e in res as List) {
        final fid = (e as Map)['folder_id'] as String?;
        if (fid != null) map[fid] = (map[fid] ?? 0) + 1;
      }
      return map;
    } catch (_) {
      return {for (final id in folderIds) id: 0};
    }
  }

  Future<int> _taskCountInFolder(String folderId) async {
    try {
      final res = await Supabase.instance.client
          .from('math_tasks')
          .select('id')
          .eq('folder_id', folderId);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  Widget _background() {
    return Positioned.fill(
      child: Image.asset(
        'assets/baggrund_matematik.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1B4D3E), Color(0xFF52B788)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _folderChip({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 132,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28, color: color == const Color(0xFFF9C433) ? Colors.black87 : const Color(0xFF1B4D3E)),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.2,
                      color: color == const Color(0xFFF9C433) ? Colors.black87 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: Colors.black.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _titleShadows = [
    Shadow(offset: Offset(0, 1), blurRadius: 5, color: Colors.black54),
  ];

  Widget _mathBrowseTopBar(BuildContext context) {
    final title = _loading ? 'Matematik' : (_title ?? 'Matematik');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KidSessionNavButton(
            kidId: widget.kidId,
            isHome: false,
            fallbackLocation: widget.folderId == null
                ? '/kid/today/${widget.kidId}'
                : '/kid/math/${widget.kidId}',
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                shadows: _titleShadows,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showBottomStrip = !_loading &&
        _loadError == null &&
        (_folders.isNotEmpty || (widget.folderId != null && _playTaskCount > 0));

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _background(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _mathBrowseTopBar(context),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : _loadError != null
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 48,
                                      color: Theme.of(context).colorScheme.error,
                                    ),
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
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: RefreshIndicator(
                                    onRefresh: _load,
                                    color: Colors.white,
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          final solved = _folderFullySolved;
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                child: Column(
                                  mainAxisAlignment:
                                      solved ? MainAxisAlignment.center : MainAxisAlignment.start,
                                  children: [
                                    if (solved)
                                      KidMathBlackPopupCard(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Du har løst alle opgaver i denne mappe.',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 24),
                                            FilledButton(
                                              onPressed: _restartFolder,
                                              style: FilledButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 28,
                                                  vertical: 16,
                                                ),
                                                backgroundColor: const Color(0xFFF9C433),
                                                foregroundColor: Colors.black87,
                                              ),
                                              child: const Text(
                                                'Begynd forfra',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else ...[
                                      if (widget.folderId == null &&
                                          _folders.isNotEmpty)
                                        SizedBox(
                                          height: math.max(
                                            120.0,
                                            constraints.maxHeight - 8,
                                          ),
                                          width: double.infinity,
                                          child: const Center(
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 24,
                                              ),
                                              child: Text(
                                                'Vælg opgave i bunden',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF2C2C2C),
                                                  height: 1.25,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_folders.isEmpty &&
                                          widget.folderId != null &&
                                          _playTaskCount == 0)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 32),
                                          child: Center(child: Text('Ingen opgaver her.')),
                                        ),
                                      if (_folders.isEmpty && widget.folderId == null)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 48),
                                          child: Center(
                                            child: Text(
                                              'Din voksen skal oprette matematikmapper under Admin → Matematik.',
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      if (_folders.isNotEmpty && widget.folderId != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 24, left: 8, right: 8),
                                          child: Text(
                                            _playTaskCount > 0
                                                ? 'Åbn en mappe nedenfor – eller tryk Spil for opgaver i denne mappe.'
                                                : 'Åbn en mappe nedenfor.',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  color: Colors.white,
                                                  shadows: const [
                                                    Shadow(
                                                      offset: Offset(1, 1),
                                                      blurRadius: 3,
                                                      color: Colors.black54,
                                                    ),
                                                  ],
                                                ),
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (showBottomStrip)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        kidZoneHorizontalPadding,
                        10,
                        kidZoneHorizontalPadding,
                        12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        border: Border(
                          top: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.hardEdge,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (widget.folderId != null && _playTaskCount > 0)
                              _folderChip(
                                title: 'Spil',
                                subtitle: '$_playTaskCount opgaver',
                                icon: Icons.play_circle_filled,
                                color: const Color(0xFFF9C433),
                                onTap: () => context.push('/kid/math/${widget.kidId}/play/${widget.folderId}'),
                              ),
                            ..._folders.map((f) {
                              final id = f['id'] as String;
                              final t = f['title'] as String? ?? '';
                              final tc = _taskCounts[id] ?? 0;
                              return _folderChip(
                                title: t,
                                subtitle: tc > 0 ? '$tc opgaver' : 'Mappe',
                                icon: Icons.folder_open,
                                color: Colors.white.withValues(alpha: 0.95),
                                onTap: () => context.push('/kid/math/${widget.kidId}/folder/$id'),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                              ],
                            ),
                          ),
                ],
              ),
            ),
          if (widget.folderId == null &&
              !_loading &&
              _loadError == null)
            Positioned(
              right: kidZoneHorizontalPadding,
              bottom: MediaQuery.paddingOf(context).bottom +
                  (showBottomStrip ? 128 : 16),
              child: KidGoldTreasuryCorner(goldCoins: _kidGoldCoins),
            ),
        ],
      ),
    );
  }
}
