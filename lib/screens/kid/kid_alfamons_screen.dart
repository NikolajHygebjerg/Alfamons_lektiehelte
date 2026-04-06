import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/alfamon_evolution.dart';
import '../../services/task_completion_service.dart';
import '../../utils/card_assets.dart';
import '../../widgets/asset_or_network_image.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/alfamon_evolution_progress_bar.dart';
import 'widgets/kid_session_nav_button.dart';

const _danishAlphabet = 'abcdefghijklmnopqrstuvwxyzæøå';

class KidAlfamonsScreen extends StatefulWidget {
  final String kidId;

  const KidAlfamonsScreen({super.key, required this.kidId});

  @override
  State<KidAlfamonsScreen> createState() => _KidAlfamonsScreenState();
}

class _UnlockedAlphamon {
  final String avatarId;
  final String letter;
  final String name;
  final String? imageUrl;
  final int currentStage;
  final int maxStage;

  /// Guldmønter allerede brugt på denne Alfamon (udvikling).
  final int pointsInvested;

  _UnlockedAlphamon({
    required this.avatarId,
    required this.letter,
    required this.name,
    this.imageUrl,
    required this.currentStage,
    required this.maxStage,
    required this.pointsInvested,
  });
}

class _KidAlfamonsScreenState extends State<KidAlfamonsScreen> {
  Set<String> _unlockedLetters = {};
  Map<String, _UnlockedAlphamon> _unlockedAlphamons = {};
  String? _activeAvatarId;
  String? _unlockCode;
  bool _loading = true;
  String? _selectedLetter;
  bool _showCodeModal = false;
  final _codeController = TextEditingController();
  bool _unlocking = false;
  String? _error;
  int _goldCoins = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;

    final kidGoldRes = await client
        .from('kids')
        .select('gold_coins')
        .eq('id', widget.kidId)
        .maybeSingle();
    final treasury = (kidGoldRes?['gold_coins'] as num?)?.toInt() ?? 0;

    final activeRes = await client
        .from('kid_active_avatar')
        .select('avatar_id')
        .eq('kid_id', widget.kidId)
        .maybeSingle();
    final activeId = activeRes?['avatar_id'] as String?;

    final settingsRes = await client
        .from('settings')
        .select('value')
        .eq('key', 'alphamon_unlock_code')
        .maybeSingle();
    final rawCode = settingsRes?['value'];
    final code = rawCode == null
        ? '0881'
        : rawCode is String
            ? rawCode.trim()
            : rawCode.toString().trim();

    final unlockedRes = await client
        .from('kid_unlocked_alphamons')
        .select('avatar_id,avatars(id,name,letter,points_per_stage)')
        .eq('kid_id', widget.kidId);

    if (unlockedRes == null || (unlockedRes as List).isEmpty) {
      setState(() {
        _activeAvatarId = activeId;
        _unlockCode = code;
        _unlockedLetters = {};
        _unlockedAlphamons = {};
        _goldCoins = treasury;
        _loading = false;
      });
      return;
    }

    final unlocked = unlockedRes as List;
    final avatarIds = unlocked
        .map((e) => e['avatar_id'] as String)
        .toSet()
        .toList();
    final libRes = await client
        .from('kid_avatar_library')
        .select('avatar_id,current_stage_index,points_current')
        .eq('kid_id', widget.kidId)
        .inFilter('avatar_id', avatarIds);
    final stagesRes = await client
        .from('avatar_stages')
        .select('avatar_id,stage_index,image_url')
        .inFilter('avatar_id', avatarIds);

    final libMap = <String, Map<String, dynamic>>{};
    for (final r in libRes as List) {
      libMap[r['avatar_id'] as String] = Map<String, dynamic>.from(r);
    }
    final stageMap = <String, Map<int, String>>{};
    final maxStageMap = <String, int>{};
    for (final s in stagesRes as List) {
      final aid = s['avatar_id'] as String;
      final idx = AlfamonEvolution.stageIndexFromJson(s['stage_index']);
      stageMap.putIfAbsent(aid, () => {});
      stageMap[aid]![idx] = (s['image_url'] as String? ?? '').trim();
      if ((maxStageMap[aid] ?? -1) < idx) maxStageMap[aid] = idx;
    }

    final letters = <String>{};
    final alphamons = <String, _UnlockedAlphamon>{};
    for (final u in unlocked) {
      final av = u['avatars'];
      if (av == null) continue;
      final avMap = Map<String, dynamic>.from(av as Map);
      final letter = (avMap['letter'] as String? ?? '').toLowerCase();
      if (letter.isEmpty) continue;
      letters.add(letter);
      final avatarId = avMap['id'] as String;
      final lib = libMap[avatarId];
      final points = AlfamonEvolution.pointsFromJson(lib?['points_current']);
      final stagesForAvatar = (stagesRes as List)
          .where((s) => s['avatar_id'] == avatarId)
          .toList();
      final sorted = AlfamonEvolution.sortedStageIndicesFromRows(
        stagesForAvatar,
      );
      final stageIdx = AlfamonEvolution.stageIndexFromPoints(points, sorted);
      final storedStage =
          AlfamonEvolution.stageIndexFromJson(lib?['current_stage_index']);
      if (lib != null && storedStage != stageIdx) {
        await client
            .from('kid_avatar_library')
            .update({'current_stage_index': stageIdx})
            .eq('kid_id', widget.kidId)
            .eq('avatar_id', avatarId);
      }
      final maxStage = maxStageMap[avatarId] ?? 0;
      var imageUrl = stageMap[avatarId]?[stageIdx];
      if (imageUrl == null || imageUrl.isEmpty) {
        final paths = CardAssets.getCardImagePathsToTry(
          avMap['name'] as String? ?? 'Alfamon',
          stageIdx,
          letter: avMap['letter'] as String?,
        );
        if (paths.isNotEmpty) imageUrl = paths.first;
      }
      alphamons[letter] = _UnlockedAlphamon(
        avatarId: avatarId,
        letter: letter,
        name: avMap['name'] as String? ?? 'Alfamon',
        imageUrl: imageUrl != null && imageUrl.isNotEmpty ? imageUrl : null,
        currentStage: stageIdx,
        maxStage: maxStage,
        pointsInvested: points,
      );
    }
    setState(() {
      _activeAvatarId = activeId;
      _unlockCode = code;
      _unlockedLetters = letters;
      _unlockedAlphamons = alphamons;
      _goldCoins = treasury;
      _loading = false;
    });
  }

  void _onLetterTap(String letter) {
    if (_unlockedLetters.contains(letter)) {
      _openAlfamonUpgradeSheet(_unlockedAlphamons[letter]!);
      return;
    }
    setState(() {
      _selectedLetter = letter;
      _showCodeModal = true;
      _codeController.clear();
      _error = null;
    });
  }

  Future<void> _openAlfamonUpgradeSheet(_UnlockedAlphamon a) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: _AlfamonUpgradeSheet(
            kidId: widget.kidId,
            alphamon: a,
            treasuryGold: _goldCoins,
            onTreasuryUpdated: (g) {
              if (mounted) setState(() => _goldCoins = g);
            },
            onReload: _load,
          ),
        );
      },
    );
  }

  Future<void> _setActiveAvatarForHome(String avatarId) async {
    final client = Supabase.instance.client;
    final libRes = await client
        .from('kid_avatar_library')
        .select('points_current')
        .eq('kid_id', widget.kidId)
        .eq('avatar_id', avatarId)
        .maybeSingle();
    final points = (libRes?['points_current'] as num?)?.toInt() ?? 0;
    await client.from('kid_active_avatar').upsert({
      'kid_id': widget.kidId,
      'avatar_id': avatarId,
      'points_current': points,
    }, onConflict: 'kid_id');
    if (mounted) {
      setState(() => _activeAvatarId = avatarId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Denne Alfamon vises nu på hjemmeskærmen'),
        ),
      );
    }
  }

  String _unlockFailureMessage(Object error) {
    if (error is PostgrestException) {
      final msg = error.message;
      final lower = msg.toLowerCase();
      if (error.code == '23505' ||
          lower.contains('duplicate') ||
          lower.contains('unique')) {
        return 'Allerede låst op!';
      }
      if (lower.contains('jwt') ||
          lower.contains('permission denied') ||
          lower.contains('row-level security') ||
          lower.contains('policy') ||
          error.code == '42501') {
        return 'Ingen adgang. Prøv igen, eller log ind som forælder.';
      }
      if (lower.contains('more than one') || lower.contains('multiple')) {
        return 'Flere Alfamons har samme bogstav i databasen. Kontakt support.';
      }
      return msg;
    }
    return 'Noget gik galt. Tjek forbindelsen og prøv igen.';
  }

  /// Ét avatar-række pr. bogstav; [limit(1)] undgår at [maybeSingle] fejler ved dubletter.
  Future<Map<String, dynamic>?> _avatarByLetter(String letter) async {
    final client = Supabase.instance.client;
    final variants = <String>{
      letter,
      letter.toLowerCase(),
      letter.toUpperCase(),
    };
    for (final v in variants) {
      if (v.isEmpty) continue;
      final rows = await client
          .from('avatars')
          .select('id,name')
          .eq('letter', v)
          .limit(1);
      final list = rows as List;
      if (list.isNotEmpty) {
        return Map<String, dynamic>.from(list.first as Map);
      }
    }
    return null;
  }

  Future<void> _unlock() async {
    final letter = _selectedLetter;
    if (letter == null) return;

    final expected = (_unlockCode ?? '').trim();
    if (expected.isEmpty) {
      setState(
        () => _error =
            'Oplåsningskode mangler. Luk vinduet og åbn Alfamons igen.',
      );
      return;
    }
    if (_codeController.text.trim() != expected) {
      setState(() => _error = 'Forkert kode! Prøv igen.');
      return;
    }

    setState(() {
      _unlocking = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final avRow = await _avatarByLetter(letter);
      if (avRow == null) {
        if (mounted) {
          setState(() {
            _error = 'Ingen Alfamon fundet for dette bogstav.';
            _unlocking = false;
          });
        }
        return;
      }
      final avatarId = avRow['id'] as String;
      final existing = await client
          .from('kid_unlocked_alphamons')
          .select('id')
          .eq('kid_id', widget.kidId)
          .eq('avatar_id', avatarId)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Allerede låst op!';
            _unlocking = false;
          });
        }
        return;
      }
      await client.from('kid_unlocked_alphamons').insert({
        'kid_id': widget.kidId,
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
        'kid_id': widget.kidId,
        'avatar_id': avatarId,
        'current_stage_index': initialStage,
        'points_current': 0,
      });
      await _load();
      if (!mounted) return;
      setState(() {
        _unlocking = false;
        _showCodeModal = false;
        _selectedLetter = null;
        _codeController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alfamon låst op!')),
      );
    } catch (e, st) {
      debugPrint('KidAlfamonsScreen._unlock: $e\n$st');
      if (mounted) {
        setState(() {
          _unlocking = false;
          _error = _unlockFailureMessage(e);
        });
      }
    }
  }

  void _closeModal() {
    setState(() {
      _showCodeModal = false;
      _selectedLetter = null;
      _error = null;
      _unlocking = false;
      _codeController.clear();
    });
  }

  /// Én bogstavboks i gitteret (størrelse [cell] × [cell]).
  Widget _alfamonLetterBox(String letter, double cell) {
    final isUnlocked = _unlockedLetters.contains(letter);
    final alphamon = _unlockedAlphamons[letter];
    final isActive =
        alphamon != null && _activeAvatarId == alphamon.avatarId;
    final badge = math.max(7.0, cell * 0.22);
    final iconSz = math.max(10.0, cell * 0.28).clamp(10.0, 16.0);
    final rad = math.max(6.0, cell * 0.12);

    return SizedBox(
      width: cell,
      height: cell,
      child: GestureDetector(
        onTap: () => _onLetterTap(letter),
        onLongPress: isUnlocked && alphamon != null
            ? () => _setActiveAvatarForHome(alphamon.avatarId)
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: isUnlocked
                ? Colors.green.shade400
                : const Color(0xFFF9C433),
            borderRadius: BorderRadius.circular(rad),
            border: Border.all(
              color: isActive
                  ? Colors.amber
                  : (isUnlocked
                      ? Colors.green.shade600
                      : Colors.grey.shade300),
              width: isActive ? 3 : 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isUnlocked &&
                  alphamon?.imageUrl != null &&
                  alphamon!.imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(rad - 2),
                  child: AssetOrNetworkImage(
                    src: alphamon.imageUrl!,
                    fit: BoxFit.cover,
                  ),
                )
              else if (!isUnlocked)
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      letter.toUpperCase(),
                      style: TextStyle(
                        fontSize: math.min(cell * 0.55, 36),
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                )
              else
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      letter.toUpperCase(),
                      style: TextStyle(
                        fontSize: cell * 0.32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (isUnlocked)
                Positioned(
                  top: math.max(2.0, cell * 0.04),
                  left: math.max(2.0, cell * 0.04),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: math.max(3.0, cell * 0.06),
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      letter.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: badge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (isUnlocked)
                Positioned(
                  top: math.max(2.0, cell * 0.04),
                  right: math.max(2.0, cell * 0.04),
                  child: Container(
                    width: math.max(16.0, math.min(cell * 0.38, 24.0)),
                    height: math.max(16.0, math.min(cell * 0.38, 24.0)),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.amber : Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isActive ? Icons.star : Icons.check,
                      size: iconSz,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (isUnlocked &&
                  alphamon != null &&
                  alphamon.maxStage > 0)
                Positioned(
                  bottom: math.max(2.0, cell * 0.04),
                  left: 2,
                  right: 2,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: math.max(3.0, cell * 0.05),
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${alphamon.currentStage}/${alphamon.maxStage}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: math.max(6.0, cell * 0.14),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;
    const letterCount = 29;
    const gap = 5.0;
    const gridPad = 8.0;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/alfamonbaggrund.svg',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                  child: Text(
                    'Alfamons',
                    style: TextStyle(
                      fontSize: isTablet ? 24 : 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black54,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final maxW =
                                constraints.maxWidth - 2 * gridPad;
                            final maxH =
                                constraints.maxHeight - 2 * gridPad;
                            if (maxW <= 0 || maxH <= 0) {
                              return const SizedBox.shrink();
                            }

                            var bestCols = 6;
                            var bestCell = 0.0;
                            for (var c = 5; c <= 12; c++) {
                              final r = (letterCount + c - 1) ~/ c;
                              final sW = (maxW - (c - 1) * gap) / c;
                              final sH = (maxH - (r - 1) * gap) / r;
                              final s = math.min(sW, sH);
                              if (s > bestCell) {
                                bestCell = s;
                                bestCols = c;
                              }
                            }
                            final rows =
                                (letterCount + bestCols - 1) ~/ bestCols;
                            bestCell = bestCell.clamp(36.0, 120.0);
                            if (rows * bestCell + (rows - 1) * gap > maxH) {
                              bestCell = (maxH - (rows - 1) * gap) / rows;
                            }
                            if (bestCols * bestCell + (bestCols - 1) * gap >
                                maxW) {
                              bestCell =
                                  (maxW - (bestCols - 1) * gap) / bestCols;
                            }
                            bestCell = math.max(32.0, bestCell);
                            final cols = bestCols;
                            final letters = _danishAlphabet.split('');

                            return Padding(
                              padding: const EdgeInsets.all(gridPad),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(rows, (r) {
                                    final start = r * cols;
                                    final end = math.min(
                                      start + cols,
                                      letters.length,
                                    );
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom:
                                            r < rows - 1 ? gap : 0,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (var i = start;
                                              i < end;
                                              i++)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                right: i < end - 1
                                                    ? gap
                                                    : 0,
                                              ),
                                              child: _alfamonLetterBox(
                                                letters[i],
                                                bestCell,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: KidSessionNavButton(kidId: widget.kidId),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: const KidParentAdminCornerButton(),
          ),
          if (_showCodeModal && _selectedLetter != null) _buildCodeModal(),
        ],
      ),
    );
  }

  Widget _buildCodeModal() {
    return GestureDetector(
      onTap: _closeModal,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedLetter!.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lås Alfamon op!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Spørg en voksen om koden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      hintText: '4-cifret kode',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _closeModal,
                          child: const Text('Annuller'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              _unlocking || _codeController.text.length != 4
                              ? null
                              : _unlock,
                          child: Text(_unlocking ? 'Låser op...' : 'Lås op'),
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
    );
  }

}

class _AlfamonUpgradeSheet extends StatefulWidget {
  const _AlfamonUpgradeSheet({
    required this.kidId,
    required this.alphamon,
    required this.treasuryGold,
    required this.onTreasuryUpdated,
    required this.onReload,
  });

  final String kidId;
  final _UnlockedAlphamon alphamon;
  final int treasuryGold;
  final void Function(int newTreasury) onTreasuryUpdated;
  final Future<void> Function() onReload;

  @override
  State<_AlfamonUpgradeSheet> createState() => _AlfamonUpgradeSheetState();
}

class _AlfamonUpgradeSheetState extends State<_AlfamonUpgradeSheet> {
  /// Sidst synkroniserede kistesaldo (efter Godkend / ved åbning).
  late int _committedTreasury;

  /// Sidst synkroniserede point på Alfamon.
  late int _committedPoints;

  /// Forskel der anvendes ved Godkend: positiv = fra kiste til Alfamon, negativ = tilbage til kisten.
  int _pendingDelta = 0;
  bool _busy = false;
  String? _previewImageUrl;

  /// Sorterede [avatar_stages.stage_index] til billedvalg under pending ændring.
  List<int> _sortedStageIndices = const [];

  /// image_url pr. [stage_index] fra Supabase (æg m.m. — ikke kun bundt-assets).
  Map<int, String> _stageImageByIndex = {};

  int get _maxPositive => math.min(
    _committedTreasury,
    AlfamonEvolution.maxProgressPoints - _committedPoints,
  );
  int get _maxNegative => -_committedPoints;

  /// Forhåndsvisning af kiste efter det afventende træk.
  int get _previewTreasury => _committedTreasury - _pendingDelta;

  /// Forhåndsvisning af Alfamon-point (til bar/tekst).
  int get _previewPoints => (_committedPoints + _pendingDelta)
      .clamp(0, AlfamonEvolution.maxProgressPoints)
      .toInt();

  @override
  void initState() {
    super.initState();
    _committedTreasury = widget.treasuryGold;
    _committedPoints = widget.alphamon.pointsInvested;
    _previewImageUrl = widget.alphamon.imageUrl;
    _loadSortedStageIndices();
  }

  Future<void> _loadSortedStageIndices() async {
    final res = await Supabase.instance.client
        .from('avatar_stages')
        .select('stage_index,image_url')
        .eq('avatar_id', widget.alphamon.avatarId)
        .order('stage_index');
    if (!mounted) return;
    final list = res as List;
    final sorted = AlfamonEvolution.sortedStageIndicesFromRows(list);
    final byIndex = <int, String>{};
    for (final row in list) {
      final m = row as Map;
      final si = m['stage_index'] as int;
      final url = (m['image_url'] as String? ?? '').trim();
      if (url.isNotEmpty) byIndex[si] = url;
    }
    setState(() {
      _sortedStageIndices = sorted;
      _stageImageByIndex = byIndex;
      _previewImageUrl = _resolveImageUrl(_committedPoints + _pendingDelta, sorted);
    });
  }

  String? _resolveImageUrl(int points, List<int> sorted) {
    if (sorted.isEmpty) {
      return _previewImageUrl ?? widget.alphamon.imageUrl;
    }
    final idx = AlfamonEvolution.stageIndexFromPoints(points, sorted);
    final fromDb = _stageImageByIndex[idx];
    if (fromDb != null && fromDb.isNotEmpty) return fromDb;
    final paths = CardAssets.getCardImagePathsToTry(
      widget.alphamon.name,
      idx,
      letter: widget.alphamon.letter,
    );
    if (paths.isNotEmpty) return paths.first;
    return _previewImageUrl;
  }

  Future<void> _refreshPreviewAfterTransfer() async {
    final client = Supabase.instance.client;
    final lib = await client
        .from('kid_avatar_library')
        .select('points_current')
        .eq('kid_id', widget.kidId)
        .eq('avatar_id', widget.alphamon.avatarId)
        .maybeSingle();
    final points = (lib?['points_current'] as num?)?.toInt() ?? 0;
    final stagesRes = await client
        .from('avatar_stages')
        .select('stage_index,image_url')
        .eq('avatar_id', widget.alphamon.avatarId)
        .order('stage_index');
    final list = stagesRes as List;
    final sorted = AlfamonEvolution.sortedStageIndicesFromRows(list);
    final byIndex = <int, String>{};
    for (final row in list) {
      final m = row as Map;
      final si = m['stage_index'] as int;
      final url = (m['image_url'] as String? ?? '').trim();
      if (url.isNotEmpty) byIndex[si] = url;
    }
    if (mounted) {
      setState(() {
        _committedPoints = points;
        _sortedStageIndices = sorted;
        _stageImageByIndex = byIndex;
        _previewImageUrl = _resolveImageUrl(points, sorted);
      });
    }
  }

  void _bumpDelta(int step) {
    if (_busy) return;
    final lo = _maxNegative;
    final hi = _maxPositive;
    final next = (_pendingDelta + step).clamp(lo, hi).toInt();
    if (next == _pendingDelta) return;
    setState(() => _pendingDelta = next);
  }

  Future<void> _openAmountEditor() async {
    if (_busy) return;
    final controller = TextEditingController(text: '$_pendingDelta');
    int? parsed;
    try {
      parsed = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Antal guldmønter'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d{0,4}')),
            ],
            decoration: const InputDecoration(
              hintText: 'Fx 5 eller -2',
              helperText:
                  'Positivt: fra kisten til Alfamon. Negativt: tilbage til kisten.',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuller'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Indtast et heltal')),
                  );
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    final value = parsed;
    if (value == null || !mounted) return;
    setState(() {
      _pendingDelta = value.clamp(_maxNegative, _maxPositive).toInt();
    });
  }

  Future<void> _onApprove() async {
    if (_busy || _pendingDelta == 0) return;
    setState(() => _busy = true);
    final d = _pendingDelta;
    try {
      if (d > 0) {
        await TaskCompletionService.transferGoldToAlfamon(
          kidId: widget.kidId,
          avatarId: widget.alphamon.avatarId,
          amount: d,
        );
      } else {
        await TaskCompletionService.transferGoldFromAlfamon(
          kidId: widget.kidId,
          avatarId: widget.alphamon.avatarId,
          amount: -d,
        );
      }
      if (!mounted) return;
      final newTreasury = _committedTreasury - d;
      setState(() {
        _committedTreasury = newTreasury;
        _pendingDelta = 0;
        _busy = false;
      });
      widget.onTreasuryUpdated(newTreasury);
      await widget.onReload();
      await _refreshPreviewAfterTransfer();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _roundGoldButton({
    required IconData icon,
    required VoidCallback? onTap,
    List<Color>? gradientColors,
    double size = 64,
    double iconSize = 40,
  }) {
    final colors =
        gradientColors ??
        const [Color(0xFFFFE082), Color(0xFFF9C433), Color(0xFFE6A000)];
    final enabled = onTap != null && !_busy;
    return Material(
      elevation: 6,
      shadowColor: const Color(0xFFF9C433).withValues(alpha: 0.6),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: enabled ? Colors.black87 : Colors.black26,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = _resolveImageUrl(_previewPoints, _sortedStageIndices);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: Center(
              child: url != null && url.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AssetOrNetworkImage(
                        key: ValueKey(url),
                        src: url,
                        fit: BoxFit.contain,
                        height: 240,
                      ),
                    )
                  : Icon(
                      Icons.pets,
                      size: 120,
                      color: theme.colorScheme.primary,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          AlfamonEvolutionProgressBar(points: _previewPoints),
          const SizedBox(height: 8),
          Text(
            '$_previewPoints / ${AlfamonEvolution.maxProgressPoints} guldmønter på Alfamon',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: _busy ? 0.45 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/moent.webp',
                    width: 52,
                    height: 52,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.monetization_on,
                      size: 52,
                      color: const Color(0xFFF9C433),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 76,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$_previewTreasury',
                        maxLines: 1,
                        style:
                            theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 44,
                              height: 1,
                              color: theme.colorScheme.onSurface,
                            ) ??
                            const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _roundGoldButton(
                    icon: Icons.remove,
                    onTap: _busy ? null : () => _bumpDelta(-1),
                    gradientColors: const [
                      Color(0xFFFFCDD2),
                      Color(0xFFE57373),
                      Color(0xFFC62828),
                    ],
                    size: 60,
                    iconSize: 36,
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.85,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _busy ? null : _openAmountEditor,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 52),
                          child: Text(
                            '$_pendingDelta',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 36,
                              height: 1,
                              color: _pendingDelta == 0
                                  ? theme.colorScheme.onSurface.withValues(
                                      alpha: 0.45,
                                    )
                                  : const Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _roundGoldButton(
                    icon: Icons.add,
                    onTap: _busy ? null : () => _bumpDelta(1),
                    size: 60,
                    iconSize: 36,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Tooltip(
              message: 'Godkend',
              child: Material(
                elevation: _pendingDelta == 0 || _busy ? 0 : 10,
                shadowColor: Colors.black38,
                color: _pendingDelta == 0 || _busy
                    ? theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      )
                    : const Color(0xFFF2F0EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: InkWell(
                  onTap: _pendingDelta == 0 || _busy ? null : _onApprove,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _busy
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Icon(
                            Icons.check_rounded,
                            size: 36,
                            color: _pendingDelta == 0
                                ? theme.colorScheme.onSurface.withValues(
                                    alpha: 0.25,
                                  )
                                : Colors.black,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
