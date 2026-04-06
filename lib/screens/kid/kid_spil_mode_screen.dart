import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/kid_session_nav_button.dart';

/// Samlet spilskærm: Ven (venstre), Computer (midten), Aktive spil (højre).
/// Bruger kampskaerm.png som baggrund.
class KidSpilModeScreen extends StatefulWidget {
  final String kidId;

  const KidSpilModeScreen({super.key, required this.kidId});

  @override
  State<KidSpilModeScreen> createState() => _KidSpilModeScreenState();
}

enum _GameType { pending, active, computer }

class _GameItem {
  final _GameType type;
  final String? invitationId;
  final String? matchId;
  final String? computerMatchId;
  final String opponentName;
  final bool isPending;

  _GameItem.pending({
    required this.invitationId,
    required this.opponentName,
  })  : type = _GameType.pending,
        matchId = null,
        computerMatchId = null,
        isPending = true;

  _GameItem.active({
    required this.matchId,
    required this.opponentName,
  })  : type = _GameType.active,
        invitationId = null,
        computerMatchId = null,
        isPending = false;

  _GameItem.computer({String? computerMatchId})
      : type = _GameType.computer,
        invitationId = null,
        matchId = null,
        computerMatchId = computerMatchId,
        opponentName = 'Computer',
        isPending = false;
}

class _KidSpilModeScreenState extends State<KidSpilModeScreen> {
  List<_GameItem> _games = [];
  bool _loading = true;
  RealtimeChannel? _invitationChannel;
  RealtimeChannel? _matchChannel;
  RealtimeChannel? _computerChannel;

  @override
  void initState() {
    super.initState();
    _loadGames();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _invitationChannel?.unsubscribe();
    _matchChannel?.unsubscribe();
    _computerChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToRealtime() {
    final client = Supabase.instance.client;
    _invitationChannel = client
        .channel('kid_spil_invitations_${widget.kidId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_match_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'challenger_kid_id',
            value: widget.kidId,
          ),
          callback: (_) {
            if (mounted) _loadGames();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_match_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'challenged_kid_id',
            value: widget.kidId,
          ),
          callback: (_) {
            if (mounted) _loadGames();
          },
        )
        .subscribe();

    _matchChannel = client
        .channel('kid_spil_matches_${widget.kidId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'kid1_id',
            value: widget.kidId,
          ),
          callback: (_) {
            if (mounted) _loadGames();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'kid2_id',
            value: widget.kidId,
          ),
          callback: (_) {
            if (mounted) _loadGames();
          },
        )
        .subscribe();

    _computerChannel = client
        .channel('kid_computer_${widget.kidId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kid_computer_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'kid_id',
            value: widget.kidId,
          ),
          callback: (_) {
            if (mounted) _loadGames();
          },
        )
        .subscribe();
  }

  Future<void> _loadGames() async {
    final client = Supabase.instance.client;
    final games = <_GameItem>[];

    // Spil mod computer først – så det altid er synligt og Afslut virker
    final computerRes = await client
        .from('kid_computer_matches')
        .select('id')
        .eq('kid_id', widget.kidId)
        .eq('status', 'in_progress')
        .order('updated_at', ascending: false)
        .limit(1);

    if ((computerRes as List).isNotEmpty) {
      games.add(_GameItem.computer(computerMatchId: computerRes.first['id'] as String));
    }

    final pendingRes = await client
        .from('kid_match_invitations')
        .select('id,challenged_kid_id')
        .eq('challenger_kid_id', widget.kidId)
        .eq('status', 'pending');

    for (final r in pendingRes as List) {
      final challengedId = r['challenged_kid_id'] as String;
      final kidRes = await client
          .from('kids')
          .select('name')
          .eq('id', challengedId)
          .maybeSingle();
      final name = kidRes?['name'] as String? ?? 'Nogen';
      games.add(_GameItem.pending(
        invitationId: r['id'] as String,
        opponentName: name,
      ));
    }

    final matchesRes = await client
        .from('kid_matches')
        .select('id,kid1_id,kid2_id')
        .eq('status', 'in_progress');

    for (final m in matchesRes as List) {
      final kid1 = m['kid1_id'] as String;
      final kid2 = m['kid2_id'] as String;
      final otherId = kid1 == widget.kidId ? kid2 : kid1;
      final kidRes = await client
          .from('kids')
          .select('name')
          .eq('id', otherId)
          .maybeSingle();
      final name = kidRes?['name'] as String? ?? 'Nogen';
      games.add(_GameItem.active(
        matchId: m['id'] as String,
        opponentName: name,
      ));
    }

    if (mounted) {
      setState(() {
        _games = games;
        _loading = false;
      });
    }
  }

  Future<void> _withdrawInvitation(String invitationId) async {
    await Supabase.instance.client
        .from('kid_match_invitations')
        .delete()
        .eq('id', invitationId)
        .eq('challenger_kid_id', widget.kidId);
    _loadGames();
  }

  Future<void> _quitMatch(String matchId) async {
    final matchRes = await Supabase.instance.client
        .from('kid_matches')
        .select('kid1_id,kid2_id')
        .eq('id', matchId)
        .maybeSingle();
    final kid1Id = matchRes?['kid1_id'] as String?;
    final kid2Id = matchRes?['kid2_id'] as String?;
    final winner = (kid1Id != null && kid2Id != null && widget.kidId == kid1Id)
        ? 'kid2'
        : (widget.kidId == kid2Id ? 'kid1' : null);
    try {
      await Supabase.instance.client
          .from('kid_matches')
          .update({'status': 'completed', if (winner != null) 'winner': winner})
          .eq('id', matchId);
    } catch (e) {
      // Backward compatibility: DB kan mangle winner-kolonnen indtil migration er kørt.
      await Supabase.instance.client
          .from('kid_matches')
          .update({'status': 'completed'})
          .eq('id', matchId);
    }
    _loadGames();
  }

  Future<void> _quitComputerMatch(String? computerMatchId) async {
    await Supabase.instance.client
        .from('kid_computer_matches')
        .update({'status': 'completed', 'updated_at': DateTime.now().toIso8601String()})
        .eq('kid_id', widget.kidId)
        .eq('status', 'in_progress');
    _loadGames();
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset('assets/kampskaerm.webp', fit: BoxFit.cover),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      KidSessionNavButton(kidId: widget.kidId),
                      const Spacer(),
                      const KidParentAdminCornerButton(),
                    ],
                  ),
                ),
                const Spacer(flex: 1),
                Expanded(
                  flex: 8,
                  child: Row(
                    children: [
                      // 1/3 venstre: Kæmp mod en ven
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: _ModeButton(
                            title: 'Kæmp mod en ven',
                            onTap: () =>
                                context.push('/kid/spil/${widget.kidId}/ven'),
                          ),
                        ),
                      ),
                      // 1/3 midten: Kæmp mod computeren
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: _ModeButton(
                            title: 'Kæmp mod computeren',
                            onTap: () =>
                                context.push('/kid/spil/${widget.kidId}/computer'),
                          ),
                        ),
                      ),
                      // 1/3 højre: Aktive spil
                      Expanded(
                        flex: 1,
                        child: _ActiveGamesPanel(
                          kidId: widget.kidId,
                          games: _games,
                          loading: _loading,
                          onWithdraw: _withdrawInvitation,
                          onQuit: _quitMatch,
                          onQuitComputer: _quitComputerMatch,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _ModeButton extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _ModeButton({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFF9C433),
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      child: Text(title),
    );
  }
}

class _ActiveGamesPanel extends StatelessWidget {
  final String kidId;
  final List<_GameItem> games;
  final bool loading;
  final void Function(String) onWithdraw;
  final void Function(String) onQuit;
  final void Function(String?) onQuitComputer;

  const _ActiveGamesPanel({
    required this.kidId,
    required this.games,
    required this.loading,
    required this.onWithdraw,
    required this.onQuit,
    required this.onQuitComputer,
  });

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        // 30% mindre (0.75 * 0.7 ≈ 0.53) så der er plads til tre aktive spil
        final cardWidth = panelWidth * 0.53;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Aktive spil',
                style: TextStyle(
                  fontSize: isTablet ? 18 : 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : games.isEmpty
                      ? Center(
                          child: Text(
                            'Ingen aktive spil',
                            style: TextStyle(
                              fontSize: isTablet ? 14 : 12,
                              color: Colors.white70,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: games.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Center(
                              child: _GameCard(
                                item: games[i],
                                kidId: kidId,
                                cardWidth: cardWidth,
                                isTablet: isTablet,
                                onWithdraw: games[i].invitationId != null
                                    ? () => onWithdraw(games[i].invitationId!)
                                    : null,
                                onQuit: games[i].matchId != null
                                    ? () => onQuit(games[i].matchId!)
                                    : null,
                                onQuitComputer: games[i].computerMatchId != null
                                    ? () => onQuitComputer(games[i].computerMatchId)
                                    : null,
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _GameCard extends StatelessWidget {
  final _GameItem item;
  final String kidId;
  final double cardWidth;
  final bool isTablet;
  final VoidCallback? onWithdraw;
  final VoidCallback? onQuit;
  final void Function()? onQuitComputer;

  const _GameCard({
    required this.item,
    required this.kidId,
    required this.cardWidth,
    required this.isTablet,
    this.onWithdraw,
    this.onQuit,
    this.onQuitComputer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Kort: kun billede med knapper ovenpå
        SizedBox(
          width: cardWidth,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.asset(
                    'assets/spilskaerm.webp',
                    fit: BoxFit.cover,
                  ),
                ),
                // Knapper ovenpå
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: item.isPending
                            ? null
                            : () {
                                if (item.matchId != null) {
                                  context.push(
                                      '/kid/spil/$kidId/pvp/${item.matchId}');
                                } else if (item.type == _GameType.computer) {
                                  final uri = item.computerMatchId != null
                                      ? Uri.parse('/kid/spil/$kidId/computer')
                                          .replace(queryParameters: {'matchId': item.computerMatchId})
                                      : Uri.parse('/kid/spil/$kidId/computer');
                                  context.push(uri.toString());
                                }
                              },
                        icon: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 28),
                        tooltip: 'Spil',
                        style: IconButton.styleFrom(
                          backgroundColor: item.isPending
                              ? Colors.grey
                              : const Color(0xFF4CAF50),
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: (onWithdraw != null || onQuit != null || onQuitComputer != null)
                            ? () async {
                                final doIt = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Afslut?'),
                                    content: Text(
                                      item.isPending
                                          ? 'Vil du trække din udfordring tilbage?'
                                          : item.type == _GameType.computer
                                              ? 'Vil du afslutte spillet mod computeren?'
                                              : 'Vil du afslutte kampen?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Annuller'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Afslut'),
                                      ),
                                    ],
                                  ),
                                );
                                if (doIt == true && context.mounted) {
                                  if (item.invitationId != null) {
                                    onWithdraw?.call();
                                  } else if (item.matchId != null) {
                                    onQuit?.call();
                                  } else if (item.type == _GameType.computer) {
                                    onQuitComputer?.call();
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 22),
                        tooltip: 'Afslut',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.isPending)
                  Positioned(
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Afventer',
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Modstanderens navn under feltet
        const SizedBox(height: 6),
        SizedBox(
          width: cardWidth,
          child: Text(
            'Mod ${item.opponentName}',
            style: TextStyle(
              fontSize: isTablet ? 14 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
