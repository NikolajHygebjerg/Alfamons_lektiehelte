import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/angreb_assets.dart';
import '../../utils/card_assets.dart';
import '../../widgets/duel_angreb_tile.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/alfamon_card.dart';
import 'widgets/kid_session_nav_button.dart';

/// Angreb-billeder: true = de kigger til højre i originalen. false = de kigger til venstre.
/// Skift denne hvis figurerne vender forkert – eller tilret alle billeder til at kigge højre.
/// Angreb-PNG'er vender mod højre i filen; spiller vises uden flip, modstander spejlvendes.
const bool _angrebImagesFaceRight = true;

class _GameCard {
  final String id;
  final String avatarId;
  final String name;
  final String? letter;
  final String imageUrl;
  final int stageIndex;
  final List<_Strength> strengths;

  _GameCard({
    required this.id,
    required this.avatarId,
    required this.name,
    this.letter,
    required this.imageUrl,
    required this.stageIndex,
    required this.strengths,
  });

  AlfamonCardData toAlfamonCardData() => AlfamonCardData(
        name: name,
        letter: letter,
        imageUrl: imageUrl,
        assetPath: CardAssets.getCardAssetPath(name, stageIndex, letter: letter),
        strengths: strengths
            .map((s) => AlfamonStrength(
                  strengthIndex: s.strengthIndex,
                  name: s.name,
                  value: s.value,
                ))
            .toList(),
      );
}

int _parseStrengthValue(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v.clamp(0, 100);
  if (v is num) return v.round().clamp(0, 100);
  return int.tryParse(v.toString()) ?? 0;
}

class _Strength {
  final int strengthIndex;
  final String name;
  final int value;

  _Strength({
    required this.strengthIndex,
    required this.name,
    required this.value,
  });
}

class KidSpilScreen extends StatefulWidget {
  final String kidId;
  final String? computerMatchId;

  const KidSpilScreen({super.key, required this.kidId, this.computerMatchId});

  @override
  State<KidSpilScreen> createState() => _KidSpilScreenState();
}

class _KidSpilScreenState extends State<KidSpilScreen> {
  List<_GameCard> _kidCards = [];
  List<_GameCard> _computerCards = [];
  bool _loading = true;
  String _gameState = 'idle'; // idle, choosing_strength, round_result, game_over
  _GameCard? _kidCard;
  _GameCard? _computerCard;
  int? _selectedStrengthIndex;
  int _kidScore = 0;
  int _computerScore = 0;
  String? _roundWinner; // 'kid', 'computer', 'tie'
  String? _previousRoundWinner; // Hvem vandt forrige runde – bestemmer hvem der vælger evne
  int _roundNumber = 0;
  bool _barometersReady = false; // Barometre starter først efter lyd 3-5 færdige
  bool _gameWinRecorded = false;
  _GameCard? _gameOverStrongestCard; // Stærkeste alfamon til game over-skærm
  bool _gameOverKidWon = false;
  String? _computerMatchId; // Gemt match-id for persistence

  final _random = Random();
  late final AudioPlayer _audioPlayer;

  Future<void> _safeSaveMatchState() async {
    try {
      await _saveComputerMatchState().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _safeCompleteMatch() async {
    try {
      await _completeComputerMatch().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _audioPlayer.audioCache.prefix = '';
    _initAudio();
    _loadCards();
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ));
    } catch (e) {
      if (kDebugMode) debugPrint('Audio init: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  static const _vaelgevne = 'Vaelgevne.mp3';
  static const _modstandervaelgerevne = 'Modstandervaelgerevne.mp3';
  static const _duvinder = 'Duvinder.mp3';
  static const _modstanderenvinder = 'Modstanderenvinder.mp3';
  static const _rising = 'rising.mp3';

  /// Asset path – bruger standard assets/ prefix.
  String _assetPath(String file) => 'assets/$file';

  /// 1–2: Afspiller evne-valg-lyd (dig eller modstander).
  Future<void> _playAbilityChoiceSound(bool kidChooses) async {
    try {
      await _audioPlayer.stop();
      final file = kidChooses ? _vaelgevne : _modstandervaelgerevne;
      final path = _assetPath(file);
      _audioPlayer.play(AssetSource(path));
      try {
        await _audioPlayer.onPlayerComplete.first
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // Fortsæt flowet hvis completion-event mangler.
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PlayAbilityChoice: $e');
    }
  }


  void _playRisingSound() {
    _audioPlayer.play(AssetSource(_assetPath(_rising)));
  }

  void _stopRisingSound() {
    _audioPlayer.stop();
  }

  /// Afspiller vinder/taber-lyd (Duvinder / Modstanderenvinder).
  void _playRoundResultSound(String winner) {
    if (winner == 'tie') return;
    final file = winner == 'kid' ? _duvinder : _modstanderenvinder;
    _audioPlayer.stop();
    _audioPlayer.play(AssetSource(_assetPath(file)));
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);

    final client = Supabase.instance.client;

    final unlockedRes = await client
        .from('kid_unlocked_alphamons')
        .select('avatar_id')
        .eq('kid_id', widget.kidId);
    final unlockedIds = (unlockedRes as List)
        .map((e) => e['avatar_id'] as String)
        .toSet()
        .toList();

    if (unlockedIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _kidCards = [];
        _loading = false;
      });
      return;
    }

    final cards = await _loadCardsForAvatars(client, unlockedIds, widget.kidId);

    final shuffled = List<_GameCard>.from(cards)..shuffle(_random);

    if (!mounted) return;

    if (widget.computerMatchId != null) {
      final res = await Supabase.instance.client
          .from('kid_computer_matches')
          .select('game_state')
          .eq('id', widget.computerMatchId!)
          .eq('kid_id', widget.kidId)
          .eq('status', 'in_progress')
          .maybeSingle();
      if (res != null && mounted) {
        setState(() => _computerMatchId = widget.computerMatchId);
        final state = res['game_state'] as Map<String, dynamic>?;
        if (state != null && state.isNotEmpty) {
          _restoreFromState(state, shuffled);
          return;
        }
      }
    }

    setState(() {
      _kidCards = shuffled;
      _computerCards = List<_GameCard>.from(shuffled)
        ..shuffle(_random);
      _loading = false;
    });

    if (widget.computerMatchId == null && mounted) {
      _createComputerMatch();
    }
  }

  void _restoreFromState(Map<String, dynamic> state, List<_GameCard> allCards) {
    // Forenklet gendannelse – fuld persistence kræver kort-serialisering
    final kidScore = state['kidScore'] as int? ?? 0;
    final computerScore = state['computerScore'] as int? ?? 0;
    final roundNumber = state['roundNumber'] as int? ?? 0;
    setState(() {
      _kidCards = List<_GameCard>.from(allCards)..shuffle(_random);
      _computerCards = List<_GameCard>.from(allCards)..shuffle(_random);
      _kidScore = kidScore;
      _computerScore = computerScore;
      _roundNumber = roundNumber;
      _loading = false;
    });
  }

  Future<void> _createComputerMatch() async {
    try {
      final res = await Supabase.instance.client
          .from('kid_computer_matches')
          .insert({
            'kid_id': widget.kidId,
            'status': 'in_progress',
            'game_state': {},
          })
          .select('id')
          .single();
      if (mounted) setState(() => _computerMatchId = res['id'] as String?);
    } catch (e) {
      if (mounted && kDebugMode) debugPrint('_createComputerMatch: $e');
    }
  }

  Future<void> _saveComputerMatchState() async {
    final id = _computerMatchId ?? widget.computerMatchId;
    if (id == null) return;
    await Supabase.instance.client
        .from('kid_computer_matches')
        .update({
          'game_state': {
            'kidScore': _kidScore,
            'computerScore': _computerScore,
            'roundNumber': _roundNumber,
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('kid_id', widget.kidId);
  }

  Future<void> _completeComputerMatch() async {
    try {
      // Luk ALLE igangværende computerspil for barnet for at undgå gamle/stale
      // in_progress-rækker, der ellers kan få spillet til at se "ikke afsluttet" ud.
      await Supabase.instance.client
          .from('kid_computer_matches')
          .update({
            'status': 'completed',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('kid_id', widget.kidId)
          .eq('status', 'in_progress');
      if (mounted) {
        setState(() => _computerMatchId = null);
      }
    } catch (e) {
      if (mounted) {
        if (kDebugMode) debugPrint('_completeComputerMatch: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke afslutte: $e')),
        );
      }
    }
  }

  Future<List<_GameCard>> _loadCardsForAvatars(
    SupabaseClient client,
    List<String> avatarIds,
    String kidId,
  ) async {
    final cards = <_GameCard>[];

    final libRes = await client
        .from('kid_avatar_library')
        .select('id,avatar_id,current_stage_index,avatars(name,letter)')
        .eq('kid_id', kidId)
        .inFilter('avatar_id', avatarIds);

    final libraryRows = (libRes as List)
        .where((r) => (r['current_stage_index'] as int? ?? 0) > 0)
        .toList();

    for (final row in libraryRows) {
      final avatarId = row['avatar_id'] as String;
      final stageIndex = row['current_stage_index'] as int;
      final av = row['avatars'];
      final name = (av is Map ? av['name'] : null) as String? ?? 'Alfamon';
      final letter = (av is Map ? av['letter'] : null) as String?;

      final stageRes = await client
          .from('avatar_stages')
          .select('image_url')
          .eq('avatar_id', avatarId)
          .eq('stage_index', stageIndex)
          .maybeSingle();

      final strengthRes = await client
          .from('avatar_strengths')
          .select('strength_index,name,value')
          .eq('avatar_id', avatarId)
          .eq('stage_index', stageIndex)
          .order('strength_index');

      final imageUrl = stageRes?['image_url'] as String?;
      final strengths = (strengthRes as List)
          .map((s) => _Strength(
                strengthIndex: s['strength_index'] as int,
                name: s['name'] as String? ?? '',
                value: _parseStrengthValue(s['value']),
              ))
          .toList();

      if (imageUrl != null && imageUrl.isNotEmpty && strengths.isNotEmpty) {
        cards.add(_GameCard(
          id: 'kid-${row['id']}-${cards.length}',
          avatarId: avatarId,
          name: name,
          letter: letter,
          imageUrl: imageUrl,
          stageIndex: stageIndex,
          strengths: strengths,
        ));
      }
    }

    final historyRes = await client
        .from('kid_avatar_history')
        .select('id,avatar_id,avatars(name,letter)')
        .eq('kid_id', kidId)
        .inFilter('avatar_id', avatarIds)
        .order('finished_at', ascending: false);

    final historyAvatarIds = (historyRes as List)
        .map((r) => r['avatar_id'] as String)
        .toSet();

    for (final row in historyRes) {
      final avatarId = row['avatar_id'] as String;
      if (cards.any((c) => c.avatarId == avatarId)) continue;

      final av = row['avatars'];
      final name = (av is Map ? av['name'] : null) as String? ?? 'Alfamon';
      final letter = (av is Map ? av['letter'] : null) as String?;

      final stageRes = await client
          .from('avatar_stages')
          .select('stage_index')
          .eq('avatar_id', avatarId)
          .order('stage_index', ascending: false)
          .limit(1);

      final maxStage = (stageRes as List).isNotEmpty
          ? (stageRes.first['stage_index'] as int)
          : 0;

      if (maxStage <= 0) continue;

      final stageData = await client
          .from('avatar_stages')
          .select('image_url')
          .eq('avatar_id', avatarId)
          .eq('stage_index', maxStage)
          .maybeSingle();

      final strengthRes = await client
          .from('avatar_strengths')
          .select('strength_index,name,value')
          .eq('avatar_id', avatarId)
          .eq('stage_index', maxStage)
          .order('strength_index');

      final imageUrl = stageData?['image_url'] as String?;
      final strengths = (strengthRes as List)
          .map((s) => _Strength(
                strengthIndex: s['strength_index'] as int,
                name: s['name'] as String? ?? '',
                value: _parseStrengthValue(s['value']),
              ))
          .toList();

      if (imageUrl != null && imageUrl.isNotEmpty && strengths.isNotEmpty) {
        cards.add(_GameCard(
          id: 'kid-hist-${row['id']}-${cards.length}',
          avatarId: avatarId,
          name: name,
          letter: letter,
          imageUrl: imageUrl,
          stageIndex: maxStage,
          strengths: strengths,
        ));
      }
    }

    return cards;
  }

  void _startGame() {
    if (_kidCards.isEmpty || _computerCards.isEmpty) return;

    setState(() {
      _gameOverStrongestCard = null;
      _gameOverKidWon = false;
      _gameState = 'idle';
      _roundNumber = 1;
      _kidScore = 0;
      _computerScore = 0;
      _kidCard = null;
      _computerCard = null;
      _selectedStrengthIndex = null;
      _roundWinner = null;
      _previousRoundWinner = null;
      _gameWinRecorded = false;
    });
  }

  Future<void> _resetAndStartNewGame() async {
    setState(() => _loading = true);
    await _loadCards();
    if (!mounted) return;
    if (_kidCards.isEmpty || _computerCards.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _startGame();
    setState(() => _loading = false);
  }

  _GameCard? _getStrongestCard(List<_GameCard> cards) {
    if (cards.isEmpty) return null;
    return cards.reduce((a, b) {
      if (a.stageIndex != b.stageIndex) return a.stageIndex > b.stageIndex ? a : b;
      final maxA = a.strengths.isEmpty ? 0 : a.strengths.map((s) => s.value).reduce((x, y) => x > y ? x : y);
      final maxB = b.strengths.isEmpty ? 0 : b.strengths.map((s) => s.value).reduce((x, y) => x > y ? x : y);
      return maxA >= maxB ? a : b;
    });
  }

  void _kidPlayCard({int? cardIndex}) {
    if (_gameState != 'idle' || _kidCards.isEmpty) return;
    if (_computerCards.isEmpty) {
      _endGame();
      return;
    }

    final index = cardIndex ?? 0;
    if (index < 0 || index >= _kidCards.length) return;

    final card = _kidCards[index];
    final compCard = _computerCards.first;

    final kidChooses = _previousRoundWinner == null || _previousRoundWinner == 'kid' || _previousRoundWinner == 'tie';

    if (kidChooses) {
      setState(() {
        _kidCards.removeAt(index);
        _computerCards.removeAt(0);
        _kidCard = card;
        _computerCard = compCard;
        _gameState = 'choosing_strength';
      });
      _playAbilityChoiceSound(true);
    } else {
      // Modstanderen vandt forrige runde – de bestemmer evnen. Vælger altid stærkeste evne.
      final compStrengths = compCard.strengths;
      final strongest = compStrengths.isNotEmpty
          ? compStrengths.reduce((a, b) => a.value >= b.value ? a : b)
          : null;
      final compStrengthIndex = strongest?.strengthIndex ?? 0;

      setState(() {
        _kidCards.removeAt(index);
        _computerCards.removeAt(0);
        _kidCard = card;
        _computerCard = compCard;
        _selectedStrengthIndex = compStrengthIndex;
        _gameState = 'round_result';
        _barometersReady = false;
      });
      _playAbilityChoiceSound(false).then((_) {
        if (mounted) setState(() => _barometersReady = true);
      });
    }
  }

  void _selectStrength(int index) {
    if (_gameState != 'choosing_strength' || _kidCard == null || _computerCard == null) return;

    setState(() {
      _selectedStrengthIndex = index;
      _gameState = 'round_result';
      _barometersReady = true;
    });
  }

  void _resolveRound(_GameCard compCard, int strengthIndex) {
    final kidCard = _kidCard!;
    final kidStrength = kidCard.strengths
        .where((s) => s.strengthIndex == strengthIndex)
        .firstOrNull;
    final compStrength = compCard.strengths
        .where((s) => s.strengthIndex == strengthIndex)
        .firstOrNull;

    final kidVal = kidStrength?.value ?? 0;
    final compVal = compStrength?.value ?? 0;

    String winner;
    if (kidVal > compVal) {
      winner = 'kid';
    } else if (compVal > kidVal) {
      winner = 'computer';
    } else {
      winner = 'tie';
    }

    setState(() => _roundWinner = winner);
    _playRoundResultSound(winner);
  }

  void _applyRoundResult(String winner, _GameCard compCard) {
    final kidCard = _kidCard!;

    if (winner == 'kid') {
      // Vundet: mit vinderkort + modstanderens taberkort nederst i min bunke
      setState(() {
        _kidScore++;
        _kidCards.add(kidCard);
        _kidCards.add(_GameCard(
          id: 'kid-${DateTime.now().millisecondsSinceEpoch}-${compCard.avatarId}',
          avatarId: compCard.avatarId,
          name: compCard.name,
          letter: compCard.letter,
          imageUrl: compCard.imageUrl,
          stageIndex: compCard.stageIndex,
          strengths: compCard.strengths,
        ));
      });
    } else if (winner == 'computer') {
      // Tabt: mister mit kort til modstanderen. Modstanderens kort går tilbage i deres bunke.
      setState(() {
        _computerScore++;
        _computerCards.add(_GameCard(
          id: 'comp-${DateTime.now().millisecondsSinceEpoch}-${kidCard.avatarId}',
          avatarId: kidCard.avatarId,
          name: kidCard.name,
          letter: kidCard.letter,
          imageUrl: kidCard.imageUrl,
          stageIndex: kidCard.stageIndex,
          strengths: kidCard.strengths,
        ));
        _computerCards.add(compCard);
      });
    } else {
      // Uafgjort: begge kort går tilbage i deres egne bunker
      setState(() {
        _kidCards.add(kidCard);
        _computerCards.add(compCard);
      });
    }

    if (_kidCards.isEmpty || _computerCards.isEmpty) {
      _endGame();
      return;
    }

    setState(() {
      _roundNumber++;
      _previousRoundWinner = winner == 'tie' ? 'kid' : winner;
      _kidCard = null;
      _computerCard = null;
      _selectedStrengthIndex = null;
      _roundWinner = null;
      _gameState = 'idle';
      _barometersReady = false;
    });

    // Træk næste kort automatisk – kun når bunken bestemmer (> 3 kort)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _kidCards.isNotEmpty && _computerCards.isNotEmpty && _kidCards.length > 3) {
        _kidPlayCard();
      }
    });
  }

  void _endGame() {
    final kidWon = _kidCards.isNotEmpty;
    final strongest = kidWon
        ? _getStrongestCard(_kidCards)
        : _getStrongestCard(_computerCards);

    setState(() {
      _gameState = 'game_over';
      _gameOverStrongestCard = strongest;
      _gameOverKidWon = kidWon;
    });

    _completeComputerMatch();

    if (kidWon && !_gameWinRecorded) {
      _gameWinRecorded = true;
      Supabase.instance.client.from('game_wins').insert({
        'kid_id': widget.kidId,
        'metadata': {
          'kid_score': _kidScore,
          'computer_score': _computerScore,
          'rounds': _roundNumber,
        },
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;
    final bgAsset = isTablet
        ? 'assets/baggrund_roedipad.svg'
        : 'assets/baggrund_roediphone.svg';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(bgAsset, fit: BoxFit.cover),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      KidSessionNavButton(
                        kidId: widget.kidId,
                        fallbackLocation: '/kid/spil/${widget.kidId}',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () async {
                          final router = GoRouter.of(context);
                          final doIt = await showDialog<bool>(
                            context: context,
                            useRootNavigator: true,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Afslut spil?'),
                              content: const Text(
                                'Vil du afslutte spillet mod computeren?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Annuller'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Afslut'),
                                ),
                              ],
                            ),
                          );
                          if (doIt != true || !context.mounted) return;
                          unawaited(_safeSaveMatchState());
                          unawaited(_safeCompleteMatch());
                          router.go('/kid/spil/${widget.kidId}');
                        },
                        tooltip: 'Afslut',
                      ),
                      Expanded(
                        child: Text(
                          'Spil mod computer',
                          style: TextStyle(
                            fontSize: isTablet ? 28 : 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const KidParentAdminCornerButton(),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : _gameState == 'game_over'
                          ? _buildGameOver()
                          : _kidCards.isEmpty
                              ? _buildNoCards()
                              : _buildGame(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoCards() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎴', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'Ingen kort endnu',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Færdiggør opgaver for at opgradere din avatar og låse kort op til spillet!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOver() {
    final kidWon = _gameOverKidWon;
    final strongest = _gameOverStrongestCard;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (strongest != null) ...[
            _GameOverAlfamon(
              card: strongest,
              message: kidWon ? 'Du vandt!' : 'Du tabte!',
              kidWon: kidWon,
            ),
            const SizedBox(height: 24),
          ] else ...[
            Text(
              kidWon ? 'Du vandt!' : 'Du tabte!',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            '$_kidScore - $_computerScore',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _resetAndStartNewGame,
            icon: const Icon(Icons.refresh),
            label: const Text('Ny kamp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF9C433),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGame() {
    if (_gameState == 'idle' && _kidCard == null) {
      return _buildIdleLayout();
    }
    if (_gameState == 'choosing_strength') {
      return _buildChoosingLayout();
    }
    return _buildDuelLayout();
  }

  /// Når man spiller kort: vis kortet og evnerne man kan vælge.
  Widget _buildChoosingLayout() {
    final kidCard = _kidCard!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ScoreCard(label: 'Dig', score: _kidScore),
              Text(
                'Runde $_roundNumber',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              _ScoreCard(label: 'Computer', score: _computerScore),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: AlfamonCard(
              card: kidCard.toAlfamonCardData(),
              width: _gameCardWidth,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Vælg styrke',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          StrengthChoiceGrid(
            strengths: kidCard.strengths
                .map((s) => AlfamonStrength(
                      strengthIndex: s.strengthIndex,
                      name: s.name,
                      value: s.value,
                    ))
                .toList(),
            onSelect: _selectStrength,
          ),
        ],
      ),
    );
  }

  /// Efter valg af evne: kort i venstre hjørne, angreb-figurer peger mod hinanden.
  Widget _buildDuelLayout() {
    final kidCard = _kidCard!;
    final computerCard = _computerCard!;
    final selectedStrength = _selectedStrengthIndex != null
        ? kidCard.strengths
            .where((s) => s.strengthIndex == _selectedStrengthIndex)
            .firstOrNull
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ScoreCard(label: 'Dig', score: _kidScore),
                  Text(
                    'Runde $_roundNumber',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  _ScoreCard(label: 'Computer', score: _computerScore),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DuelAngrebTile(
                        name: kidCard.name,
                        stageIndex: kidCard.stageIndex,
                        letter: kidCard.letter,
                        faceRight: _angrebImagesFaceRight,
                        strengthName: selectedStrength?.name,
                        powerValue: selectedStrength?.value ?? 0,
                        barometerOnRight: true,
                        animationDelayMs: 0,
                        barometersReady: _barometersReady,
                        onBarometerStart: _playRisingSound,
                        onBarometerComplete: _stopRisingSound,
                      ),
                    ),
                    Expanded(
                      child: DuelAngrebTile(
                        name: computerCard.name,
                        stageIndex: computerCard.stageIndex,
                        letter: computerCard.letter,
                        faceRight: !_angrebImagesFaceRight,
                        strengthName: selectedStrength?.name,
                        powerValue: computerCard.strengths
                            .where((s) => s.strengthIndex == _selectedStrengthIndex)
                            .firstOrNull?.value ?? 0,
                        barometerOnRight: false,
                        animationDelayMs: 1200,
                        barometersReady: _barometersReady,
                        onBarometerStart: _playRisingSound,
                        onBarometerComplete: () {
                          _stopRisingSound();
                          if (_computerCard != null && _selectedStrengthIndex != null) {
                            _resolveRound(_computerCard!, _selectedStrengthIndex!);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_roundWinner != null) ...[
                const SizedBox(height: 12),
                Text(
                  _roundWinner == 'kid'
                      ? '✓ Du vandt runden!'
                      : _roundWinner == 'computer'
                          ? '✗ Computeren vandt'
                          : 'Uafgjort',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _roundWinner == 'kid'
                        ? Colors.green
                        : _roundWinner == 'computer'
                            ? Colors.red
                            : Colors.amber,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _applyRoundResult(_roundWinner!, _computerCard!),
                  icon: const Icon(Icons.sports_martial_arts),
                  label: const Text('Næste kamp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF9C433),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        Positioned(
          bottom: 16,
          left: 8,
          child: AlfamonCard(
            card: kidCard.toAlfamonCardData(),
            selectedStrengthIndex: _selectedStrengthIndex,
            isWinner: _roundWinner == 'kid',
            width: _gameCardWidth,
          ),
        ),
        if (_roundWinner == 'kid')
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: Center(child: _buildWinnerSplash()),
          ),
        if (_roundWinner == 'computer')
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: Center(child: _buildWinnerSplash()),
          ),
      ],
    );
  }

  Widget _buildWinnerSplash() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9C433).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          'VINDER',
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 4,
            shadows: [
              Shadow(color: Colors.black54, offset: const Offset(2, 2), blurRadius: 4),
              Shadow(color: Colors.black38, offset: const Offset(-1, -1), blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }

  static const double _gameCardWidth = 103.5; // Samme format i bunke og i spil
  static const String _danishAlphabet = 'abcdefghijklmnopqrstuvwxyzæøå';

  /// Sorterer kort efter bogstav (a-å)
  List<_GameCard> _cardsSortedByLetter(List<_GameCard> cards) {
    final sorted = List<_GameCard>.from(cards);
    sorted.sort((a, b) {
      final letterA = (a.letter ?? '').toLowerCase();
      final letterB = (b.letter ?? '').toLowerCase();
      final idxA = letterA.isEmpty ? 999 : _danishAlphabet.indexOf(letterA);
      final idxB = letterB.isEmpty ? 999 : _danishAlphabet.indexOf(letterB);
      return idxA.compareTo(idxB);
    });
    return sorted;
  }

  /// Viser kort forstørret i dialog så man kan se evner osv.
  void _showCardDetail(_GameCard card) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Center(
              child: AlfamonCard(
                card: card.toAlfamonCardData(),
                width: 220,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Før start: vis alle kort i rækkefølge a-å (undtagen æg)
  Widget _buildCardPreview() {
    final sorted = _cardsSortedByLetter(_kidCards);
    if (sorted.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Dine kort i spil',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: sorted.map((c) => GestureDetector(
              onTap: () => _showCardDetail(c),
              child: AlfamonCard(
                card: c.toAlfamonCardData(),
                width: _gameCardWidth,
              ),
            )).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _startGame,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start spil'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF9C433),
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_kidCards.length} kort lægges i bunken',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdleLayout() {
    const stackOffset = 4.0;

    // Før start: vis alle kort i rækkefølge a-å
    if (_roundNumber == 0) {
      return _buildCardPreview();
    }

    // 3 eller færre kort: vis alle midt på skærmen, vælg hvilket kort man vil spille
    if (_kidCards.length <= 3) {
      return _buildCardChoiceLayout();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ScoreCard(label: 'Dig', score: _kidScore),
                Text(
                  'Runde $_roundNumber',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                _ScoreCard(label: 'Computer', score: _computerScore),
              ],
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: _gameCardWidth + 20,
                child: _buildOpponentPile(_gameCardWidth, stackOffset),
              ),
            ),
          ),
          Positioned(
            top: 56,
            right: 8,
            child: Text(
              '${_computerCards.length} kort',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            child: _buildPlayerPile(_gameCardWidth, stackOffset),
          ),
          Positioned(
            bottom: 92,
            left: 0,
            child: Text(
              '${_kidCards.length} kort',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: _kidPlayCard,
                  icon: const Icon(Icons.card_giftcard),
                  label: const Text('Spil kort'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF9C433),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Når 3 eller færre kort: vis alle midt på skærmen, vælg hvilket kort at spille.
  Widget _buildCardChoiceLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ScoreCard(label: 'Dig', score: _kidScore),
                Text(
                  'Runde $_roundNumber',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                _ScoreCard(label: 'Computer', score: _computerScore),
              ],
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: _gameCardWidth + 20,
                child: _buildOpponentPile(_gameCardWidth, 4.0),
              ),
            ),
          ),
          Positioned(
            top: 56,
            right: 8,
            child: Text(
              '${_computerCards.length} kort',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Vælg et kort at spille',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _kidCards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _kidPlayCard(cardIndex: i),
                        child: AlfamonCard(
                          card: _kidCards[i].toAlfamonCardData(),
                          width: _gameCardWidth,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerPile(double cardWidth, double stackOffset) {
    if (_kidCards.isEmpty) return const SizedBox.shrink();
    final topCard = _kidCards.first;
    final count = _kidCards.length;
    final stackCount = count.clamp(1, 12);
    final offset = count > 8 ? 3.0 : stackOffset;

    return SizedBox(
      width: cardWidth + (stackCount - 1) * offset + 8,
      height: AlfamonCard.heightForWidth(cardWidth) + (stackCount - 1) * offset + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = stackCount - 1; i >= 1; i--)
            Positioned(
              left: i * offset,
              top: i * offset,
              child: AlfamonCardBack(width: cardWidth),
            ),
          Positioned(
            left: 0,
            top: 0,
            child: AlfamonCard(
              card: topCard.toAlfamonCardData(),
              width: cardWidth,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentPile(double cardWidth, double stackOffset) {
    final count = _computerCards.length;
    if (count == 0) return const SizedBox.shrink();
    final stackCount = count.clamp(1, 12);
    final offset = count > 8 ? 3.0 : stackOffset;

    return SizedBox(
      width: cardWidth + (stackCount - 1) * offset + 8,
      height: AlfamonCard.heightForWidth(cardWidth) + (stackCount - 1) * offset + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < stackCount; i++)
            Positioned(
              left: i * offset,
              top: i * offset,
              child: AlfamonCardBack(width: cardWidth),
            ),
        ],
      ),
    );
  }

}

/// Viser stærkeste alfamon med taleboble (Du vandt / Du tabte).
class _GameOverAlfamon extends StatelessWidget {
  final _GameCard card;
  final String message;
  final bool kidWon;

  const _GameOverAlfamon({
    required this.card,
    required this.message,
    required this.kidWon,
  });

  @override
  Widget build(BuildContext context) {
    final path = AngrebAssets.getAngrebAssetPath(
      card.name,
      card.stageIndex,
      letter: card.letter,
    );
    final bubbleColor = kidWon
        ? const Color(0xFF2E7D32).withValues(alpha: 0.95)
        : const Color(0xFFC62828).withValues(alpha: 0.95);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -10,
              child: Center(
                child: CustomPaint(
                  size: const Size(24, 14),
                  painter: _BubbleTailPainter(color: bubbleColor),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 180,
          height: 180,
          child: path != null
              ? Image.asset(path, fit: BoxFit.contain)
              : Container(
                  color: Colors.white12,
                  child: Center(
                    child: Text(
                      card.name,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;

  _BubbleTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(size.width / 2, size.height);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final int score;

  const _ScoreCard({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9C433).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

