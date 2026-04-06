import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/math_tasks_service.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import '../../utils/math_task_parse.dart';
import '../../utils/math_tutor_lesson.dart';
import '../../utils/math_tutor_prerecorded_intro.dart';
import '../../utils/math_vertical_prompt.dart';
import 'kid_layout_constants.dart';
import 'widgets/gold_coins_earned_overlay.dart';
import 'widgets/kid_gold_treasury_corner.dart';
import 'widgets/kid_math_black_popup_card.dart';
import 'kid_math_input_device.dart';
import 'widgets/kid_math_numeric_keypad.dart';
import 'widgets/math_tutor_help_sheet.dart';

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
  int _pendingGoldCoins = 0;
  bool _loading = true;
  final _answer = TextEditingController();
  final _answerFocus = FocusNode();
  /// Lodret opstilling: ét felt pr. svarciffer (venstre = højeste plads).
  final List<TextEditingController> _vertDigitControllers = [];
  final List<FocusNode> _vertDigitFocus = [];

  static const double _vertProblemDigitSize = 34;
  int _rate = 2;
  int _helpCost = 1;
  /// Under korrekt-popup: optjening for netop den løste opgave (til kistetal).
  int _stagedEarnCoins = 0;
  String? _folderTitle;
  int? _overlayGold;
  String? _loadError;
  int _dbGold = 0;
  bool _correctDialogOpen = false;
  final AudioPlayer _wrongAnswerPlayer = AudioPlayer();
  /// Plus/minus: vis regnestykke lodret (skolepapir) i stedet for én linje.
  bool _useVerticalAddSub = false;

  int get _effectiveRate => _rate < 0 ? 0 : _rate;

  /// Guldmønter i kisten + optjent i mappen (afventer Afslut i DB). Under korrekt-popup medregnes netop optjent beløb.
  int get _displayGoldCoins =>
      _dbGold +
      _pendingGoldCoins +
      (_correctDialogOpen ? _stagedEarnCoins : 0);

  bool get _useInAppKeypad => kidUseInAppNumericKeypad();

  void _playNumpadDigit(int d) {
    if (_tasks.isEmpty || _index >= _tasks.length) return;
    final exp = _tasks[_index]['answer'] as String? ?? '';
    final maxLen = math.max(3, _intAnswerDigitCount(exp) + 1);
    if (_useVerticalAnswerFields()) {
      var idx = _vertDigitFocus.indexWhere((f) => f.hasFocus);
      if (idx < 0) {
        idx = _vertDigitControllers.indexWhere((c) => c.text.isEmpty);
      }
      if (idx < 0) idx = _vertDigitControllers.length - 1;
      if (idx >= 0 && idx < _vertDigitControllers.length) {
        setState(() => _vertDigitControllers[idx].text = '$d');
        _maybeAutoSwitchVerticalFocus(_vertDigitControllers.length, idx);
      }
    } else {
      if (_answer.text.length >= maxLen) return;
      setState(() => _answer.text += '$d');
    }
  }

  void _playNumpadBackspace() {
    if (_useVerticalAnswerFields()) {
      var idx = _vertDigitFocus.indexWhere((f) => f.hasFocus);
      if (idx < 0) {
        for (var i = _vertDigitControllers.length - 1; i >= 0; i--) {
          if (_vertDigitControllers[i].text.isNotEmpty) {
            idx = i;
            break;
          }
        }
      }
      if (idx >= 0 && idx < _vertDigitControllers.length) {
        final t = _vertDigitControllers[idx].text;
        if (t.isNotEmpty) {
          setState(() => _vertDigitControllers[idx].text = '');
        }
      }
    } else {
      final t = _answer.text;
      if (t.isNotEmpty) {
        setState(() => _answer.text = t.substring(0, t.length - 1));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    _answerFocus.dispose();
    _disposeVertDigitFieldsOnly();
    unawaited(_wrongAnswerPlayer.dispose());
    super.dispose();
  }

  void _disposeVertDigitFieldsOnly() {
    for (final c in _vertDigitControllers) {
      c.dispose();
    }
    for (final f in _vertDigitFocus) {
      f.dispose();
    }
    _vertDigitControllers.clear();
    _vertDigitFocus.clear();
  }

  /// Kaldes efter opgave-skift / layout-skift (inde i [setState] er OK).
  void _syncVerticalDigitControllersFromCurrentTask() {
    if (_tasks.isEmpty || _index >= _tasks.length) {
      _disposeVertDigitFieldsOnly();
      return;
    }
    final p = _tasks[_index]['prompt'] as String? ?? '';
    if (!(_useVerticalAddSub && tryParseSingleAddSub(p) != null)) {
      _disposeVertDigitFieldsOnly();
      return;
    }
    final exp = _tasks[_index]['answer'] as String? ?? '';
    final n = math.max(1, _intAnswerDigitCount(exp));
    if (_vertDigitControllers.length == n) return;
    _disposeVertDigitFieldsOnly();
    for (var i = 0; i < n; i++) {
      _vertDigitControllers.add(TextEditingController());
      _vertDigitFocus.add(FocusNode());
    }
  }

  void _fillVerticalControllersRightAligned(String digitsOnly) {
    final n = _vertDigitControllers.length;
    if (n == 0) return;
    for (final c in _vertDigitControllers) {
      c.clear();
    }
    if (!RegExp(r'^\d+$').hasMatch(digitsOnly)) return;
    final take = digitsOnly.length > n
        ? digitsOnly.substring(digitsOnly.length - n)
        : digitsOnly;
    final pad = n - take.length;
    for (var i = 0; i < take.length; i++) {
      _vertDigitControllers[pad + i].text = take[i];
    }
  }

  bool _useVerticalAnswerFields() {
    if (_tasks.isEmpty || _index >= _tasks.length) return false;
    final p = _tasks[_index]['prompt'] as String? ?? '';
    return _useVerticalAddSub && tryParseSingleAddSub(p) != null;
  }

  /// Antal cifre i heltals-svaret (til opdeling i tiere/enere).
  static int _intAnswerDigitCount(String expectedAnswer) {
    final a = expectedAnswer
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '.');
    final v = num.tryParse(a);
    if (v != null) return v.round().abs().toString().length;
    final digits = RegExp(r'\d+').firstMatch(a)?.group(0) ?? '';
    if (digits.isEmpty) return 1;
    return digits.length;
  }

  static String _answerDigitsString(String expectedAnswer) {
    final a = expectedAnswer
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(',', '.');
    final v = num.tryParse(a);
    if (v != null) return v.round().abs().toString();
    return RegExp(r'\d+').firstMatch(a)?.group(0) ?? '';
  }

  /// Antal korrekte svarcifre fra højre (til at vise mente trinvis).
  int _matchingAnswerSuffixDigits(String expectedAnswer) {
    if (!_useVerticalAnswerFields()) return 0;
    final exp = _answerDigitsString(expectedAnswer);
    if (exp.isEmpty) return 0;
    final got = _composedVerticalAnswer();
    if (got.isEmpty) return 0;
    var k = 0;
    final maxK = math.min(got.length, exp.length);
    while (k < maxK &&
        got[got.length - 1 - k] == exp[exp.length - 1 - k]) {
      k++;
    }
    return k;
  }

  Widget? _buildCarryRowForVerticalAdd(
    BuildContext context,
    MathAddSubParts parts,
    String expectedAnswer,
  ) {
    if (parts.operator != '+') return null;
    final slots = additionCarrySlotsForAdd(parts);
    if (slots.isEmpty) return null;
    final line = additionCarryLineForDisplay(
      parts,
      slots,
      _matchingAnswerSuffixDigits(expectedAnswer),
    );
    if (line == null) return null;
    final fs = MediaQuery.textScalerOf(context).scale(_vertProblemDigitSize);
    final style = TextStyle(
      fontSize: fs,
      height: 1.05,
      fontWeight: FontWeight.w300,
      color: Colors.black87,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final w = mathVerticalColumnWidth(parts, _vertProblemDigitSize);
    return mathAlignedDigitRow(
      line: line,
      columnWidth: w,
      style: style,
    );
  }

  String _composedVerticalAnswer() {
    if (_vertDigitControllers.isEmpty) return '';
    return _vertDigitControllers.map((c) => c.text).join();
  }

  void _focusAnswerField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_useVerticalAnswerFields() && _vertDigitFocus.isNotEmpty) {
        _vertDigitFocus.last.requestFocus();
      } else {
        _answerFocus.requestFocus();
      }
    });
  }

  /// Skifter mellem vandret og lodret opstilling (3× større knap end tidl. 24 px).
  static const double _mathOpstillingIconSize = 72;

  void _onMathOpstillingTogglePressed() {
    setState(() {
      if (!_useVerticalAddSub) {
        _useVerticalAddSub = true;
        _syncVerticalDigitControllersFromCurrentTask();
        final raw = _answer.text.trim();
        if (RegExp(r'^\d+$').hasMatch(raw) && raw.isNotEmpty) {
          _fillVerticalControllersRightAligned(raw);
        }
      } else {
        _useVerticalAddSub = false;
        final merged = _composedVerticalAnswer();
        if (merged.isNotEmpty) {
          _answer.text = merged;
        }
        _disposeVertDigitFieldsOnly();
      }
    });
    _focusAnswerField();
  }

  Widget _mathOpstillingToggleButton() {
    const pad = 12.0;
    const r = 21.0;
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: _useVerticalAddSub ? 4 : 1,
      borderRadius: BorderRadius.circular(r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _onMathOpstillingTogglePressed,
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: Image.asset(
            'assets/math_opstill_ikon.webp',
            height: _mathOpstillingIconSize,
            width: _mathOpstillingIconSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => Icon(
              Icons.view_agenda,
              size: _mathOpstillingIconSize * 0.72,
            ),
          ),
        ),
      ),
    );
  }

  void _maybeAutoSwitchVerticalFocus(int n, int changedIndex) {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (n <= 1 || changedIndex < 0 || changedIndex >= n) return;
      if (_vertDigitControllers.length != n) return;
      bool hasChar(int i) =>
          i >= 0 && i < n && _vertDigitControllers[i].text.isNotEmpty;
      if (!hasChar(changedIndex)) return;
      int? next;
      for (var d = 1; d < n; d++) {
        final r = changedIndex + d;
        if (r < n && !hasChar(r)) {
          next = r;
          break;
        }
        final l = changedIndex - d;
        if (l >= 0 && !hasChar(l)) {
          next = l;
          break;
        }
      }
      if (next != null) _vertDigitFocus[next].requestFocus();
    });
  }

  void _focusNextEmptyNearIndex(int i, int n) {
    for (var d = 1; d < n; d++) {
      final r = i + d;
      if (r < n && _vertDigitControllers[r].text.isEmpty) {
        _vertDigitFocus[r].requestFocus();
        return;
      }
      final l = i - d;
      if (l >= 0 && _vertDigitControllers[l].text.isEmpty) {
        _vertDigitFocus[l].requestFocus();
        return;
      }
    }
  }

  void _onVerticalDigitSubmitted(int n, int index) {
    final allFull = _vertDigitControllers.every((c) => c.text.isNotEmpty);
    if (allFull) {
      _submitAnswer();
      return;
    }
    _focusNextEmptyNearIndex(index, n);
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
      final rate = MathTasksService.effectiveGoldPerTask(widget.folderId, folderById);
      final helpCost =
          MathTasksService.effectiveMathHelpGoldCost(widget.folderId, folderById);
      final prog = await MathTasksService.fetchProgress(
        kidId: widget.kidId,
        folderId: widget.folderId,
        legacyTasksTimesRate: rate,
      );
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
        _pendingGoldCoins = prog.pendingGoldCoins;
        _rate = rate;
        _helpCost = helpCost;
        _folderTitle = title;
        _dbGold = g;
        _loading = false;
        _answer.clear();
        _syncVerticalDigitControllersFromCurrentTask();
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

  String _correctGoldSentence(int coins) {
    final c = coins < 0 ? 0 : coins;
    if (c == 0) {
      return 'Ja det var rigtigt — ingen guldstykker denne gang.';
    }
    if (c == 1) {
      return 'Ja det var rigtigt - du har tjent et guldstykke.';
    }
    return 'Ja det var rigtigt - du har tjent $c guldstykker.';
  }

  Future<void> _submitAnswer() async {
    if (_tasks.isEmpty || _index >= _tasks.length) return;
    final task = _tasks[_index];
    final expected = task['answer'] as String? ?? '';
    final given =
        _useVerticalAnswerFields() ? _composedVerticalAnswer() : _answer.text;
    if (!mathAnswersMatch(expected, given)) {
      if (!mounted) return;
      try {
        await _wrongAnswerPlayer.stop();
      } catch (_) {}
      final played = await mathTutorTryPlayOevProevIgen(_wrongAnswerPlayer);
      if (mounted) _focusAnswerField();
      if (!played && mounted) {
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
        if (mounted) _focusAnswerField();
      }
      return;
    }

    await _completeCurrentTaskSuccess();
  }

  /// Efter rigtigt svar (feltet eller matematikhjælp): gulddialog, fremskridt og næste opgave.
  Future<void> _completeCurrentTaskSuccess({bool usedMathHelp = false}) async {
    if (!mounted) return;
    final earn = MathTasksService.coinsEarnedForMathTask(
      baseGoldWithoutHelp: _effectiveRate,
      helpGoldCost: _helpCost < 0 ? 0 : _helpCost,
      usedMathHelp: usedMathHelp,
    );
    setState(() {
      _correctDialogOpen = true;
      _stagedEarnCoins = earn;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/moent.webp',
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
                _correctGoldSentence(_stagedEarnCoins),
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
    setState(() {
      _correctDialogOpen = false;
      _stagedEarnCoins = 0;
    });

    final nextIdx = _index + 1;
    final nextPending = _pendingGoldCoins + earn;
    await MathTasksService.saveProgress(
      kidId: widget.kidId,
      folderId: widget.folderId,
      nextTaskIndex: nextIdx,
      pendingGoldCoins: nextPending,
    );
    if (!mounted) return;
    setState(() {
      _index = nextIdx;
      _pendingGoldCoins = nextPending;
      _answer.clear();
      _syncVerticalDigitControllersFromCurrentTask();
      for (final c in _vertDigitControllers) {
        c.clear();
      }
    });
    _focusAnswerField();
  }

  /// Udbetal ventende guldmønter. Ved [showEarnedOverlay] vises skærm når der er udbetalt beløb > 0.
  Future<void> _runSettle({required bool showEarnedOverlay}) async {
    if (_pendingGoldCoins <= 0) return;
    final amount = await MathTasksService.settlePendingGold(
      kidId: widget.kidId,
      folderId: widget.folderId,
      pendingGoldCoins: _pendingGoldCoins,
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
      _pendingGoldCoins = 0;
      _dbGold = newG;
      if (showEarnedOverlay && amount > 0) {
        _overlayGold = amount;
      }
    });
  }

  Future<void> _onCloseMathPlay() async {
    if (_pendingGoldCoins > 0) {
      await _runSettle(showEarnedOverlay: true);
      if (!mounted) return;
      if (_overlayGold == null || _overlayGold! <= 0) {
        context.go('/kid/math/${widget.kidId}');
      }
      return;
    }
    if (mounted) context.go('/kid/math/${widget.kidId}');
  }

  Future<void> _showMathTutorHelp(
    BuildContext context,
    MathAddSubParts parts,
  ) async {
    final lesson = buildMathTutorLesson(context, parts);
    if (lesson == null) return;
    final ok = await showMathTutorHelpSheet(context, lesson);
    if (ok == true && mounted) {
      await _completeCurrentTaskSuccess(usedMathHelp: true);
    }
  }

  Widget _mathBackground() {
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

  InputDecoration _mathAnswerInputDecoration() {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.95),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF1B4D3E), width: 2),
      ),
      counterText: '',
    );
  }

  Widget _buildVerticalDigitSlots(
    BuildContext context,
    String expectedAnswer,
    MathAddSubParts parts,
  ) {
    final n = math.max(1, _intAnswerDigitCount(expectedAnswer));
    if (_vertDigitControllers.length != n) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncVerticalDigitControllersFromCurrentTask();
        setState(() {});
      });
      return SizedBox(height: _vertProblemDigitSize * 1.8);
    }
    final columnW =
        mathVerticalColumnWidth(parts, _vertProblemDigitSize);
    final segW = columnW / n;
    final fs = MediaQuery.textScalerOf(context).scale(_vertProblemDigitSize);
    final ref = math.min(fs, segW * 0.98);
    final digitFont = ref * 0.78;
    return Align(
      alignment: Alignment.centerRight,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: _VerticalAnswerStrip(
          width: columnW,
          digitCount: n,
          digitFont: digitFont,
          controllers: _vertDigitControllers,
          focusNodes: _vertDigitFocus,
          readOnlyForNumpad: _useInAppKeypad,
          onChanged: (i) => _maybeAutoSwitchVerticalFocus(n, i),
          onSubmitted: (i) => _onVerticalDigitSubmitted(n, i),
        ),
      ),
    );
  }

  Widget _checkAnswerButton() {
    return Material(
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
    );
  }

  /// Selve opgaven (prompt, lodret-knap, svarfelt) – skaleres som helhed inde i papiret.
  Widget _buildActiveTaskColumn(
    BuildContext context, {
    required String prompt,
    required String expectedAnswer,
    required MathAddSubParts? addSubParts,
    required bool showVerticalToggle,
    bool useInAppKeypad = false,
    bool phoneTouchLayout = false,
  }) {
    final vertical =
        showVerticalToggle && _useVerticalAddSub && addSubParts != null;
    final readOnlyField = useInAppKeypad;
    final fieldKb =
        readOnlyField ? TextInputType.none : TextInputType.text;
    final promptStyle = const TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      height: 1.1,
      color: Colors.black87,
    );
    final double fieldW = useInAppKeypad
        ? 56
        : 24 + MediaQuery.textScalerOf(context).scale(26 * 1.05 * 3);
    final answerField = SizedBox(
      width: fieldW,
      child: TextField(
        controller: _answer,
        focusNode: _answerFocus,
        readOnly: readOnlyField,
        showCursor: true,
        keyboardType: fieldKb,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submitAnswer(),
        textAlign: TextAlign.center,
        maxLength: 4,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
        ],
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1B1B1B),
        ),
        decoration: _mathAnswerInputDecoration().copyWith(
          counterText: '',
        ),
      ),
    );
    final horizontalRowPhone = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.36,
          ),
          child: Text(
            prompt.trim(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: promptStyle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '=',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        answerField,
        const SizedBox(width: 10),
        _checkAnswerButton(),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width * 0.44;
        final horizontalRowWide = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW * 0.62),
              child: Text(
                prompt.trim(),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: promptStyle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '=',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            answerField,
            const SizedBox(width: 10),
            _checkAnswerButton(),
          ],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (vertical)
              Center(
                child: MathVerticalAddSubView(
                  parts: addSubParts,
                  digitFontSize: _vertProblemDigitSize,
                  carryRowAbove: _buildCarryRowForVerticalAdd(
                    context,
                    addSubParts,
                    expectedAnswer,
                  ),
                  belowDoubleRule: _buildVerticalDigitSlots(
                    context,
                    expectedAnswer,
                    addSubParts,
                  ),
                ),
              )
            else if (phoneTouchLayout)
              Center(child: horizontalRowPhone)
            else
              horizontalRowWide,
            SizedBox(height: vertical ? 14 : 10),
            if (vertical)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _checkAnswerButton(),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _mathPlayTopBar(
    BuildContext context, {
    required String title,
    bool compact = false,
  }) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _mathPlayCloseLeading(context),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/moent.webp',
                  height: 28,
                  width: 28,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.monetization_on,
                    color: Color(0xFFF9C433),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$_displayGoldCoins',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    shadows: _titleShadows,
                  ),
                ),
                const SizedBox(width: 8),
                const KidParentAdminCornerButton(size: 40),
              ],
            ),
          ],
        ),
      );
    }
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
          const KidParentAdminCornerButton(),
        ],
      ),
    );
  }

  Widget _mathPlayPaperBody({
    required BuildContext context,
    required String prompt,
    required MathTaskRow task,
    required MathAddSubParts? addSubParts,
    required bool showVerticalToggle,
    required bool useInAppKeypad,
  }) {
    final isPhone = kidIsPhoneLayout(context);
    final sw = MediaQuery.sizeOf(context).width;
    final paperCard = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  12,
                  showVerticalToggle ? 102 : 14,
                  12,
                ),
                child: LayoutBuilder(
                  builder: (ctx, inner) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: inner.maxHeight),
                        child: Center(
                          child: _buildActiveTaskColumn(
                            context,
                            prompt: prompt,
                            expectedAnswer: task['answer'] as String? ?? '',
                            addSubParts: addSubParts,
                            showVerticalToggle: showVerticalToggle,
                            useInAppKeypad: useInAppKeypad,
                            phoneTouchLayout: isPhone,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (showVerticalToggle)
              Positioned(
                top: 8,
                right: 8,
                child: _mathOpstillingToggleButton(),
              ),
          ],
        ),
      ),
    );

    /// Papir ca. halvdelen af skærmbredden; minhøjde ca. halvdelen af tilgængelig højde (scroll inde i feltet).
    final paperTargetMaxW = math.max(400.0, sw * 0.5);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 14 : 20,
        12,
        isPhone ? 14 : 20,
        16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final paperW = math.min(paperTargetMaxW, c.maxWidth);
                final availH =
                    c.maxHeight.isFinite && c.maxHeight > 0
                        ? c.maxHeight
                        : MediaQuery.sizeOf(context).height * 0.55;
                // Ca. halvdelen af tilgængelig højde (≈ dobbelt vs. kun indholdshøjde), max 92%.
                final paperH = math.min(
                  availH * 0.92,
                  math.max(400.0, availH * 0.52),
                );
                return Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: paperW,
                    height: paperH,
                    child: paperCard,
                  ),
                );
              },
            ),
          ),
          if (addSubParts != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Align(
                alignment: Alignment.topCenter,
                child: isPhone
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () =>
                                _showMathTutorHelp(context, addSubParts),
                            child: Image.asset(
                              'assets/tutor2.webp',
                              height: 88,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.school,
                                size: 62,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () =>
                                _showMathTutorHelp(context, addSubParts),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.35),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            child: const Text(
                              'Hjælp',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      )
                    : TextButton(
                        onPressed: () =>
                            _showMathTutorHelp(context, addSubParts),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor:
                              Colors.black.withValues(alpha: 0.35),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        child: const Text(
                          'Hjælp',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
              ),
            ),
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
    final addSubParts = prompt.isEmpty ? null : tryParseSingleAddSub(prompt);
    final showVerticalToggle = addSubParts != null;

    final showPaper =
        !_loading && _loadError == null && !done && task != null && _tasks.isNotEmpty;
    final touchPlay = showPaper && _useInAppKeypad;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _mathBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _mathPlayTopBar(
                  context,
                  title: _folderTitle ?? 'Matematik',
                  compact: touchPlay,
                ),
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
                                              _pendingGoldCoins > 0
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
                          : showPaper
                              ? _mathPlayPaperBody(
                                  context: context,
                                  prompt: prompt,
                                  task: task,
                                  addSubParts: addSubParts,
                                  showVerticalToggle: showVerticalToggle,
                                  useInAppKeypad: touchPlay,
                                )
                              : const SizedBox.shrink(),
                ),
                if (touchPlay)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 16,
                      bottom: math.max(
                        12.0,
                        MediaQuery.paddingOf(context).bottom + 8,
                      ),
                      left: 8,
                      right: 8,
                    ),
                    child: KidMathNumericKeypad(
                      onDigit: _playNumpadDigit,
                      onBackspace: _playNumpadBackspace,
                    ),
                  ),
              ],
            ),
          ),
          if (!touchPlay)
            Positioned(
              right: kidZoneHorizontalPadding,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: KidGoldTreasuryCorner(
                kidId: widget.kidId,
                goldCoins: _displayGoldCoins,
                onAfterAlfamonsRoute: _load,
              ),
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

/// Én samlet svarboks under stregerne med lodrette skillestreger mellem cifre.
class _VerticalAnswerStrip extends StatelessWidget {
  const _VerticalAnswerStrip({
    required this.width,
    required this.digitCount,
    required this.digitFont,
    required this.controllers,
    required this.focusNodes,
    required this.readOnlyForNumpad,
    required this.onChanged,
    required this.onSubmitted,
  });

  final double width;
  final int digitCount;
  final double digitFont;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool readOnlyForNumpad;
  final void Function(int index) onChanged;
  final void Function(int index) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final h = math.max(
      56.0,
      math.min(72.0, width / digitCount * 1.35),
    );
    const radius = 12.0;
    return SizedBox(
      width: width,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0xFF424242), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < digitCount; i++) ...[
                if (i > 0)
                  Container(
                    width: 2,
                    color: const Color(0xFF616161),
                  ),
                Expanded(
                  child: FocusTraversalOrder(
                    order: NumericFocusOrder((digitCount - i).toDouble()),
                    child: _StripDigitCell(
                      controller: controllers[i],
                      focusNode: focusNodes[i],
                      fontSize: digitFont,
                      readOnly: readOnlyForNumpad,
                      onChanged: () => onChanged(i),
                      onSubmitted: () => onSubmitted(i),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StripDigitCell extends StatefulWidget {
  const _StripDigitCell({
    required this.controller,
    required this.focusNode,
    required this.fontSize,
    required this.readOnly,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double fontSize;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  State<_StripDigitCell> createState() => _StripDigitCellState();
}

class _StripDigitCellState extends State<_StripDigitCell> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _StripDigitCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return ColoredBox(
      color: focused
          ? const Color(0xFFD8F0E0)
          : Colors.transparent,
      child: LayoutBuilder(
        builder: (context, c) {
          final innerW = math.max(4.0, c.maxWidth - 4);
          final eff = math.min(widget.fontSize, innerW * 0.68);
          return TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            readOnly: widget.readOnly,
            showCursor: true,
            keyboardType:
                widget.readOnly ? TextInputType.none : TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLines: 1,
            expands: false,
            textAlignVertical: TextAlignVertical.center,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            onChanged: (_) => widget.onChanged(),
            onSubmitted: (_) => widget.onSubmitted(),
            style: TextStyle(
              fontSize: eff,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1B1B1B),
            ),
            strutStyle: StrutStyle(
              fontSize: eff,
              height: 1.0,
              leading: 0,
              fontWeight: FontWeight.w800,
              forceStrutHeight: true,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              counterText: '',
            ),
          );
        },
      ),
    );
  }
}
