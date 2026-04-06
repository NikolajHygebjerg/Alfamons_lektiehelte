import 'dart:async';

import 'package:alfamon_trace/alfamon_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/task_completion_service.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'kid_layout_constants.dart';
import 'kid_library_screen.dart' show kidLibraryIntroAsset;
import 'kid_today_hit_regions.dart';
import 'widgets/gold_coins_earned_overlay.dart';
import 'widgets/kid_gold_treasury_corner.dart';
import 'widgets/kid_session_nav_button.dart';

/// Barnets hjem – [baggrund.svg]. Trykflader: [KidTodayHitRegions] i design-rum 1200×895.
class KidTodayScreen extends StatefulWidget {
  const KidTodayScreen({super.key, required this.kidId});

  final String kidId;

  @override
  State<KidTodayScreen> createState() => _KidTodayScreenState();
}

class _KidTodayScreenState extends State<KidTodayScreen> {
  int _goldCoins = 0;
  bool _loadingGold = true;
  final AudioPlayer _libraryIntroPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    unawaited(_loadGold());
  }

  Future<void> _refreshAfterKidRoute() async {
    await _loadGold();
  }

  @override
  void dispose() {
    unawaited(_libraryIntroPlayer.dispose());
    super.dispose();
  }

  Future<void> _playLibraryIntroFromHomeTap() async {
    try {
      await _libraryIntroPlayer.stop();
      await _libraryIntroPlayer.setAudioSource(
        AudioSource.asset(kidLibraryIntroAsset),
        preload: true,
      );
      await _libraryIntroPlayer.play();
    } catch (e, st) {
      debugPrint(
        'KidTodayScreen: kunne ikke afspille $kidLibraryIntroAsset: $e\n$st',
      );
    }
  }

  Future<void> _openLibrary() async {
    unawaited(_playLibraryIntroFromHomeTap());
    await context.push(
      '/kid/library/${widget.kidId}',
      extra: true,
    );
    if (mounted) await _refreshAfterKidRoute();
  }

  Future<void> _openTrace() async {
    final container = ProviderScope.containerOf(context);
    // Gem evt. guldmønter fra sidste gang (fx ved netværksfejl), så de ikke nulstilles.
    if (container.read(traceSessionCoinsEarnedProvider) >= 1) {
      await _settleTraceRewards();
      if (!mounted) return;
      if (container.read(traceSessionCoinsEarnedProvider) >= 1) return;
    }
    container.read(traceSessionAwardedLetterIdsProvider.notifier).state = {};
    await context.push('/kid/trace/${widget.kidId}');
    if (!mounted) return;
    await _settleTraceRewards();
    if (mounted) await _refreshAfterKidRoute();
  }

  Future<void> _settleTraceRewards() async {
    final container = ProviderScope.containerOf(context);
    final earned = container.read(traceSessionCoinsEarnedProvider);
    if (earned < 1) return;
    try {
      await TaskCompletionService.addAlphabetTraceGold(widget.kidId, earned);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke gemme guldmønter: $e')),
        );
      }
      return;
    }
    container.read(traceSessionCoinsEarnedProvider.notifier).state = 0;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoldCoinsEarnedOverlay(amount: earned),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5A1A0D),
                minimumSize: const Size(220, 48),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadGold() async {
    final goldRes = await Supabase.instance.client
        .from('kids')
        .select('gold_coins')
        .eq('id', widget.kidId)
        .maybeSingle();
    final gold = (goldRes?['gold_coins'] as num?)?.toInt() ?? 0;
    if (mounted) {
      setState(() {
        _goldCoins = gold;
        _loadingGold = false;
      });
    }
  }

  static Widget _region(
    Rect designRect,
    Size screenSize,
    Widget child,
  ) {
    final r = kidTodayMapDesignRectToScreen(designRect, screenSize);
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: child,
    );
  }

  /// Diplom-knap til venstre for skattekisten — åbner opgave-skærmen.
  Widget _diplomTasksButton(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final h = (screenW * 0.22).clamp(72.0, 120.0);

    return Semantics(
      button: true,
      label: 'Opgaver',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await context.push('/kid/tasks/${widget.kidId}');
            if (mounted) await _refreshAfterKidRoute();
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
            child: Image.asset(
              'assets/diplom.png',
              height: h,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => SizedBox(
                height: h,
                width: h * 0.75,
                child: Icon(
                  Icons.workspace_premium,
                  size: h * 0.55,
                  color: const Color(0xFFF9C433),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _treasuryAndDiplomaRow(bool isPhone) {
    Future<void> openAlfamonsFromTreasury() async {
      await context.push('/kid/alfamons/${widget.kidId}');
      if (mounted) await _refreshAfterKidRoute();
    }

    final treasury = _loadingGold
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: openAlfamonsFromTreasury,
              child: const SizedBox(
                width: 80,
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          )
        : KidGoldTreasuryCorner(
            kidId: widget.kidId,
            goldCoins: _goldCoins,
            onAfterAlfamonsRoute: _refreshAfterKidRoute,
          );

    // [KidGoldTreasuryCorner]: kistebillede derefter mønttal — vi flugter diplom
    // med kistens visuelle bund (løftes fra Row.end som ellers flugter med tekst).
    final sh = MediaQuery.sizeOf(context).height;
    final lift = (sh * 0.055).clamp(44.0, 58.0);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Transform.translate(
          offset: Offset(-10, -lift),
          child: _diplomTasksButton(context),
        ),
        const SizedBox(width: 2),
        treasury,
      ],
    );

    if (isPhone) {
      return SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        minimum: EdgeInsets.zero,
        child: row,
      );
    }
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topPad = MediaQuery.paddingOf(context).top;
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;
    final isPhone = shortest < 600;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/baggrund.svg',
              fit: BoxFit.cover,
            ),
          ),
          _region(
            KidTodayHitRegions.trace,
            size,
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_openTrace()),
              child: const SizedBox.expand(),
            ),
          ),
          _region(
            KidTodayHitRegions.spil,
            size,
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  await context.push('/kid/spil/${widget.kidId}');
                  if (mounted) await _refreshAfterKidRoute();
                },
                splashColor: Colors.white24,
                highlightColor: Colors.white10,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _region(
            KidTodayHitRegions.library,
            size,
            Material(
              color: Colors.transparent,
              child: InkWell(
                splashColor: Colors.white24,
                highlightColor: Colors.white10,
                onTap: () => unawaited(_openLibrary()),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _region(
            KidTodayHitRegions.math,
            size,
            Material(
              color: Colors.transparent,
              child: InkWell(
                splashColor: Colors.white24,
                highlightColor: Colors.white10,
                onTap: () async {
                  await context.push('/kid/math/${widget.kidId}');
                  if (mounted) await _refreshAfterKidRoute();
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            top: topPad + 8,
            left: kidZoneHorizontalPadding,
            child: KidSessionNavButton(
              kidId: widget.kidId,
              isHome: true,
            ),
          ),
          Positioned(
            top: topPad + 8,
            right: kidZoneHorizontalPadding,
            child: const KidParentAdminCornerButton(),
          ),
          Positioned(
            right: kidZoneHorizontalPadding,
            bottom: isPhone ? 0 : (bottomInset > 0 ? bottomInset : 4),
            child: _treasuryAndDiplomaRow(isPhone),
          ),
        ],
      ),
    );
  }
}
