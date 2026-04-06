import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/kid_invitation_service.dart';
import '../services/notification_service.dart';
import '../widgets/challenge_notification_dialog.dart';

/// Håndterer udfordrings-notifikationer når brugeren trykker på en iPad-notifikation.
class PendingChallengeHandler extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const PendingChallengeHandler({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<PendingChallengeHandler> createState() => _PendingChallengeHandlerState();
}

class _PendingChallengeHandlerState extends State<PendingChallengeHandler>
    with WidgetsBindingObserver {
  bool _handlingPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await KidInvitationService.refreshPendingForCurrentKid();
      await _checkPending();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await KidInvitationService.refreshPendingForCurrentKid();
        await _checkPending();
      });
    }
  }

  Future<void> _checkPending() async {
    if (kIsWeb) return;
    if (_handlingPending || !mounted) return;
    final pending = NotificationService.peekPendingChallenge();
    if (pending == null) return;
    _handlingPending = true;

    try {
      final initialCtx = widget.navigatorKey.currentContext;
      if (initialCtx == null || !initialCtx.mounted) return;

      final kidRes = await Supabase.instance.client
          .from('kids')
          .select('name,avatar_url')
          .eq('id', pending.challengerKidId)
          .maybeSingle();

      final name = kidRes?['name'] as String? ?? 'Nogen';
      final avatarUrl = kidRes?['avatar_url'] as String?;

      if (!initialCtx.mounted) return;
      initialCtx.go('/kid/today/${pending.kidId}');

      await Future.delayed(const Duration(milliseconds: 100));
      final ctx = widget.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      await ChallengeNotificationDialog.show(
        ctx,
        kidId: pending.kidId,
        invitationId: pending.invitationId,
        challengerKidId: pending.challengerKidId,
        challengerName: name,
        challengerAvatarUrl: avatarUrl,
      );
      NotificationService.clearPendingChallenge();
    } finally {
      _handlingPending = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
