import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/kid_parent_admin_corner.dart';

/// Bøger i én bibliotekgruppe (når barnet har > 6 bøger og forælder har oprettet grupper).
class KidLibraryGroupScreen extends StatefulWidget {
  const KidLibraryGroupScreen({
    super.key,
    required this.kidId,
    required this.groupId,
  });

  final String kidId;
  final String groupId;

  @override
  State<KidLibraryGroupScreen> createState() => _KidLibraryGroupScreenState();
}

class _KidLibraryGroupScreenState extends State<KidLibraryGroupScreen> {
  String? _groupName;
  List<Map<String, dynamic>> _books = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gRes = await Supabase.instance.client
          .from('shop_book_groups')
          .select('name')
          .eq('id', widget.groupId)
          .maybeSingle();
      if (gRes == null) {
        if (mounted) {
          setState(() {
            _error = 'Gruppe ikke fundet';
            _loading = false;
          });
        }
        return;
      }
      _groupName = gRes['name'] as String? ?? 'Gruppe';

      final itemsRes = await Supabase.instance.client
          .from('shop_book_group_items')
          .select('book_id, sort_order')
          .eq('group_id', widget.groupId)
          .order('sort_order');
      final bookIds = <String>[];
      for (final r in itemsRes as List) {
        bookIds.add(r['book_id'] as String);
      }
      if (bookIds.isEmpty) {
        if (mounted) {
          setState(() {
            _books = [];
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
      final order = {for (var i = 0; i < bookIds.length; i++) bookIds[i]: i};
      books.sort((a, b) => (order[a['id']] ?? 0).compareTo(order[b['id']] ?? 0));

      for (final b in books) {
        final pagesRes = await Supabase.instance.client
            .from('shop_book_pages')
            .select('right_image_url')
            .eq('book_id', b['id'])
            .eq('spread_index', 0)
            .maybeSingle();
        b['cover_url'] = pagesRes?['right_image_url'];
      }

      if (mounted) {
        setState(() {
          _books = books;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortest >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFF3E2723),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3E2723),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(_groupName ?? 'Gruppe'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(
              child: KidParentAdminCornerButton(size: 40),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFF9C433)),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
              : _books.isEmpty
                  ? const Center(
                      child: Text(
                        'Ingen bøger i gruppen',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isTablet ? 4 : 3,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _books.length,
                      itemBuilder: (context, i) {
                        final b = _books[i];
                        final id = b['id'] as String;
                        final title = b['title'] as String? ?? 'Bog';
                        final cover = b['cover_url'] as String?;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => context.push(
                              '/kid/library/${widget.kidId}/book/$id',
                            ),
                            borderRadius: BorderRadius.circular(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: cover != null && cover.isNotEmpty
                                        ? Image.network(
                                            cover,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _ph(title),
                                          )
                                        : _ph(title),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _ph(String title) {
    return ColoredBox(
      color: const Color(0xFF5D4037),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFF8E1), fontSize: 11),
          ),
        ),
      ),
    );
  }
}
