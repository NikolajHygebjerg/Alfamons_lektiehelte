import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'kid_layout_constants.dart';
import 'kid_today_hit_regions.dart';
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

  @override
  void initState() {
    super.initState();
    _loadGold();
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
              onTap: () => context.push('/trace'),
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
                  if (mounted) _loadGold();
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
                onTap: () async {
                  await context.push('/kid/library/${widget.kidId}');
                  if (mounted) _loadGold();
                },
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
                  if (mounted) _loadGold();
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
            right: kidZoneHorizontalPadding,
            bottom: isPhone ? 0 : (bottomInset > 0 ? bottomInset : 4),
            child: isPhone
                ? SafeArea(
                    top: false,
                    left: false,
                    right: false,
                    bottom: true,
                    minimum: EdgeInsets.zero,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          await context.push('/kid/alfamons/${widget.kidId}');
                          if (mounted) _loadGold();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: _loadingGold
                            ? const SizedBox(
                                width: 80,
                                height: 100,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : KidGoldTreasuryCorner(goldCoins: _goldCoins),
                      ),
                    ),
                  )
                : Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await context.push('/kid/alfamons/${widget.kidId}');
                        if (mounted) _loadGold();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: _loadingGold
                          ? const SizedBox(
                              width: 80,
                              height: 100,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : KidGoldTreasuryCorner(goldCoins: _goldCoins),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
