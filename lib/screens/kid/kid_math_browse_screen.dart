import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/math_tasks_service.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import '../../utils/math_tutor_prerecorded_intro.dart';
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
  final AudioPlayer _rootFolderHintPlayer = AudioPlayer();
  int _loadSeq = 0;
  /// Undgå gentagen auto-start ved refresh, når vi allerede er kommet tilbage fra Spil.
  bool _didAutoStartPlayForThisFolder = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KidMathBrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderId != widget.folderId) {
      _didAutoStartPlayForThisFolder = false;
    }
  }

  @override
  void dispose() {
    unawaited(_rootFolderHintPlayer.dispose());
    super.dispose();
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
        folders = MathTasksService.orderedVisibleRootFolders(folders);
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
          final rate = MathTasksService.effectiveGoldPerTask(
            widget.folderId!,
            folderById,
          );
          final prog = await MathTasksService.fetchProgress(
            kidId: widget.kidId,
            folderId: widget.folderId!,
            legacyTasksTimesRate: rate,
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
      final seq = ++_loadSeq;
      setState(() {
        _folders = folders;
        _taskCounts = counts;
        _title = title;
        _playTaskCount = playN;
        _playNextIndex = nextIdx;
        _kidGoldCoins = gold;
        _loading = false;
      });
      final folderFullySolvedNow =
          widget.folderId != null && playN > 0 && nextIdx >= playN;
      if (widget.folderId == null &&
          folders.isNotEmpty &&
          mounted &&
          seq == _loadSeq) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || seq != _loadSeq) return;
          try {
            await _rootFolderHintPlayer.stop();
          } catch (_) {}
          unawaited(mathTutorTryPlayAabenEnMappeNedenfor(_rootFolderHintPlayer));
        });
      }
      if (widget.folderId != null &&
          folders.isNotEmpty &&
          !folderFullySolvedNow &&
          mounted &&
          seq == _loadSeq) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || seq != _loadSeq) return;
          try {
            await _rootFolderHintPlayer.stop();
          } catch (_) {}
          unawaited(mathTutorTryPlayVaelgHvilkenOpgave(_rootFolderHintPlayer));
        });
      }
      final leafWithTasks = widget.folderId != null &&
          playN > 0 &&
          !folderFullySolvedNow &&
          folders.isEmpty;
      if (leafWithTasks &&
          !_didAutoStartPlayForThisFolder &&
          mounted &&
          seq == _loadSeq) {
        final fid = widget.folderId!;
        final k = widget.kidId;
        final capturedSeq = seq;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || capturedSeq != _loadSeq) return;
          _didAutoStartPlayForThisFolder = true;
          context.push('/kid/math/$k/play/$fid');
        });
      }
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
        'assets/baggrund_matematik2.webp',
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
    String? imageAsset,
  }) {
    final iconColor = color == const Color(0xFFF9C433)
        ? Colors.black87
        : const Color(0xFF1B4D3E);

    // Rodmapper Plus/Minus/Dividere/Gange: kun asset-ikon, ingen hvid boks.
    if (imageAsset != null) {
      return Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.white24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 160,
                      maxHeight: 120,
                    ),
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) =>
                          Icon(icon, size: 40, color: Colors.white),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                          color: Colors.white.withValues(alpha: 0.92),
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 1),
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
        ),
      );
    }

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
                  Icon(icon, size: 28, color: iconColor),
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

  /// Undermapper + evt. Spil — vandret scroll, centreret når der er plads.
  Widget _centeredFolderStrip(double viewportWidth) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: kidZoneHorizontalPadding,
        vertical: 8,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: viewportWidth - 2 * kidZoneHorizontalPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
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
              final img = widget.folderId == null
                  ? MathTasksService.kidIconAssetForMathFolderTitle(t)
                  : null;
              return _folderChip(
                title: t,
                subtitle: img != null
                    ? (tc > 0 ? '$tc opgaver' : '')
                    : (tc > 0 ? '$tc opgaver' : 'Mappe'),
                icon: Icons.folder_open,
                color: Colors.white.withValues(alpha: 0.95),
                imageAsset: img,
                onTap: () => context.push('/kid/math/${widget.kidId}/folder/$id'),
              );
            }),
          ],
        ),
      ),
    );
  }

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
          const KidParentAdminCornerButton(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFolderStrip = !_loading &&
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
                          : RefreshIndicator(
                                onRefresh: _load,
                                color: Colors.white,
                                child: LayoutBuilder(
                                  builder: (ctx, constraints) {
                                    final solved = _folderFullySolved;
                                    final w = constraints.maxWidth;
                                    return SingleChildScrollView(
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
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
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .titleLarge
                                                              ?.copyWith(
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
                                                else if (showFolderStrip)
                                                  _centeredFolderStrip(w)
                                                else if (_folders.isEmpty &&
                                                    widget.folderId != null &&
                                                    _playTaskCount == 0)
                                                  const Text('Ingen opgaver her.')
                                                else if (_folders.isEmpty && widget.folderId == null)
                                                  const Text(
                                                    'Din voksen skal oprette matematikmapper under Admin → Matematik.',
                                                    textAlign: TextAlign.center,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
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
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: KidGoldTreasuryCorner(
                kidId: widget.kidId,
                goldCoins: _kidGoldCoins,
                onAfterAlfamonsRoute: _load,
              ),
            ),
        ],
      ),
    );
  }
}
