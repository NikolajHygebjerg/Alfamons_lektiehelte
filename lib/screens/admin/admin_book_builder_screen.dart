import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/profile_role_provider.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

/// Bogbuilder – kun for administratorer ([ProfileRoleProvider.isAdmin]).
class AdminBookBuilderScreen extends StatefulWidget {
  const AdminBookBuilderScreen({super.key});

  @override
  State<AdminBookBuilderScreen> createState() => _AdminBookBuilderScreenState();
}

class _AdminBookBuilderScreenState extends State<AdminBookBuilderScreen> {
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
      final res = await Supabase.instance.client
          .from('shop_books')
          .select('id, title, created_at, updated_at')
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _books = List<Map<String, dynamic>>.from(res as List);
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

  @override
  Widget build(BuildContext context) {
    final isAppAdmin = context.watch<ProfileRoleProvider>().isAdmin;
    if (!isAppAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Bogbuilder'),
          backgroundColor: const Color(0xFF5A1A0D),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/admin'),
          ),
          actions: const [AdminMenuToolbarButton()],
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Du har ikke adgang til denne side.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bogbuilder – Læs-let'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin'),
        ),
        actions: [
          const AdminMenuToolbarButton(),
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: 'Lydbibliotek',
            onPressed: _loading ? null : () => context.push('/admin/book-builder/lydbibliotek'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _loading ? null : () => _createNewBook(context),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _createNewBook(BuildContext context) async {
    final pageCount = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PageCountDialog(),
    );
    if (pageCount == null || pageCount < 1) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final insert = await Supabase.instance.client
          .from('shop_books')
          .insert({'title': 'Ny bog'})
          .select('id')
          .single();

      final bookId = insert['id'] as String;
      final pages = <Map<String, dynamic>>[];
      for (var i = 0; i < pageCount; i++) {
        pages.add({
          'book_id': bookId,
          'spread_index': i,
          'left_text': '',
          'right_image_url': null,
        });
      }
      await Supabase.instance.client.from('shop_book_pages').insert(pages);

      if (mounted) {
        await router.push('/admin/book-builder/edit/$bookId');
        if (mounted) _load();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
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
                      'Ingen bøger endnu.\nTryk + for at oprette en ny bog.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _books.length,
              itemBuilder: (context, i) {
                final b = _books[i];
                final title = b['title'] as String? ?? 'Uden titel';
                final id = b['id'] as String;
                return GestureDetector(
                  onTap: () => context.push('/admin/book-builder/edit/$id'),
                  behavior: HitTestBehavior.opaque,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: const Color(0xFFF9C433).withOpacity(0.9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.menu_book, size: 40),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('Oprettet: ${b['created_at']}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PageCountDialog extends StatefulWidget {
  @override
  State<_PageCountDialog> createState() => _PageCountDialogState();
}

class _PageCountDialogState extends State<_PageCountDialog> {
  int _count = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Antal opslag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Forside + antal opslag (2-3, 4-5, osv.).\nForside tæller som 1.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _count > 1 ? () => setState(() => _count--) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('$_count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _count < 50 ? () => setState(() => _count++) : null,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuller'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_count),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5A1A0D)),
          child: const Text('Opret'),
        ),
      ],
    );
  }
}
