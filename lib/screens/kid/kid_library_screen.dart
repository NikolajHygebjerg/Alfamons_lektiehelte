import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/audio_cache_service.dart';
import 'kid_layout_constants.dart';
import 'widgets/kid_session_nav_button.dart';
import 'widgets/library_cabinet_background.dart';

/// Bibliotek – tegnet bogskab (hylder i kode), bøger på hylder.
class KidLibraryScreen extends StatefulWidget {
  final String kidId;

  const KidLibraryScreen({super.key, required this.kidId});

  @override
  State<KidLibraryScreen> createState() => _KidLibraryScreenState();
}

class _KidLibraryScreenState extends State<KidLibraryScreen> {
  /// Købte bøger (til tom-tilstand og gruppe-logik).
  List<Map<String, dynamic>> _purchasedBooks = [];
  /// Rækkefølge på hylderne: bog-map eller gruppe-tile `{'_kind':'group','id','name'}`.
  List<Map<String, dynamic>> _shelfItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
    unawaited(AudioCacheService.syncAll());
  }

  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    try {
      final kidRes = await Supabase.instance.client
          .from('kids')
          .select('parent_id')
          .eq('id', widget.kidId)
          .maybeSingle();
      final profileId = kidRes?['parent_id'] as String?;
      if (profileId == null) {
        if (mounted) {
          setState(() {
            _purchasedBooks = [];
            _shelfItems = [];
            _loading = false;
          });
        }
        return;
      }

      List<String> bookIds = [];
      try {
        final purchasesRes = await Supabase.instance.client
            .from('shop_book_purchases')
            .select('book_id')
            .eq('profile_id', profileId);
        for (final p in purchasesRes as List) {
          bookIds.add(p['book_id'] as String);
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _purchasedBooks = [];
            _shelfItems = [];
            _loading = false;
          });
        }
        return;
      }

      if (bookIds.isEmpty) {
        if (mounted) {
          setState(() {
            _purchasedBooks = [];
            _shelfItems = [];
            _loading = false;
          });
        }
        return;
      }

      final booksRes = await Supabase.instance.client
          .from('shop_books')
          .select('id, title')
          .inFilter('id', bookIds);
      final books = (booksRes as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final b in books) {
        final pagesRes = await Supabase.instance.client
            .from('shop_book_pages')
            .select('right_image_url')
            .eq('book_id', b['id'])
            .eq('spread_index', 0)
            .maybeSingle();
        b['cover_url'] = pagesRes?['right_image_url'];
      }

      final purchaseOrder = <String, int>{
        for (var i = 0; i < bookIds.length; i++) bookIds[i]: i,
      };
      books.sort((a, b) => (purchaseOrder[a['id']] ?? 0)
          .compareTo(purchaseOrder[b['id']] ?? 0));

      List<Map<String, dynamic>> shelfItems = List.from(books);

      if (books.length > 6) {
        try {
          final groupsRes = await Supabase.instance.client
              .from('shop_book_groups')
              .select('id, name, sort_order')
              .eq('profile_id', profileId)
              .order('sort_order');
          final groups = (groupsRes as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final groupIds = groups.map((g) => g['id'] as String).toList();

          final itemsRes = groupIds.isEmpty
              ? <dynamic>[]
              : await Supabase.instance.client
                  .from('shop_book_group_items')
                  .select('group_id, book_id, sort_order')
                  .inFilter('group_id', groupIds)
                  .order('sort_order');

          final booksInAnyGroup = <String>{};
          final itemsByGroup = <String, List<Map<String, dynamic>>>{};
          for (final g in groups) {
            itemsByGroup[g['id'] as String] = [];
          }
          for (final row in itemsRes) {
            final m = Map<String, dynamic>.from(row as Map);
            final gid = m['group_id'] as String;
            if (!itemsByGroup.containsKey(gid)) continue;
            final bid = m['book_id'] as String;
            booksInAnyGroup.add(bid);
            itemsByGroup[gid]!.add(m);
          }

          shelfItems = [];
          for (final g in groups) {
            final gid = g['id'] as String;
            final itemRows = itemsByGroup[gid] ?? [];
            if (itemRows.isEmpty) continue;
            shelfItems.add({
              '_kind': 'group',
              'id': gid,
              'name': g['name'] as String? ?? 'Gruppe',
            });
          }
          for (final b in books) {
            final id = b['id'] as String;
            if (!booksInAnyGroup.contains(id)) {
              shelfItems.add(b);
            }
          }
        } catch (_) {
          shelfItems = List.from(books);
        }
      }

      if (mounted) {
        setState(() {
          _purchasedBooks = books;
          _shelfItems = shelfItems;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _purchasedBooks = [];
          _shelfItems = [];
          _loading = false;
        });
      }
    }
  }

  /// Op til 2 pr. hylde (større forsider), fylder fra oven; overskud på nederste hylde.
  List<List<Map<String, dynamic>>> _itemsOnCabinetShelves() {
    const maxPerShelf = 2;
    final n = LibraryCabinetShelfLayout.shelfCount;
    if (_shelfItems.isEmpty) {
      return List.generate(n, (_) => <Map<String, dynamic>>[]);
    }
    final rows = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < _shelfItems.length; i += maxPerShelf) {
      rows.add(
        _shelfItems.sublist(
          i,
          math.min(i + maxPerShelf, _shelfItems.length),
        ),
      );
    }
    if (rows.length > n) {
      final overflow = <Map<String, dynamic>>[];
      for (var r = n - 1; r < rows.length; r++) {
        overflow.addAll(rows[r]);
      }
      rows.removeRange(n, rows.length);
      rows[n - 1] = [...rows[n - 1], ...overflow];
    }
    while (rows.length < n) {
      rows.add([]);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortestSide >= 600;
    final topPad = MediaQuery.paddingOf(context).top;
    final screenSize = MediaQuery.sizeOf(context);
    final showBookOverlay = !_loading && _shelfItems.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF3E2723),
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/alfamonbaggrund.svg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Center(
            child: SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: Transform.scale(
                scale: 0.8,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    const LibraryCabinetBackground(showWallBackdrop: false),
                    if (showBookOverlay)
                      _BogskabShelfOverlay(
                        maxWidth: screenSize.width,
                        maxHeight: screenSize.height,
                        kidId: widget.kidId,
                        booksPerShelf: _itemsOnCabinetShelves(),
                        isTablet: isTablet,
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Let mørkning øverst så titel og knap læses bedre
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPad + 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    kidZoneHorizontalPadding + 52,
                    8,
                    kidZoneHorizontalPadding,
                    4,
                  ),
                  child: Text(
                    'Bibliotek',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTablet ? 26 : 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: IgnorePointer(
                    ignoring: showBookOverlay,
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFF9C433),
                            ),
                          )
                        : _purchasedBooks.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.menu_book,
                                            size: 56,
                                            color: Colors.white70,
                                          ),
                                          SizedBox(height: 12),
                                          Text(
                                            'Ingen bøger endnu.\nForældre kan købe bøger i Bogbutik.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const ColoredBox(
                                color: Colors.transparent,
                                child: SizedBox.expand(),
                              ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: kidZoneHorizontalPadding,
            child: KidSessionNavButton(kidId: widget.kidId),
          ),
        ],
      ),
    );
  }
}

/// Hylder matchet til [LibraryCabinetShelfLayout.shelfBands] og [LibraryCabinetBackground].
/// Brøkdele er af fuld skærmhøjde; børnene ligger i båndet med bund ved hyldelinjen.
class _BogskabShelfOverlay extends StatelessWidget {
  const _BogskabShelfOverlay({
    required this.maxWidth,
    required this.maxHeight,
    required this.kidId,
    required this.booksPerShelf,
    required this.isTablet,
  });

  final double maxWidth;
  final double maxHeight;
  final String kidId;
  final List<List<Map<String, dynamic>>> booksPerShelf;
  final bool isTablet;

  static const double _coverAspect = 1.42;

  /// Samme som planke-kant i [_LibraryCabinetPainter]: ramme + 12px.
  static double _sideInset(double w) =>
      (w * 0.055).clamp(12.0, 48.0) + 12.0;

  @override
  Widget build(BuildContext context) {
    if (maxHeight <= 1 || maxWidth <= 1) {
      return const SizedBox.shrink();
    }

    final inset = _sideInset(maxWidth);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var s = 0;
            s < booksPerShelf.length &&
                s < LibraryCabinetShelfLayout.shelfBands.length;
            s++)
          Positioned(
            left: inset,
            right: inset,
            top: maxHeight *
                LibraryCabinetShelfLayout.shelfBands[s].top.clamp(
                  0.0,
                  0.92,
                ),
            height: maxHeight *
                (LibraryCabinetShelfLayout.shelfBands[s].bottom -
                    LibraryCabinetShelfLayout.shelfBands[s].top),
            child: _CabinetShelfRow(
              shelfBooks: booksPerShelf[s],
              kidId: kidId,
              isTablet: isTablet,
              coverAspect: _coverAspect,
              overlayOnArtwork: true,
              overlayLayoutWidthSlots: 2,
            ),
          ),
      ],
    );
  }
}

/// Én hylde – enten i overlay mod [bogskabbaggrund] eller tidligere skabs-layout.
class _CabinetShelfRow extends StatelessWidget {
  const _CabinetShelfRow({
    required this.shelfBooks,
    required this.kidId,
    required this.isTablet,
    required this.coverAspect,
    this.overlayOnArtwork = false,
    this.overlayLayoutWidthSlots,
  });

  final List<Map<String, dynamic>> shelfBooks;
  final String kidId;
  final bool isTablet;
  final double coverAspect;
  final bool overlayOnArtwork;
  /// Når sat (fx 3): bredden af hvert element som om der er så mange pladser på hylden.
  final int? overlayLayoutWidthSlots;

  static ({double bookW, double bookH, double titleH, double gap})
      _layoutForRow({
    required double innerW,
    required double rowMaxHeight,
    required int bookCount,
    required bool isTablet,
    required double coverAspect,
    bool captionBelow = true,
    int? widthSlots,
    double bookScaleFactor = 1.95,
    double widthCapFraction = 0.364,
  }) {
    final gap = isTablet ? 8.0 : 5.0;
    if (bookCount <= 0 || innerW <= 0 || rowMaxHeight <= 0) {
      return (bookW: 48.0, bookH: 48.0, titleH: 0.0, gap: gap);
    }

    final slotCount = math.max(1, widthSlots ?? bookCount);

    var titleH = captionBelow
        ? (rowMaxHeight * 0.24).clamp(10.0, 22.0)
        : 0.0;
    const verticalPad = 4.0;
    var maxBodyH = rowMaxHeight - titleH - verticalPad;
    if (maxBodyH < 6) {
      titleH = math.max(0.0, rowMaxHeight - verticalPad - 8);
      maxBodyH = math.max(4.0, rowMaxHeight - titleH - verticalPad);
    }

    final fromRow = (innerW - (slotCount - 1) * gap) / slotCount;
    final capW = math.min(
      innerW * widthCapFraction,
      rowMaxHeight * coverAspect * 0.92,
    );
    var bookW = math.min(fromRow, capW);
    var bookH = math.min(bookW * coverAspect, maxBodyH);
    bookW = bookH / coverAspect;

    var needW = slotCount * bookW + (slotCount - 1) * gap;
    if (needW > innerW + 0.5) {
      bookW = (innerW - (slotCount - 1) * gap) / slotCount;
      bookH = math.min(bookW * coverAspect, maxBodyH);
      bookW = bookH / coverAspect;
    }

    const minBookW = 30.0;
    if (bookW < minBookW) {
      final hAtMin = minBookW * coverAspect;
      if (hAtMin <= maxBodyH) {
        bookW = minBookW;
        bookH = hAtMin;
      } else {
        bookH = maxBodyH;
        bookW = bookH / coverAspect;
      }
    }

    bookW *= bookScaleFactor;
    bookH *= bookScaleFactor;
    bookH = math.min(bookH, maxBodyH);
    bookW = bookH / coverAspect;
    var totalW = bookCount * bookW + (bookCount - 1) * gap;
    if (totalW > innerW + 0.5) {
      bookW = (innerW - (bookCount - 1) * gap) / bookCount;
      bookH = math.min(bookW * coverAspect, maxBodyH);
      bookW = bookH / coverAspect;
    }

    return (bookW: bookW, bookH: bookH, titleH: titleH, gap: gap);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final innerW = c.maxWidth;
        final rowH = c.maxHeight;
        final n = shelfBooks.length;

        if (n == 0) {
          return overlayOnArtwork
              ? const SizedBox.expand()
              : ColoredBox(
                  color: const Color(0xFF4E342E).withValues(alpha: 0.25),
                  child: const Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(height: 3, width: double.infinity),
                  ),
                );
        }

        final layout = _layoutForRow(
          innerW: innerW,
          rowMaxHeight: rowH,
          bookCount: n,
          isTablet: isTablet,
          coverAspect: coverAspect,
          captionBelow: !overlayOnArtwork,
          widthSlots: overlayOnArtwork ? overlayLayoutWidthSlots : null,
          bookScaleFactor: overlayOnArtwork ? 2.45 : 1.95,
          widthCapFraction: overlayOnArtwork ? 0.48 : 0.364,
        );

        final need =
            n * layout.bookW + (n > 0 ? (n - 1) * layout.gap : 0);
        final overflowW = need > innerW + 0.5;

        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: layout.gap),
              _ShelfBookTile(
                item: shelfBooks[i],
                kidId: kidId,
                width: layout.bookW,
                height: layout.bookH,
                titleStripHeight: layout.titleH,
                titleFontSize: (layout.bookW * 0.2).clamp(7.0, 12.0),
                showCaptionBelow: !overlayOnArtwork,
              ),
            ],
          ],
        );

        final scroll = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.only(
            left: 4,
            right: 4,
            bottom: overlayOnArtwork ? 4 : 2,
          ),
          physics: overflowW
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: row,
        );

        if (overlayOnArtwork) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: scroll,
          );
        }

        return DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF5D4037), width: 5),
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: scroll,
          ),
        );
      },
    );
  }
}

class _ShelfBookTile extends StatelessWidget {
  const _ShelfBookTile({
    required this.item,
    required this.kidId,
    required this.width,
    required this.height,
    required this.titleStripHeight,
    required this.titleFontSize,
    this.showCaptionBelow = true,
  });

  final Map<String, dynamic> item;
  final String kidId;
  final double width;
  final double height;
  final double titleStripHeight;
  final double titleFontSize;
  final bool showCaptionBelow;

  bool get _isGroup => item['_kind'] == 'group';

  @override
  Widget build(BuildContext context) {
    final id = item['id'] as String;
    final title = _isGroup
        ? (item['name'] as String? ?? 'Gruppe')
        : (item['title'] as String? ?? 'Bog');
    final coverUrl =
        _isGroup ? null : (item['cover_url'] as String?);

    final inner = _isGroup
        ? ColoredBox(
            color: const Color(0xFF6D4C41),
            child: Center(
              child: Icon(
                Icons.folder_special_rounded,
                size: (width * 0.55).clamp(22.0, 48.0),
                color: const Color(0xFFFFF8E1),
              ),
            ),
          )
        : (coverUrl != null && coverUrl.isNotEmpty
            ? ColoredBox(
                color: const Color(0xFF4E342E),
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.contain,
                  width: width,
                  height: height,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => _bookFallback(title),
                ),
              )
            : _bookFallback(title));

    final tile = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 6,
                    offset: Offset(3, 4),
                  ),
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(-1, 0),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFF4E342E),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: inner,
              ),
            ),
          ),
          if (showCaptionBelow && titleStripHeight > 0)
            SizedBox(
              height: titleStripHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width + 8),
                  child: Text(
                    title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.05,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    void onTap() {
      if (_isGroup) {
        context.push('/kid/library/$kidId/group/$id');
      } else {
        context.push('/kid/library/$kidId/book/$id');
      }
    }

    final ink = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: showCaptionBelow
          ? tile
          : Semantics(
              label: title,
              button: true,
              child: tile,
            ),
    );

    return Material(
      color: Colors.transparent,
      child: showCaptionBelow
          ? ink
          : Tooltip(
              message: title,
              preferBelow: false,
              child: ink,
            ),
    );
  }

  Widget _bookFallback(String title) {
    return ColoredBox(
      color: const Color(0xFF5D4037),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            title,
            maxLines: 4,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFF8E1),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
