import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/kid.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/kid_session_nav_button.dart';

/// Vælg ven at udfordre – kun børn under samme forælder.
class KidSpilVenScreen extends StatefulWidget {
  final String kidId;

  const KidSpilVenScreen({super.key, required this.kidId});

  @override
  State<KidSpilVenScreen> createState() => _KidSpilVenScreenState();
}

class _InvitationToMe {
  final String id;
  final String challengerKidId;
  final String challengerName;

  _InvitationToMe({
    required this.id,
    required this.challengerKidId,
    required this.challengerName,
  });
}

class _KidSpilVenScreenState extends State<KidSpilVenScreen> {
  List<Kid> _kids = [];
  List<_InvitationToMe> _invitationsToMe = [];
  bool _loading = true;
  String? _challengedKidId; // Viser "venter på svar" for denne
  RealtimeChannel? _invitationToMeChannel;

  @override
  void initState() {
    super.initState();
    _loadKids();
    _subscribeToInvitationsToMe();
  }

  @override
  void dispose() {
    _invitationToMeChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToInvitationsToMe() {
    _invitationToMeChannel = Supabase.instance.client
        .channel('kid_invitations_to_${widget.kidId}')
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
            if (mounted) _loadInvitationsToMe();
          },
        )
        .subscribe();
  }

  Future<String?> _waitForMatchId(String invitationId) async {
    for (var i = 0; i < 25 && mounted; i++) {
      final matchRes = await Supabase.instance.client
          .from('kid_matches')
          .select('id')
          .eq('invitation_id', invitationId)
          .maybeSingle();
      final matchId = matchRes?['id'] as String?;
      if (matchId != null) return matchId;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  Future<void> _loadInvitationsToMe() async {
    final res = await Supabase.instance.client
        .from('kid_match_invitations')
        .select('id,challenger_kid_id')
        .eq('challenged_kid_id', widget.kidId)
        .eq('status', 'pending');

    final list = <_InvitationToMe>[];
    for (final r in res as List) {
      final challengerId = r['challenger_kid_id'] as String;
      final kidRes = await Supabase.instance.client
          .from('kids')
          .select('name')
          .eq('id', challengerId)
          .maybeSingle();
      final name = kidRes?['name'] as String? ?? 'Nogen';
      list.add(_InvitationToMe(
        id: r['id'] as String,
        challengerKidId: challengerId,
        challengerName: name,
      ));
    }
    if (mounted) setState(() => _invitationsToMe = list);
  }

  Future<void> _respondToInvitation(String invitationId, bool accept) async {
    try {
      final updated = await Supabase.instance.client
          .from('kid_match_invitations')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', invitationId)
          .eq('challenged_kid_id', widget.kidId)
          .eq('status', 'pending')
          .select('id')
          .maybeSingle();
      if (updated == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Udfordringen er allerede håndteret.')),
          );
          _loadInvitationsToMe();
        }
        return;
      }

      if (accept) {
        final matchId = await _waitForMatchId(invitationId);
        if (matchId != null && mounted) {
          context.go('/kid/spil/${widget.kidId}/pvp/$matchId');
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kunne ikke åbne kampen endnu. Prøv igen om et øjeblik.')),
          );
        }
      } else {
        _loadInvitationsToMe();
      }
    } catch (e) {
      if (accept && mounted) {
        final matchId = await _waitForMatchId(invitationId);
        if (matchId != null && mounted) {
          context.go('/kid/spil/${widget.kidId}/pvp/$matchId');
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunne ikke acceptere: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadKids() async {
    final client = Supabase.instance.client;

    // Hent mit barns parent_id
    final myKidRes = await client
        .from('kids')
        .select('parent_id')
        .eq('id', widget.kidId)
        .maybeSingle();
    final parentId = myKidRes?['parent_id'];
    if (parentId == null) {
      setState(() {
        _kids = [];
        _loading = false;
      });
      return;
    }

    // Hent alle børn under samme forælder, undtagen mig selv
    final res = await client
        .from('kids')
        .select('id,name,avatar_url')
        .eq('parent_id', parentId)
        .neq('id', widget.kidId)
        .order('name');

    setState(() {
      _kids = (res as List).map((e) => Kid.fromJson(e)).toList();
      _loading = false;
    });
    _loadInvitationsToMe();
  }

  Future<void> _challengeKid(Kid kid) async {
    final client = Supabase.instance.client;

    // Maks 3 aktive spil (pending + i gang + computer)
    final pendingRes = await client
        .from('kid_match_invitations')
        .select('id')
        .eq('challenger_kid_id', widget.kidId)
        .eq('status', 'pending');
    final matchesRes = await client
        .from('kid_matches')
        .select('id,kid1_id,kid2_id')
        .eq('status', 'in_progress');
    final computerRes = await client
        .from('kid_computer_matches')
        .select('id')
        .eq('kid_id', widget.kidId)
        .eq('status', 'in_progress');
    final matchCount = (matchesRes as List)
        .where((m) =>
            m['kid1_id'] == widget.kidId || m['kid2_id'] == widget.kidId)
        .length;
    final total = (pendingRes as List).length + matchCount + (computerRes as List).length;
    if (total >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Afslut et spil før du kan oprette et nyt spil',
            ),
          ),
        );
      }
      return;
    }

    // Tjek om der allerede er en invitation fra mig til dem (alle status)
    final existing = await client
        .from('kid_match_invitations')
        .select('id,status')
        .eq('challenger_kid_id', widget.kidId)
        .eq('challenged_kid_id', kid.id)
        .maybeSingle();

    if (existing != null) {
      final status = existing['status'] as String?;
      if (status == 'pending' || status == 'declined') {
        await client
            .from('kid_match_invitations')
            .update({'status': 'pending'})
            .eq('id', existing['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${kid.name} er blevet udfordret. Du får besked når de svarer.')),
          );
          context.go('/kid/spil/${widget.kidId}');
        }
        return;
      }
      if (status == 'accepted') {
        final matchRes = await client
            .from('kid_matches')
            .select('id,status')
            .eq('invitation_id', existing['id'])
            .maybeSingle();
        final matchStatus = matchRes?['status'] as String?;
        final matchId = matchRes?['id'] as String?;
        if (matchStatus == 'in_progress' && matchId != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Du har allerede en kamp med ${kid.name}.')),
          );
          context.go('/kid/spil/${widget.kidId}/pvp/$matchId');
          return;
        }
        if (matchStatus == 'completed') {
          // Opret ny invitation i stedet for at genbruge gammel, så vi ikke
          // åbner en gammel afsluttet kamp.
          await client
              .from('kid_match_invitations')
              .delete()
              .eq('id', existing['id']);
          await client.from('kid_match_invitations').insert({
            'challenger_kid_id': widget.kidId,
            'challenged_kid_id': kid.id,
            'status': 'pending',
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${kid.name} er blevet udfordret. Du får besked når de svarer.')),
            );
            context.go('/kid/spil/${widget.kidId}');
          }
          return;
        }
        return;
      }
    }

    // Tjek om de allerede har udfordret mig – accepter/afvis øverst i stedet
    final invitationToMe = await client
        .from('kid_match_invitations')
        .select('id')
        .eq('challenger_kid_id', kid.id)
        .eq('challenged_kid_id', widget.kidId)
        .eq('status', 'pending')
        .maybeSingle();

    if (invitationToMe != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${kid.name} har allerede udfordret dig. Accepter eller afvis øverst.')),
        );
      }
      return;
    }

    try {
      await client.from('kid_match_invitations').insert({
        'challenger_kid_id': widget.kidId,
        'challenged_kid_id': kid.id,
        'status': 'pending',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke udfordre: $e')),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${kid.name} er blevet udfordret. Du får besked når de svarer.')),
      );
      context.go('/kid/spil/${widget.kidId}');
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
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.go('/kid/spil/${widget.kidId}'),
                      ),
                      Expanded(
                        child: Text(
                          'Udfordr en ven',
                          style: TextStyle(
                            fontSize: isTablet ? 28 : 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                if (_invitationsToMe.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Colors.amber.withValues(alpha: 0.2),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Du er blevet udfordret!',
                              style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            ..._invitationsToMe.map((inv) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${inv.challengerName} vil spille mod dig',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            _respondToInvitation(inv.id, false),
                                        child: const Text('Afvis'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            _respondToInvitation(inv.id, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        child: const Text('Accepter'),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : _kids.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'Ingen venner at udfordre.\nKun børn under samme forælder kan spille sammen.',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: GridView.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: isTablet ? 6 : 4,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                ),
                                itemCount: _kids.length,
                                itemBuilder: (_, i) {
                                  final kid = _kids[i];
                                  final isChallenged = _challengedKidId == kid.id;
                                  final isChallengingMe = _invitationsToMe
                                      .any((inv) => inv.challengerKidId == kid.id);
                                  return _VenCard(
                                    kid: kid,
                                    isChallenged: isChallenged,
                                    isChallengingMe: isChallengingMe,
                                    onTap: () => _challengeKid(kid),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: KidSessionNavButton(
              kidId: widget.kidId,
              fallbackLocation: '/kid/spil/${widget.kidId}',
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: const KidParentAdminCornerButton(),
          ),
        ],
      ),
    );
  }
}

class _VenCard extends StatelessWidget {
  final Kid kid;
  final bool isChallenged;
  final bool isChallengingMe;
  final VoidCallback onTap;

  const _VenCard({
    required this.kid,
    required this.isChallenged,
    required this.isChallengingMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF8B7355).withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: (isChallenged || isChallengingMe) ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isChallenged || isChallengingMe)
                  ? Colors.amber
                  : const Color(0xFFD4A853),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage:
                    kid.avatarUrl != null ? NetworkImage(kid.avatarUrl!) : null,
                child: kid.avatarUrl == null
                    ? const Icon(Icons.person, size: 36, color: Colors.white70)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                kid.name,
                style: const TextStyle(
                  color: Color(0xFFE8DCC8),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              if (isChallenged) ...[
                const SizedBox(height: 4),
                Text(
                  'Venter på svar...',
                  style: TextStyle(
                    color: Colors.amber.shade200,
                    fontSize: 11,
                  ),
                ),
              ],
              if (isChallengingMe && !isChallenged) ...[
                const SizedBox(height: 4),
                Text(
                  'Udfordrer dig!',
                  style: TextStyle(
                    color: Colors.amber.shade200,
                    fontSize: 11,
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
