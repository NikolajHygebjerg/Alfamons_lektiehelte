import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'kid_layout_constants.dart';
import 'widgets/kid_gold_treasury_corner.dart';
import 'widgets/kid_session_nav_button.dart';

/// Trykflader oven på [baggrund.svg] (0–1 af skærm): justér ved visuel test mod illustrationen.
const double _owlLibraryLeft = 0.02;
const double _owlLibraryTop = 0.08;
const double _owlLibraryW = 0.30;
const double _owlLibraryH = 0.44;

const double _birdMathLeft = 0.33;
const double _birdMathTop = 0.48;
const double _birdMathW = 0.34;
const double _birdMathH = 0.36;

/// Barnets hjem – [baggrund.svg], to zoner (opgaver / spil), kiste → Alfamons.
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
          // Venstre: bjørn m.m. – ingen destination lige nu (ugle/fugl ligger ovenpå).
          Positioned(
            left: 0,
            top: size.height * 0.06,
            width: size.width * 0.5,
            height: size.height * 0.78,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
            ),
          ),
          // Zone: spil / kort (højre)
          Positioned(
            right: 0,
            top: size.height * 0.06,
            width: size.width * 0.5,
            height: size.height * 0.78,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  await context.push('/kid/spil/${widget.kidId}');
                  if (mounted) _loadGold();
                },
                splashColor: Colors.white24,
                highlightColor: Colors.white10,
              ),
            ),
          ),
          // Ugle → bibliotek; fugl → matematik (oven på venstre/højre zoner).
          Positioned(
            left: size.width * _owlLibraryLeft,
            top: size.height * _owlLibraryTop,
            width: size.width * _owlLibraryW,
            height: size.height * _owlLibraryH,
            child: Material(
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
          Positioned(
            left: size.width * _birdMathLeft,
            top: size.height * _birdMathTop,
            width: size.width * _birdMathW,
            height: size.height * _birdMathH,
            child: Material(
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
