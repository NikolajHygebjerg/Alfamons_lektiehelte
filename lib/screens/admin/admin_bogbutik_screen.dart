import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

/// Bogbutik – forældre kan købe Læs-let bøger.
/// Forberedt til in-app køb, priser sættes til 0 kr indtil videre.
class AdminBogbutikScreen extends StatefulWidget {
  const AdminBogbutikScreen({super.key});

  @override
  State<AdminBogbutikScreen> createState() => _AdminBogbutikScreenState();
}

class _AdminBogbutikScreenState extends State<AdminBogbutikScreen> {
  List<Map<String, dynamic>> _books = [];
  Set<String> _ownedBookIds = {};
  List<Map<String, dynamic>> _libraryGroups = [];
  /// Hver bog kan kun være i én gruppe ad gangen (seneste tildeling vinder).
  Map<String, String?> _bookIdToGroupId = {};
  String? _profileId;
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
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() { _error = 'Log ind for at se bogbutikken'; _loading = false; });
        return;
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('auth_user_id', user.id)
          .maybeSingle();
      _profileId = profile?['id'] as String?;

      List<Map<String, dynamic>> books;
      try {
        final booksRes = await Supabase.instance.client
            .from('shop_books')
            .select('id, title, price_kr')
            .order('updated_at', ascending: false);
        books = (booksRes as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        final booksRes = await Supabase.instance.client
            .from('shop_books')
            .select('id, title')
            .order('updated_at', ascending: false);
        books = (booksRes as List<dynamic>)
            .map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              m['price_kr'] = 0;
              return m;
            })
            .toList();
      }

      final booksList = books;

      for (final b in booksList) {
        final pagesRes = await Supabase.instance.client
            .from('shop_book_pages')
            .select('right_image_url')
            .eq('book_id', b['id'])
            .eq('spread_index', 0)
            .maybeSingle();
        b['cover_url'] = pagesRes?['right_image_url'];
      }

      Set<String> owned = {};
      if (_profileId != null) {
        try {
          final purchasesRes = await Supabase.instance.client
              .from('shop_book_purchases')
              .select('book_id')
              .eq('profile_id', _profileId!);
          for (final p in purchasesRes as List) {
            owned.add(p['book_id'] as String);
          }
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST205') {
            debugPrint('shop_book_purchases findes ikke – kør migration 20250319000000_shop_books_price_purchases.sql');
          } else {
            rethrow;
          }
        }
      }

      var groups = <Map<String, dynamic>>[];
      final bookToGroup = <String, String?>{};
      if (_profileId != null) {
        try {
          final grRes = await Supabase.instance.client
              .from('shop_book_groups')
              .select('id, name, sort_order')
              .eq('profile_id', _profileId!)
              .order('sort_order');
          groups = (grRes as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          if (groups.isNotEmpty) {
            final gids =
                groups.map((g) => g['id'] as String).toList();
            final itemsRes = await Supabase.instance.client
                .from('shop_book_group_items')
                .select('group_id, book_id')
                .inFilter('group_id', gids);
            for (final row in itemsRes as List) {
              final m = row as Map<String, dynamic>;
              bookToGroup[m['book_id'] as String] = m['group_id'] as String;
            }
          }
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST205') {
            debugPrint(
              'shop_book_groups findes ikke – kør migration 20260312120000_shop_book_groups.sql',
            );
          } else {
            rethrow;
          }
        }
      }

      if (mounted) {
        setState(() {
          _books = booksList;
          _ownedBookIds = owned;
          _libraryGroups = groups;
          _bookIdToGroupId = bookToGroup;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _purchaseBook(String bookId) async {
    if (_profileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunne ikke finde din profil')),
      );
      return;
    }
    if (_ownedBookIds.contains(bookId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Du ejer allerede denne bog')),
      );
      return;
    }

    try {
      await Supabase.instance.client.from('shop_book_purchases').insert({
        'profile_id': _profileId!,
        'book_id': bookId,
      });
      if (mounted) {
        setState(() => _ownedBookIds = {..._ownedBookIds, bookId});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bog købt – den er nu i dit bibliotek')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.code == 'PGRST205'
            ? 'Køb ikke tilgængeligt endnu. Kør migration 20250319000000_shop_books_price_purchases.sql i Supabase SQL Editor.'
            : 'Køb fejlede: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Køb fejlede: $e')),
        );
      }
    }
  }

  Future<void> _createLibraryGroup() async {
    if (_profileId == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny bibliotek-gruppe'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Navn',
            hintText: 'Fx Eventyr',
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuller'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Opret'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await Supabase.instance.client.from('shop_book_groups').insert({
        'profile_id': _profileId!,
        'name': name,
        'sort_order': _libraryGroups.length,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppe oprettet')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke oprette gruppe: $e')),
        );
      }
    }
  }

  Future<void> _renameLibraryGroup(String groupId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Omdøb gruppe'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Navn'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuller'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Gem'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('shop_book_groups')
          .update({'name': name})
          .eq('id', groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navn opdateret')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  Future<void> _deleteLibraryGroup(String groupId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet gruppe?'),
        content: const Text(
          'Bøgerne fjernes fra gruppen men forbliver købt. '
          'Du kan tildele dem en anden gruppe bagefter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuller'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('shop_book_groups')
          .delete()
          .eq('id', groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppe slettet')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  Future<void> _assignBookToLibraryGroup(String bookId, String? groupId) async {
    final myGroupIds = _libraryGroups.map((g) => g['id'] as String).toList();
    try {
      if (myGroupIds.isNotEmpty) {
        await Supabase.instance.client
            .from('shop_book_group_items')
            .delete()
            .eq('book_id', bookId)
            .inFilter('group_id', myGroupIds);
      }
      if (groupId != null) {
        await Supabase.instance.client.from('shop_book_group_items').insert({
          'group_id': groupId,
          'book_id': bookId,
          'sort_order': 0,
        });
      }
      if (mounted) {
        setState(() {
          if (groupId == null) {
            _bookIdToGroupId.remove(bookId);
          } else {
            _bookIdToGroupId[bookId] = groupId;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke gemme gruppe: $e')),
        );
      }
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'Gratis';
    final p = price is num ? price.toDouble() : double.tryParse(price.toString()) ?? 0.0;
    if (p <= 0) return 'Gratis';
    return '${p.toStringAsFixed(0)} kr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bogbutik'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin'),
        ),
        actions: [
          const AdminMenuToolbarButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Prøv igen'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5A1A0D), Color(0xFFE85A4A)],
        ),
      ),
      child: _books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book, size: 64, color: Colors.white70),
                    const SizedBox(height: 16),
                    const Text(
                      'Ingen bøger i butikken endnu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final b = _books[i];
                        final id = b['id'] as String;
                        final title = b['title'] as String? ?? 'Uden titel';
                        final coverUrl = b['cover_url'] as String?;
                        final price = b['price_kr'];
                        final owned = _ownedBookIds.contains(id);

                        return Card(
                          color: const Color(0xFFF9C433)
                              .withValues(alpha: 0.9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: coverUrl != null && coverUrl.isNotEmpty
                                    ? Image.network(
                                        coverUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                          child: Icon(Icons.menu_book,
                                              size: 48),
                                        ),
                                      )
                                    : const Center(
                                        child: Icon(Icons.menu_book,
                                            size: 48),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatPrice(price),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF5A1A0D),
                                          ),
                                        ),
                                        if (owned)
                                          const Text(
                                            'Ejet',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        else
                                          FilledButton(
                                            onPressed: () => _purchaseBook(id),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF5A1A0D),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                            ),
                                            child: const Text('Køb'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _books.length,
                    ),
                  ),
                ),
                if (_ownedBookIds.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _buildLibraryGroupsSection()),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }

  Widget _buildLibraryGroupsSection() {
    final ownedBooks = _books
        .where((b) => _ownedBookIds.contains(b['id'] as String))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Card(
        color: Colors.white.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_special, color: Color(0xFF5A1A0D)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _ownedBookIds.length > 6
                          ? 'Bibliotek-grupper'
                          : 'Bibliotek-grupper (valgfrit)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A1A0D),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Når barnet har mere end seks bøger, vises grupper som mapper '
                'på boghylden. Opret grupper her og fordel jeres købte bøger.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.brown.shade800,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _createLibraryGroup,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Ny gruppe'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5A1A0D),
                ),
              ),
              if (_libraryGroups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Ingen grupper endnu.',
                    style: TextStyle(color: Colors.brown.shade600),
                  ),
                )
              else
                ..._libraryGroups.map((g) {
                  final gid = g['id'] as String;
                  final name = g['name'] as String? ?? 'Gruppe';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder),
                    title: Text(name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _renameLibraryGroup(gid, name),
                          tooltip: 'Omdøb',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteLibraryGroup(gid),
                          tooltip: 'Slet',
                        ),
                      ],
                    ),
                  );
                }),
              if (ownedBooks.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Gruppe pr. købt bog',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.brown.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                ...ownedBooks.map((b) {
                  final bid = b['id'] as String;
                  final title = b['title'] as String? ?? 'Bog';
                  final selected = _bookIdToGroupId[bid];
                  final validGroupIds = _libraryGroups
                      .map((g) => g['id'] as String)
                      .toSet();
                  final dropdownValue = selected != null &&
                          validGroupIds.contains(selected)
                      ? selected
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: dropdownValue,
                                hint: const Text('Ikke i gruppe'),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Ikke i gruppe'),
                                  ),
                                  ..._libraryGroups.map(
                                    (g) => DropdownMenuItem<String?>(
                                      value: g['id'] as String,
                                      child: Text(
                                        g['name'] as String? ?? 'Gruppe',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: _libraryGroups.isEmpty
                                    ? null
                                    : (v) =>
                                        _assignBookToLibraryGroup(bid, v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
