import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/math_tasks_service.dart';
import '../../utils/math_task_parse.dart';
import 'kid_layout_constants.dart';
import 'widgets/gold_coins_earned_overlay.dart';
import 'widgets/kid_gold_treasury_corner.dart';
import 'widgets/kid_math_black_popup_card.dart';

class KidMathPlayScreen extends StatefulWidget {
  const KidMathPlayScreen({
    super.key,
    required this.kidId,
    required this.folderId,
  });

  final String kidId;
  final String folderId;

  @override
  State<KidMathPlayScreen> createState() => _KidMathPlayScreenState();
}

class _KidMathPlayScreenState extends State<KidMathPlayScreen> {
  List<MathTaskRow> _tasks = [];
  int _index = 0;
  int _pending = 0;
  bool _loading = true;
  final _answer = TextEditingController();
  final _answerFocus = FocusNode();
  int _rate = 1;
  String? _folderTitle;
  int? _overlayGold;
  String? _loadError;
  int _dbGold = 0;
  bool _correctDialogOpen = false;

  int get _effectiveRate => _rate < 1 ? 1 : _rate;

  /// Guldmønter i kisten + optjent i mappen (afventer Afslut i DB). Under korrekt-popup tælles næste stykke med.
  int get _displayGoldCoins =>
      _dbGold + (_pending + (_correctDialogOpen ? 1 : 0)) * _effectiveRate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  void _focusAnswerField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _answerFocus.requestFocus();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final ctx = await MathTasksService.loadKidVisibilityContext(widget.kidId);
      final folderById = ctx.folderById;
      if (!MathTasksService.kidHasAccessToFolder(
        folderId: widget.folderId,
        assignedFolderIds: ctx.assigned,
        folderById: folderById,
      )) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Denne mappe er ikke til dig.')),
          );
          context.pop();
        }
        return;
      }
      final tasks = await MathTasksService.fetchTasks(widget.folderId);
      final prog = await MathTasksService.fetchProgress(
        kidId: widget.kidId,
        folderId: widget.folderId,
      );
      final rate = MathTasksService.effectiveGoldPerTask(widget.folderId, folderById);
      final title = folderById[widget.folderId]?['title'] as String? ?? 'Opgaver';
      final kidRow = await Supabase.instance.client
          .from('kids')
          .select('gold_coins')
          .eq('id', widget.kidId)
          .maybeSingle();
      final g = (kidRow?['gold_coins'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _index = prog.nextIndex.clamp(0, tasks.isEmpty ? 0 : tasks.length);
        _pending = prog.pendingGold;
        _rate = rate;
        _folderTitle = title;
        _dbGold = g;
        _loading = false;
        _answer.clear();
      });
      _focusAnswerField();
    } catch (e, stack) {
      debugPrint('KidMathPlayScreen._load: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _loadError = MathTasksService.describeLoadError(e);
        _loading = false;
      });
    }
  }

  String _correctGoldSentence(int rate) {
    final r = rate < 1 ? 1 : rate;
    if (r == 1) {
      return 'Ja det var rigtigt - du har tjent et guldstykke.';
    }
    return 'Ja det var rigtigt - du har tjent $r guldstykker.';
  }

  Future<void> _submitAnswer() async {
    if (_tasks.isEmpty || _index >= _tasks.length) return;
    final task = _tasks[_index];
    final expected = task['answer'] as String? ?? '';
    if (!mathAnswersMatch(expected, _answer.text)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Øv - prøv igen'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _focusAnswerField();
      return;
    }

    if (!mounted) return;
    setState(() => _correctDialogOpen = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/moent.png',
                height: 88,
                width: 88,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.monetization_on,
                  size: 88,
                  color: Color(0xFFF9C433),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _correctGoldSentence(_effectiveRate),
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Videre'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _correctDialogOpen = false);

    final nextIdx = _index + 1;
    final nextPending = _pending + 1;
    await MathTasksService.saveProgress(
      kidId: widget.kidId,
      folderId: widget.folderId,
      nextTaskIndex: nextIdx,
      pendingGoldTasks: nextPending,
    );
    if (!mounted) return;
    setState(() {
      _index = nextIdx;
      _pending = nextPending;
      _answer.clear();
    });
    _focusAnswerField();
  }

  /// Udbetal ventende guldmønter. Ved [showEarnedOverlay] vises skærm når der er udbetalt beløb > 0.
  Future<void> _runSettle({required bool showEarnedOverlay}) async {
    if (_pending <= 0) return;
    final amount = await MathTasksService.settlePendingGold(
      kidId: widget.kidId,
      folderId: widget.folderId,
      pendingCount: _pending,
      coinsPerTask: _effectiveRate,
    );
    if (!mounted) return;
    final kidRow = await Supabase.instance.client
        .from('kids')
        .select('gold_coins')
        .eq('id', widget.kidId)
        .maybeSingle();
    final newG = (kidRow?['gold_coins'] as num?)?.toInt() ?? _dbGold + amount;
    if (!mounted) return;
    setState(() {
      _pending = 0;
      _dbGold = newG;
      if (showEarnedOverlay && amount > 0) {
        _overlayGold = amount;
      }
    });
  }

  Future<void> _onCloseMathPlay() async {
    if (_pending > 0) {
      await _runSettle(showEarnedOverlay: true);
      if (!mounted) return;
      if (_overlayGold == null || _overlayGold! <= 0) {
        context.go('/kid/math/${widget.kidId}');
      }
      return;
    }
    if (mounted) context.go('/kid/math/${widget.kidId}');
  }

  Widget _mathBackground() {
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

  /// Afslut opgaveløsning og gå til matematik-hjem (mapper).
  Widget _mathPlayCloseLeading(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Afslut opgaver',
        icon: const Icon(Icons.close, color: Colors.white, size: 24),
        onPressed: _onCloseMathPlay,
      ),
    );
  }

  static const _titleShadows = [
    Shadow(offset: Offset(0, 1), blurRadius: 5, color: Colors.black54),
  ];

  Widget _mathPlayTopBar(BuildContext context, {required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _mathPlayCloseLeading(context),
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
    if (_loading) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            _mathBackground(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _mathPlayTopBar(context, title: 'Matematik'),
                  const Expanded(
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            _mathBackground(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _mathPlayTopBar(context, title: 'Matematik'),
                  Expanded(
                    child: Padding(
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
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final done = _tasks.isNotEmpty && _index >= _tasks.length;
    final task = (!done && _tasks.isNotEmpty) ? _tasks[_index] : null;
    final prompt = task?['prompt'] as String? ?? '';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _mathBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _mathPlayTopBar(context, title: _folderTitle ?? 'Matematik'),
                Expanded(
                  child: _tasks.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
                          child: Text(
                            'Ingen opgaver i denne mappe.',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : done
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                    child: Center(
                                      child: KidMathBlackPopupCard(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.celebration, size: 64, color: Color(0xFFF9C433)),
                                            const SizedBox(height: 16),
                                            Text(
                                              'Du har løst alle opgaver i mappen!',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              _pending > 0
                                                  ? 'Tryk på krydset øverst for at gå tilbage og hente dine guldmønter.'
                                                  : 'Tryk på krydset øverst for at gå tilbage.',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                    color: Colors.white.withValues(alpha: 0.85),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 520),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (_tasks.length > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: Text(
                                            'Opgave ${_index + 1} af ${_tasks.length}',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      Text(
                                        prompt,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700,
                                          height: 1.15,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          const Text(
                                            '=',
                                            style: TextStyle(
                                              fontSize: 34,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextField(
                                              controller: _answer,
                                              focusNode: _answerFocus,
                                              keyboardType: TextInputType.text,
                                              textInputAction: TextInputAction.done,
                                              onSubmitted: (_) => _submitAnswer(),
                                              style: const TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1B1B1B),
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Skriv her',
                                                isDense: true,
                                                filled: true,
                                                fillColor: Colors.white.withValues(alpha: 0.95),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 14,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Colors.white.withValues(alpha: 0.8),
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFF1B4D3E),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Material(
                                            color: const Color(0xFF2B9348),
                                            shape: const CircleBorder(),
                                            elevation: 3,
                                            child: InkWell(
                                              customBorder: const CircleBorder(),
                                              onTap: _submitAnswer,
                                              child: const Padding(
                                                padding: EdgeInsets.all(14),
                                                child: Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 30,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ),
          Positioned(
            right: kidZoneHorizontalPadding,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: KidGoldTreasuryCorner(goldCoins: _displayGoldCoins),
          ),
          if (_overlayGold != null && _overlayGold! > 0)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() => _overlayGold = null);
                  context.go('/kid/math/${widget.kidId}');
                },
                child: GoldCoinsEarnedOverlay(amount: _overlayGold!),
              ),
            ),
        ],
      ),
    );
  }
}
