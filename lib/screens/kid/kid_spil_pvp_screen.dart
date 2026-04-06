import 'dart:math';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/spil_card_service.dart';
import '../../utils/card_assets.dart';
import '../../widgets/duel_angreb_tile.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/alfamon_card.dart';
import 'widgets/kid_session_nav_button.dart';

/// Angreb-billeder: samme som computer-spil.
/// Angreb-PNG'er vender mod højre i filen; spiller vises uden flip, modstander spejlvendes.
const bool _angrebImagesFaceRight = true;

/// PvP kamp – begge vælger kort, derefter evne. Kampen starter når begge har valgt.
class KidSpilPvpScreen extends StatefulWidget {
  final String kidId;
  final String matchId;

  const KidSpilPvpScreen({super.key, required this.kidId, required this.matchId});

  @override
  State<KidSpilPvpScreen> createState() => _KidSpilPvpScreenState();
}

class _KidSpilPvpScreenState extends State<KidSpilPvpScreen> {
  String? _opponentKidId;
  bool _amKid1 = true;
  List<SpilGameCard> _myCards = [];
  List<SpilGameCard> _opponentCards = [];
  bool _loading = true;
  String _phase = 'pick_card'; // pick_card, pick_strength, round_result, game_over
  int _roundNumber = 1;
  int _myScore = 0;
  int _opponentScore = 0;
  SpilGameCard? _myCard;
  SpilGameCard? _opponentCard;
  int? _myStrengthIndex;
  int? _opponentStrengthIndex;
  String? _roundWinner; // 'me', 'opponent', 'tie'
  String? _opponentName;
  bool _barometersReady = false;
  bool _iWonByForfeit = false; // Modstanderen opgav – vi vandt
  RealtimeChannel? _matchChannel;
  bool _hasInitialLoad = false;
  bool _resolvingRound = false;
  bool _autoPickInProgress = false;

  final _random = Random();
  late final AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    _audioPlayer.audioCache.prefix = '';
    _initAudio();
    _loadMatch();
  }

  @override
  void dispose() {
    _matchChannel?.unsubscribe();
    _audioPlayer.dispose();
    super.dispose();
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

  String _assetPath(String file) => 'assets/$file';

  void _playRisingSound() {
    _audioPlayer.stop();
    _audioPlayer.play(AssetSource(_assetPath('rising.mp3')));
  }

  void _stopRisingSound() {
    _audioPlayer.stop();
  }

  Future<void> _playRoundResultSound(String winner) async {
    if (winner == 'tie') return;
    final file = winner == 'me' ? 'Duvinder.mp3' : 'Modstanderenvinder.mp3';
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(_assetPath(file)));
      try {
        await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // Fortsæt flowet hvis lyd-event ikke kommer.
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RoundResult sound: $e');
    }
  }

  Future<void> _loadMatch() async {
    if (!_hasInitialLoad && mounted) {
      setState(() => _loading = true);
    }
    final client = Supabase.instance.client;

    Map<String, dynamic>? matchRes;
    try {
      matchRes = await client
          .from('kid_matches')
          .select('kid1_id,kid2_id,kid1_score,kid2_score,round_number,status,winner')
          .eq('id', widget.matchId)
          .maybeSingle();
    } catch (_) {
      final fallback = await client
          .from('kid_matches')
          .select('kid1_id,kid2_id,kid1_score,kid2_score,round_number,status')
          .eq('id', widget.matchId)
          .maybeSingle();
      if (fallback != null) {
        matchRes = {
          ...fallback,
          'winner': null,
        };
      }
    }

    if (matchRes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamp ikke fundet')),
        );
        context.go('/kid/spil/${widget.kidId}');
      }
      return;
    }

    final kid1Id = matchRes['kid1_id'] as String;
    final kid2Id = matchRes['kid2_id'] as String;
    _amKid1 = widget.kidId == kid1Id;
    _opponentKidId = _amKid1 ? kid2Id : kid1Id;
    _myScore = (_amKid1 ? matchRes['kid1_score'] : matchRes['kid2_score']) as int? ?? 0;
    _opponentScore = (_amKid1 ? matchRes['kid2_score'] : matchRes['kid1_score']) as int? ?? 0;
    _roundNumber = matchRes['round_number'] as int? ?? 1;

    final opponentRes = await client
        .from('kids')
        .select('name')
        .eq('id', _opponentKidId!)
        .maybeSingle();
    _opponentName = opponentRes?['name'] as String? ?? 'Modstander';

    var myCards = await SpilCardService.loadCardsForKid(widget.kidId);
    var opponentCards = await SpilCardService.loadCardsForKid(_opponentKidId!);

    if (myCards.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingen kort. Færdiggør opgaver først.')),
        );
        context.go('/kid/spil/${widget.kidId}');
      }
      return;
    }

    if (matchRes['status'] == 'completed') {
      if (!mounted) return;
      final winner = matchRes['winner'] as String?;
      final iWonByForfeit = winner != null &&
          ((winner == 'kid1' && _amKid1) || (winner == 'kid2' && !_amKid1));
      if (iWonByForfeit) {
        try {
          await client.from('game_wins').insert({
            'kid_id': widget.kidId,
            'metadata': {'type': 'pvp_forfeit', 'match_id': widget.matchId},
          });
        } catch (_) {}
      }
      setState(() {
        _loading = false;
        _myCards = myCards;
        _opponentCards = opponentCards;
        _phase = 'game_over';
        _iWonByForfeit = iWonByForfeit;
        _hasInitialLoad = true;
      });
      return;
    }

    _subscribeToMatch();

    final resolvedRounds = await client
        .from('kid_match_rounds')
        .select('round_number,kid1_avatar_id,kid2_avatar_id,kid1_stage_index,kid2_stage_index,winner')
        .eq('match_id', widget.matchId)
        .lt('round_number', _roundNumber)
        .eq('phase', 'resolved')
        .order('round_number');

    for (final r in resolvedRounds as List) {
      final k1Avatar = r['kid1_avatar_id'] as String?;
      final k2Avatar = r['kid2_avatar_id'] as String?;
      final k1Stage = r['kid1_stage_index'] as int? ?? 0;
      final k2Stage = r['kid2_stage_index'] as int? ?? 0;
      final winner = r['winner'] as String?;
      if (k1Avatar == null || k2Avatar == null || winner == null) continue;

      var k1Card = _findCardByAvatar(_amKid1 ? myCards : opponentCards, k1Avatar, k1Stage);
      var k2Card = _findCardByAvatar(_amKid1 ? opponentCards : myCards, k2Avatar, k2Stage);
      if (k1Card == null) {
        k1Card = await SpilCardService.loadCardByAvatar(client, k1Avatar, k1Stage);
      }
      if (k2Card == null) {
        k2Card = await SpilCardService.loadCardByAvatar(client, k2Avatar, k2Stage);
      }
      if (k1Card == null || k2Card == null) continue;

      final myCard = _amKid1 ? k1Card : k2Card;
      final oppCard = _amKid1 ? k2Card : k1Card;

      myCards = myCards.where((c) => !(c.avatarId == myCard.avatarId && c.stageIndex == myCard.stageIndex)).toList();
      opponentCards = opponentCards.where((c) => !(c.avatarId == oppCard.avatarId && c.stageIndex == oppCard.stageIndex)).toList();

      if (winner == 'kid1') {
        if (_amKid1) {
          myCards = [...myCards, myCard, oppCard];
        } else {
          opponentCards = [...opponentCards, k1Card, k2Card];
        }
      } else if (winner == 'kid2') {
        if (_amKid1) {
          opponentCards = [...opponentCards, k1Card, k2Card];
        } else {
          myCards = [...myCards, myCard, oppCard];
        }
      } else {
        myCards = [...myCards, myCard];
        opponentCards = [...opponentCards, oppCard];
      }
    }

    final roundRes = await client
        .from('kid_match_rounds')
        .select('*')
        .eq('match_id', widget.matchId)
        .eq('round_number', _roundNumber)
        .maybeSingle();

    if (roundRes != null) {
      final phase = roundRes['phase'] as String? ?? 'pick_card';
      final k1Avatar = roundRes['kid1_avatar_id'] as String?;
      final k2Avatar = roundRes['kid2_avatar_id'] as String?;
      final k1Strength = roundRes['kid1_strength_index'] as int?;
      final k2Strength = roundRes['kid2_strength_index'] as int?;
      final winner = roundRes['winner'] as String?;

      if (phase == 'resolved' && winner != null) {
        _roundWinner = winner == 'kid1' ? (_amKid1 ? 'me' : 'opponent') : (winner == 'kid2' ? (_amKid1 ? 'opponent' : 'me') : 'tie');
      }

      SpilGameCard? myCard;
      SpilGameCard? oppCard;
      if (_amKid1) {
        if (k1Avatar != null) {
          myCard = _findCardByAvatar(myCards, k1Avatar, roundRes['kid1_stage_index'] as int?);
          myCard ??= await SpilCardService.loadCardByAvatar(client, k1Avatar, roundRes['kid1_stage_index'] as int? ?? 0);
        }
        if (k2Avatar != null) {
          oppCard = _findCardByAvatar(opponentCards, k2Avatar, roundRes['kid2_stage_index'] as int?);
          oppCard ??= await SpilCardService.loadCardByAvatar(client, k2Avatar, roundRes['kid2_stage_index'] as int? ?? 0);
        }
        _myStrengthIndex = k1Strength;
        _opponentStrengthIndex = k2Strength;
      } else {
        if (k2Avatar != null) {
          myCard = _findCardByAvatar(myCards, k2Avatar, roundRes['kid2_stage_index'] as int?);
          myCard ??= await SpilCardService.loadCardByAvatar(client, k2Avatar, roundRes['kid2_stage_index'] as int? ?? 0);
        }
        if (k1Avatar != null) {
          oppCard = _findCardByAvatar(opponentCards, k1Avatar, roundRes['kid1_stage_index'] as int?);
          oppCard ??= await SpilCardService.loadCardByAvatar(client, k1Avatar, roundRes['kid1_stage_index'] as int? ?? 0);
        }
        _myStrengthIndex = k2Strength;
        _opponentStrengthIndex = k1Strength;
      }

      // Kort som allerede er valgt i den aktuelle runde er "på bordet" og
      // må ikke stadig ligge i bunken, ellers bliver næste kortvalg tilfældigt.
      if (myCard != null) {
        myCards = myCards
            .where((c) =>
                !(c.avatarId == myCard!.avatarId &&
                    c.stageIndex == myCard!.stageIndex))
            .toList();
      }
      if (oppCard != null) {
        opponentCards = opponentCards
            .where((c) =>
                !(c.avatarId == oppCard!.avatarId &&
                    c.stageIndex == oppCard!.stageIndex))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _myCards = myCards;
        _opponentCards = opponentCards;
        _phase = phase;
        _myCard = myCard;
        _opponentCard = oppCard;
        _barometersReady =
            (phase == 'pick_strength' || phase == 'resolved') &&
            _myStrengthIndex != null &&
            _opponentStrengthIndex != null;
        _hasInitialLoad = true;
      });
      _autoPickMyCardIfNeeded();
    } else {
      await _ensureRoundExists();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _myCards = myCards..shuffle(_random);
        _opponentCards = opponentCards;
        _hasInitialLoad = true;
      });
      _autoPickMyCardIfNeeded();
    }
  }

  SpilGameCard? _findCardByAvatar(List<SpilGameCard> cards, String avatarId, int? stageIndex) {
    for (final c in cards) {
      if (c.avatarId == avatarId && (stageIndex == null || c.stageIndex == stageIndex)) return c;
    }
    return cards.where((c) => c.avatarId == avatarId).firstOrNull;
  }

  Future<void> _ensureRoundExists() async {
    await Supabase.instance.client.from('kid_match_rounds').upsert({
      'match_id': widget.matchId,
      'round_number': _roundNumber,
      'phase': 'pick_card',
    }, onConflict: 'match_id,round_number');
  }

  void _subscribeToMatch() {
    _matchChannel = Supabase.instance.client
        .channel('match_${widget.matchId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_match_rounds',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: widget.matchId,
          ),
          callback: (_) => _loadMatch(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.matchId,
          ),
          callback: (_) => _loadMatch(),
        )
        .subscribe();
  }

  Future<void> _pickCard(SpilGameCard card) async {
    final client = Supabase.instance.client;
    final col1 = _amKid1 ? 'kid1_avatar_id' : 'kid2_avatar_id';
    final col2 = _amKid1 ? 'kid1_stage_index' : 'kid2_stage_index';

    await client.from('kid_match_rounds').update({
      col1: card.avatarId,
      col2: card.stageIndex,
    }).eq('match_id', widget.matchId).eq('round_number', _roundNumber);

    setState(() {
      _myCard = card;
      _myCards = _myCards.where((c) => c.id != card.id).toList();
    });
    _checkRoundPhase();
  }

  /// Bestemmer hvem der vælger evne: starter (runde 1) eller vinder af sidste runde. Ved uafgjort: samme som sidst.
  Future<String> _getAbilityPickerForRound() async {
    if (_roundNumber == 1) return 'kid1';

    final prevRes = await Supabase.instance.client
        .from('kid_match_rounds')
        .select('winner,ability_picker')
        .eq('match_id', widget.matchId)
        .eq('round_number', _roundNumber - 1)
        .maybeSingle();

    if (prevRes == null) return 'kid1';
    final winner = prevRes['winner'] as String?;
    final prevPicker = prevRes['ability_picker'] as String?;

    if (winner == 'kid1' || winner == 'kid2') return winner!;
    return prevPicker ?? 'kid1';
  }

  Future<void> _checkRoundPhase() async {
    final roundRes = await Supabase.instance.client
        .from('kid_match_rounds')
        .select('kid1_avatar_id,kid2_avatar_id,kid1_strength_index,kid2_strength_index,phase,ability_picker')
        .eq('match_id', widget.matchId)
        .eq('round_number', _roundNumber)
        .maybeSingle();

    if (roundRes == null) return;

    final k1Avatar = roundRes['kid1_avatar_id'];
    final k2Avatar = roundRes['kid2_avatar_id'];
    final k1Str = roundRes['kid1_strength_index'] as int?;
    final k2Str = roundRes['kid2_strength_index'] as int?;
    if (k1Avatar != null && k2Avatar != null && _phase == 'pick_card') {
      final picker = await _getAbilityPickerForRound();
      await Supabase.instance.client.from('kid_match_rounds').update({
        'phase': 'pick_strength',
        'ability_picker': picker,
      }).eq('match_id', widget.matchId).eq('round_number', _roundNumber);

      final myCard = _myCard;
      SpilGameCard? oppCard;
      if (_amKid1) {
        oppCard = _findCardByAvatar(_opponentCards, k2Avatar as String, roundRes['kid2_stage_index'] as int?);
      } else {
        oppCard = _findCardByAvatar(_opponentCards, k1Avatar as String, roundRes['kid1_stage_index'] as int?);
      }

      final iAmPicker = (picker == 'kid1' && _amKid1) || (picker == 'kid2' && !_amKid1);

      if (mounted) {
        setState(() {
          _phase = 'pick_strength';
          _opponentCard = oppCard;
          if (oppCard != null) {
            final playedOppCard = oppCard;
            // Kortet er nu "på bordet" og må ikke stadig ligge i modstanderens bunke.
            _opponentCards = _opponentCards
                .where((c) =>
                    !(c.avatarId == playedOppCard.avatarId &&
                        c.stageIndex == playedOppCard.stageIndex))
                .toList();
          }
          _myStrengthIndex = null;
          _opponentStrengthIndex = null;
          _abilityPickerCached = picker;
          _barometersReady = false;
        });
        await _playAbilityChoiceSound(iAmPicker);
        if (mounted) setState(() => _barometersReady = true);
      }
    } else if (k1Str != null && k2Str != null && _phase == 'pick_strength') {
      // Vis duel med barometre først – _resolveRound kaldes når barometer er færdig
      if (mounted) setState(() => _barometersReady = true);
    }
  }

  Future<void> _playAbilityChoiceSound(bool meFirst) async {
    try {
      await _audioPlayer.stop();
      final file = meFirst ? 'Vaelgevne.mp3' : 'Modstandervaelgerevne.mp3';
      _audioPlayer.play(AssetSource(_assetPath(file)));
      try {
        await _audioPlayer.onPlayerComplete.first.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // Fortsæt selv hvis completion-event mangler.
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Ability sound: $e');
    }
  }

  Future<void> _pickStrength(int index) async {
    final iAmPicker = await _amIAbilityPicker();
    if (!iAmPicker) return;

    final client = Supabase.instance.client;
    // Samme evne skal bruges af begge spillere i runden.
    await client.from('kid_match_rounds').update({
      'kid1_strength_index': index,
      'kid2_strength_index': index,
    }).eq('match_id', widget.matchId).eq('round_number', _roundNumber);

    if (mounted) {
      setState(() {
        _myStrengthIndex = index;
        _opponentStrengthIndex = index;
      });
    }
    _checkRoundPhase();
  }

  Future<void> _resolveRound() async {
    if (_resolvingRound) return;
    if (_myCard == null || _opponentCard == null || _myStrengthIndex == null) return;
    _resolvingRound = true;

    try {
      _stopRisingSound();
      final myStr = _myCard!.strengths.where((s) => s.strengthIndex == _myStrengthIndex).firstOrNull;
      final oppStr = _opponentCard!.strengths.where((s) => s.strengthIndex == _opponentStrengthIndex).firstOrNull;
      final myVal = myStr?.value ?? 0;
      final oppVal = oppStr?.value ?? 0;

      String winner;
      if (myVal > oppVal) {
        winner = _amKid1 ? 'kid1' : 'kid2';
      } else if (oppVal > myVal) {
        winner = _amKid1 ? 'kid2' : 'kid1';
      } else {
        winner = 'tie';
      }

      await Supabase.instance.client.from('kid_match_rounds').update({
        'phase': 'resolved',
        'winner': winner,
      }).eq('match_id', widget.matchId).eq('round_number', _roundNumber);

      final matchRes = await Supabase.instance.client
          .from('kid_matches')
          .select('kid1_score,kid2_score')
          .eq('id', widget.matchId)
          .maybeSingle();
      final curKid1 = matchRes?['kid1_score'] as int? ?? 0;
      final curKid2 = matchRes?['kid2_score'] as int? ?? 0;
      final newKid1Score = curKid1 + (winner == 'kid1' ? 1 : 0);
      final newKid2Score = curKid2 + (winner == 'kid2' ? 1 : 0);

      await Supabase.instance.client.from('kid_matches').update({
        'kid1_score': newKid1Score,
        'kid2_score': newKid2Score,
      }).eq('id', widget.matchId);

      final roundWinner =
          winner == 'tie' ? 'tie' : (winner == (_amKid1 ? 'kid1' : 'kid2') ? 'me' : 'opponent');

      if (mounted) {
        setState(() {
          _roundWinner = roundWinner;
          _myScore = roundWinner == 'me' ? _myScore + 1 : _myScore;
          _opponentScore = roundWinner == 'opponent' ? _opponentScore + 1 : _opponentScore;
        });
      }

      await _playRoundResultSound(roundWinner);
    } finally {
      _resolvingRound = false;
    }
  }

  Future<void> _applyRoundResult() async {
    _stopRisingSound();
    final myCard = _myCard!;
    final oppCard = _opponentCard!;
    final roundWinner = _roundWinner!;

    if (roundWinner == 'me') {
      _myCards.add(myCard);
      _myCards.add(SpilGameCard(
        id: 'opp-${DateTime.now().millisecondsSinceEpoch}-${oppCard.avatarId}',
        avatarId: oppCard.avatarId,
        name: oppCard.name,
        letter: oppCard.letter,
        imageUrl: oppCard.imageUrl,
        stageIndex: oppCard.stageIndex,
        strengths: oppCard.strengths,
      ));
    } else if (roundWinner == 'opponent') {
      // Modstanderen vinder begge kort og får dem bagerst i bunken.
      _opponentCards.add(oppCard);
      _opponentCards.add(SpilGameCard(
        id: 'my-${DateTime.now().millisecondsSinceEpoch}-${myCard.avatarId}',
        avatarId: myCard.avatarId,
        name: myCard.name,
        letter: myCard.letter,
        imageUrl: myCard.imageUrl,
        stageIndex: myCard.stageIndex,
        strengths: myCard.strengths,
      ));
    } else {
      // Uafgjort: begge kort tilbage til deres egne bunker bagerst.
      _myCards.add(myCard);
      _opponentCards.add(oppCard);
    }

    if (_myCards.isEmpty || _opponentCards.isEmpty) {
      await Supabase.instance.client.from('kid_matches').update({'status': 'completed'}).eq('id', widget.matchId);
      if (mounted) setState(() => _phase = 'game_over');
      return;
    }

    await Supabase.instance.client.from('kid_matches').update({
      'round_number': _roundNumber + 1,
    }).eq('id', widget.matchId);

    if (mounted) {
      setState(() {
        _roundNumber++;
        _phase = 'pick_card';
        _myCard = null;
        _opponentCard = null;
        _myStrengthIndex = null;
        _opponentStrengthIndex = null;
        _roundWinner = null;
        _abilityPickerCached = null;
      });
      _ensureRoundExists();
      _autoPickMyCardIfNeeded();
    }
  }

  void _autoPickMyCardIfNeeded() {
    if (!mounted || _autoPickInProgress) return;
    if (_phase != 'pick_card' || _myCard != null || _myCards.isEmpty) return;
    // Ved 1-3 kort skal spilleren kunne vælge kort manuelt.
    if (_myCards.length <= 3) return;
    _autoPickInProgress = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        if (_phase != 'pick_card' || _myCard != null || _myCards.isEmpty) return;
        await _pickCard(_myCards.first);
      } finally {
        _autoPickInProgress = false;
      }
    });
  }

  AlfamonCardData _toCardData(SpilGameCard c) => AlfamonCardData(
        name: c.name,
        letter: c.letter,
        imageUrl: c.imageUrl,
        assetPath: CardAssets.getCardAssetPath(c.name, c.stageIndex, letter: c.letter),
        strengths: c.strengths.map((s) => AlfamonStrength(strengthIndex: s.strengthIndex, name: s.name, value: s.value)).toList(),
      );

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;
    final bgAsset = isTablet ? 'assets/baggrund_roedipad.svg' : 'assets/baggrund_roediphone.svg';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: SvgPicture.asset(bgAsset, fit: BoxFit.cover)),
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
                      Expanded(
                        child: Text(
                          'Kamp mod ${_opponentName ?? 'Modstander'}',
                          style: TextStyle(fontSize: isTablet ? 28 : 24, fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const KidParentAdminCornerButton(),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : _phase == 'game_over'
                          ? _buildGameOver()
                          : _buildGame(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _abilityPickerCached;

  Future<bool> _amIAbilityPicker() async {
    if (_abilityPickerCached != null) {
      return (_abilityPickerCached == 'kid1' && _amKid1) || (_abilityPickerCached == 'kid2' && !_amKid1);
    }
    final roundRes = await Supabase.instance.client
        .from('kid_match_rounds')
        .select('phase,ability_picker,kid1_avatar_id,kid2_avatar_id')
        .eq('match_id', widget.matchId)
        .eq('round_number', _roundNumber)
        .maybeSingle();

    var picker = roundRes?['ability_picker'] as String?;
    final phase = roundRes?['phase'] as String?;
    final k1Avatar = roundRes?['kid1_avatar_id'];
    final k2Avatar = roundRes?['kid2_avatar_id'];

    // Fallback: Hvis pick_strength er startet, men ability_picker ikke er skrevet endnu,
    // udled den deterministisk for denne runde, så den rigtige spiller kan vælge evne.
    if (picker == null && phase == 'pick_strength' && k1Avatar != null && k2Avatar != null) {
      picker = await _getAbilityPickerForRound();
      await Supabase.instance.client
          .from('kid_match_rounds')
          .update({'ability_picker': picker})
          .eq('match_id', widget.matchId)
          .eq('round_number', _roundNumber);
    }

    _abilityPickerCached = picker;
    return (_abilityPickerCached == 'kid1' && _amKid1) || (_abilityPickerCached == 'kid2' && !_amKid1);
  }

  Widget _buildGame() {
    if (_phase == 'pick_card' && _myCard == null) {
      return _buildPickCard();
    }
    if (_phase == 'pick_card' && _myCard != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Venter på at ${_opponentName ?? 'Modstander'} vælger kort...', style: const TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            AlfamonCard(card: _toCardData(_myCard!), width: 120),
          ],
        ),
      );
    }
    if (_phase == 'pick_strength') {
      return FutureBuilder<bool>(
        future: _amIAbilityPicker(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          final iAmPicker = snap.data ?? false;
          if (iAmPicker && _myStrengthIndex == null) {
            return _buildPickStrength();
          }
          if (iAmPicker && _myStrengthIndex != null && _opponentStrengthIndex == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Venter på at ${_opponentName ?? 'Modstander'} vælger evne...', style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 16),
                  AlfamonCard(card: _toCardData(_myCard!), selectedStrengthIndex: _myStrengthIndex, width: 120),
                ],
              ),
            );
          }
          if (!iAmPicker && _opponentStrengthIndex == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Venter på at ${_opponentName ?? 'Modstander'} vælger evne...', style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 16),
                  if (_myCard != null)
                    AlfamonCard(card: _toCardData(_myCard!), selectedStrengthIndex: _myStrengthIndex, width: 120),
                ],
              ),
            );
          }
          if (_myCard == null || _opponentCard == null || _myStrengthIndex == null || _opponentStrengthIndex == null) {
            return Center(
              child: Text(
                'Venter på at kampen bliver klar...',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            );
          }
          return _buildDuelLayout();
        },
      );
    }
    if (_myCard == null || _opponentCard == null) {
      return Center(
        child: Text(
          'Venter på næste træk...',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      );
    }
    return _buildDuelLayout();
  }

  Widget _buildPickCard() {
    const gameCardWidth = 103.5;
    final useDeck = _myCards.length > 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ScoreCard(label: 'Dig', score: _myScore),
              Text('Runde $_roundNumber', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9))),
              _ScoreCard(label: _opponentName ?? 'Modstander', score: _opponentScore),
            ],
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: gameCardWidth + 20,
                child: _buildOpponentPile(gameCardWidth, 4.0),
              ),
            ),
          ),
          Positioned(
            top: 56,
            right: 8,
            child: Text(
              '${_opponentCards.length} kort',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          if (useDeck) ...[
            Positioned(
              bottom: 100,
              left: 0,
              child: _buildPlayerPile(gameCardWidth, 4.0),
            ),
            Positioned(
              bottom: 92,
              left: 0,
              child: Text(
                '${_myCards.length} kort',
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
                    onPressed: () {
                      if (_myCards.isNotEmpty) _pickCard(_myCards.first);
                    },
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
          ] else ...[
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vælg et kort at spille',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.95)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _myCards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => _pickCard(_myCards[i]),
                          child: AlfamonCard(card: _toCardData(_myCards[i]), width: gameCardWidth),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerPile(double cardWidth, double stackOffset) {
    if (_myCards.isEmpty) return const SizedBox.shrink();
    final topCard = _myCards.first;
    final count = _myCards.length;
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
            child: AlfamonCard(card: _toCardData(topCard), width: cardWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentPile(double cardWidth, double stackOffset) {
    final count = _opponentCards.length;
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

  Widget _buildPickStrength() {
    final card = _myCard!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ScoreCard(label: 'Dig', score: _myScore),
              Text('Runde $_roundNumber', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9))),
              _ScoreCard(label: _opponentName ?? 'Modstander', score: _opponentScore),
            ],
          ),
          const SizedBox(height: 16),
          AlfamonCard(card: _toCardData(card), width: 120),
          const SizedBox(height: 16),
          const Text('Vælg styrke', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          StrengthChoiceGrid(
            strengths: card.strengths.map((s) => AlfamonStrength(strengthIndex: s.strengthIndex, name: s.name, value: s.value)).toList(),
            onSelect: _pickStrength,
          ),
        ],
      ),
    );
  }

  static const double _gameCardWidth = 103.5;

  Widget _buildDuelLayout() {
    final myCard = _myCard!;
    final oppCard = _opponentCard!;
    final myStr = myCard.strengths.where((s) => s.strengthIndex == _myStrengthIndex).firstOrNull;
    final oppStr = oppCard.strengths.where((s) => s.strengthIndex == _opponentStrengthIndex).firstOrNull;

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
                  _ScoreCard(label: 'Dig', score: _myScore),
                  Text('Runde $_roundNumber', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9))),
                  _ScoreCard(label: _opponentName ?? 'Modstander', score: _opponentScore),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DuelAngrebTile(
                        name: myCard.name,
                        stageIndex: myCard.stageIndex,
                        letter: myCard.letter,
                        faceRight: _angrebImagesFaceRight,
                        strengthName: myStr?.name,
                        powerValue: myStr?.value ?? 0,
                        barometerOnRight: true,
                        animationDelayMs: 0,
                        barometersReady: _barometersReady,
                        onBarometerStart: _playRisingSound,
                        onBarometerComplete: _stopRisingSound,
                      ),
                    ),
                    Expanded(
                      child: DuelAngrebTile(
                        name: oppCard.name,
                        stageIndex: oppCard.stageIndex,
                        letter: oppCard.letter,
                        faceRight: !_angrebImagesFaceRight,
                        strengthName: oppStr?.name,
                        powerValue: oppStr?.value ?? 0,
                        barometerOnRight: false,
                        animationDelayMs: 1200,
                        barometersReady: _barometersReady,
                        onBarometerStart: _playRisingSound,
                        onBarometerComplete: () {
                          _stopRisingSound();
                          if (_roundWinner == null) _resolveRound();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_roundWinner != null) ...[
                const SizedBox(height: 12),
                Text(
                  _roundWinner == 'me'
                      ? '✓ Du vandt runden!'
                      : _roundWinner == 'opponent'
                          ? '✗ $_opponentName vandt'
                          : 'Uafgjort',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _roundWinner == 'me'
                        ? Colors.green
                        : _roundWinner == 'opponent'
                            ? Colors.red
                            : Colors.amber,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _applyRoundResult,
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
            card: _toCardData(myCard),
            selectedStrengthIndex: _myStrengthIndex,
            isWinner: _roundWinner == 'me',
            width: _gameCardWidth,
          ),
        ),
        if (_roundWinner == 'me')
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: Center(child: _buildWinnerSplash()),
          ),
        if (_roundWinner == 'opponent')
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

  Widget _buildGameOver() {
    final iWon = _iWonByForfeit ||
        (_opponentCards.isEmpty && _myCards.isNotEmpty) ||
        (_opponentCards.isNotEmpty && _myCards.isNotEmpty && _myScore > _opponentScore);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            iWon ? 'Du vandt!' : '$_opponentName vandt!',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          if (_iWonByForfeit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$_opponentName opgav',
                style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.9)),
              ),
            ),
          const SizedBox(height: 16),
          Text('$_myScore - $_opponentScore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.95))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go('/kid/spil/${widget.kidId}'),
            icon: const Icon(Icons.home),
            label: const Text('Tilbage'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF9C433), foregroundColor: Colors.black87),
          ),
        ],
      ),
    );
  }

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
          ),
          Text(
            '$score',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

