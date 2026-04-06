import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Efter login: **Web** → kun forælder-admin (`/admin`).
/// **Mobil/tablet/desktop-app**: automatisk til barn-valg hvis der findes børn, ellers admin.
/// Voksen-adgang fra barnesider: **hjørneikon** + forældrekode (ikke denne skærm).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_routeAfterAuth());
    });
  }

  Future<void> _routeAfterAuth() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (!mounted) return;
    if (user == null) {
      context.go('/auth');
      return;
    }

    if (kIsWeb) {
      if (!mounted) return;
      context.go('/admin');
      return;
    }

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    final parentId = profile?['id'] as String?;

    if (!mounted) return;
    if (parentId == null) {
      context.go('/admin');
      return;
    }

    final kidsProbe = await Supabase.instance.client
        .from('kids')
        .select('id')
        .eq('parent_id', parentId)
        .limit(1);

    if (!mounted) return;
    final hasKids = (kidsProbe as List).isNotEmpty;
    if (hasKids) {
      context.go('/kid/select');
    } else {
      context.go('/admin');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF9C433),
        ),
      ),
    );
  }
}
