import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/task.dart';
import '../../services/kid_daily_task_instances_service.dart';
import '../../services/task_completion_service.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'kid_layout_constants.dart';
import 'widgets/gold_coins_earned_overlay.dart';
import 'widgets/kid_gold_treasury_corner.dart';
import 'widgets/kid_session_nav_button.dart';

/// Dagens opgaver – baggrund `alfamonbaggrund.svg`, opgaver øverst, kiste som på hjem.
class KidTasksScreen extends StatefulWidget {
  const KidTasksScreen({super.key, required this.kidId});

  final String kidId;

  @override
  State<KidTasksScreen> createState() => _KidTasksScreenState();
}

class _KidTasksScreenState extends State<KidTasksScreen> {
  List<TaskInstance> _instances = [];
  bool _loading = true;
  final Map<String, int> _countInput = {};
  String? _completingId;
  int _goldCoins = 0;
  int? _flashGoldAmount;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    final client = Supabase.instance.client;
    final visible =
        await KidDailyTaskInstancesService.loadTodayVisibleInstances(
      widget.kidId,
    );

    final goldRes = await client
        .from('kids')
        .select('gold_coins')
        .eq('id', widget.kidId)
        .maybeSingle();
    final gold = (goldRes?['gold_coins'] as num?)?.toInt() ?? 0;

    if (!mounted) return;
    setState(() {
      _instances = visible;
      _goldCoins = gold;
      _loading = false;
    });
  }

  Future<void> _complete(TaskInstance ti, GlobalKey key) async {
    if (ti.status != 'pending') return;

    final codeOk = await _showParentCodeDialog();
    if (codeOk != true || !mounted) return;

    setState(() => _completingId = ti.id);

    try {
      final result = await TaskCompletionService.complete(
        taskInstanceId: ti.id,
        kidId: widget.kidId,
        count: ti.task.mode == 'counter' ? _countInput[ti.id] : null,
      );

      if (result.dailyBonus != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Du fik ${result.dailyBonus} ekstra guldmønter for at færdiggøre alle dagens opgaver!',
            ),
          ),
        );
      }

      final gained = result.points + (result.dailyBonus ?? 0);
      if (gained > 0 && mounted) {
        setState(() => _flashGoldAmount = gained);
        Future.delayed(const Duration(milliseconds: 2800), () {
          if (mounted) setState(() => _flashGoldAmount = null);
        });
      }

      await _loadToday();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _completingId = null);
    }
  }

  Future<bool> _showParentCodeDialog() async {
    final storedRes = await Supabase.instance.client
        .from('settings')
        .select('value')
        .eq('key', 'approval_code')
        .maybeSingle();
    final storedCode = (storedRes?['value'] as String?)?.trim() ?? '';
    if (storedCode.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Forældrekode er ikke sat. En voksen skal logge ind som forælder og sætte koden.',
            ),
          ),
        );
      }
      return false;
    }

    if (!mounted) return false;
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ParentCodeDialog(),
    );
    if (code == null) return false;
    if (code.trim() != storedCode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forkert forældrekode')),
        );
      }
      return false;
    }
    return true;
  }

  List<TaskInstance> get _pendingTasks =>
      _instances.where((ti) => ti.status == 'pending').toList();

  Widget _buildTasksSection() {
    final tasks = _pendingTasks;
    if (tasks.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // Under tilbage-knap (tekst er centreret og kan ellers ramme knappen)
          padding: const EdgeInsets.only(top: 52),
          child: Text(
            'Ingen opgaver i dag!',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: w.isFinite && w > 0 ? w : 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: tasks
                  .toList()
                  .reversed
                  .map(
                    (ti) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _TaskCard(
                        instance: ti,
                        countInput: _countInput,
                        onCountChanged: (c) =>
                            setState(() => _countInput[ti.id] = c),
                        onComplete: (_) => _complete(ti, GlobalKey()),
                        isCompleting: _completingId == ti.id,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/alfamonbaggrund.svg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Kortene er scrollet til højre, så venstre felt kan være tomt under knappen.
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kidZoneHorizontalPadding,
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          )
                        : _buildTasksSection(),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: kidZoneHorizontalPadding,
            child: KidSessionNavButton(kidId: widget.kidId),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: kidZoneHorizontalPadding,
            child: const KidParentAdminCornerButton(),
          ),
          Positioned(
            right: kidZoneHorizontalPadding,
            bottom: bottomInset + 12,
            child: KidGoldTreasuryCorner(
              kidId: widget.kidId,
              goldCoins: _goldCoins,
              onAfterAlfamonsRoute: _loadToday,
            ),
          ),
          if (_flashGoldAmount != null)
            Positioned.fill(
              child: GoldCoinsEarnedOverlay(amount: _flashGoldAmount!),
            ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.instance,
    required this.countInput,
    required this.onCountChanged,
    required this.onComplete,
    required this.isCompleting,
  });

  final TaskInstance instance;
  final Map<String, int> countInput;
  final void Function(int) onCountChanged;
  final void Function(GlobalKey) onComplete;
  final bool isCompleting;

  @override
  Widget build(BuildContext context) {
    final ti = instance;
    final isCounter = ti.task.mode == 'counter';
    final points = isCounter
        ? ti.task.pointsPerUnit ?? 0
        : ti.task.pointsFixed ?? 0;
    final count = countInput[ti.id] ?? 0;
    final canComplete = !isCounter || count > 0;

    const cardWidth = 150.0;

    return SizedBox(
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Card(
          margin: EdgeInsets.zero,
          color: Colors.white.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    ti.task.displayEmoji,
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ti.task.title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '⭐ $points ${isCounter ? 'pr. stk' : 'guldmønter'}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ti.requiredCompletions > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${ti.completionsDone} / ${ti.requiredCompletions} gange i dag',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isCounter) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => onCountChanged(count - 1),
                        icon: const Icon(Icons.remove, size: 14),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(2),
                          minimumSize: const Size(28, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: Colors.black12,
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => onCountChanged(count + 1),
                        icon: const Icon(Icons.add, size: 14),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(2),
                          minimumSize: const Size(28, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: Colors.black12,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: canComplete && !isCompleting
                      ? () => onComplete(GlobalKey())
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9C433),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: isCompleting
                      ? const Text('...', style: TextStyle(fontSize: 11))
                      : Text(
                          isCounter ? 'Færdig ($count)' : 'Færdig',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParentCodeDialog extends StatefulWidget {
  const _ParentCodeDialog();

  @override
  State<_ParentCodeDialog> createState() => _ParentCodeDialogState();
}

class _ParentCodeDialogState extends State<_ParentCodeDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forældrekode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bed en voksen om at indtaste forældrekoden for at færdiggøre opgaven.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              hintText: '••••',
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuller'),
        ),
        FilledButton(
          onPressed: _controller.text.length == 4 ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A1A0D),
          ),
          child: const Text('Bekræft'),
        ),
      ],
    );
  }

  void _submit() {
    if (_controller.text.length != 4) return;
    Navigator.of(context).pop(_controller.text);
  }
}
