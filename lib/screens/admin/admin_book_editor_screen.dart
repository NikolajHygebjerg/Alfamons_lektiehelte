import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/read_file_bytes_stub.dart' if (dart.library.io) '../../utils/read_file_bytes_io.dart' as file_reader;
import '../../widgets/admin/admin_menu_toolbar_button.dart';

const _pageSize = 1024;
const _bucketName = 'book-images';

/// Rediger en bog: forside + opslag med tekst (venstre) og billede (højre).
/// Format: 1024x1024 px per side.
class AdminBookEditorScreen extends StatefulWidget {
  final String bookId;

  const AdminBookEditorScreen({super.key, required this.bookId});

  @override
  State<AdminBookEditorScreen> createState() => _AdminBookEditorScreenState();
}

class _AdminBookEditorScreenState extends State<AdminBookEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController(text: '0');
  List<Map<String, dynamic>> _pages = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (widget.bookId.isEmpty) {
      if (mounted) setState(() { _error = 'Ugyldigt bog-id'; _loading = false; });
      return;
    }
    try {
      Map<String, dynamic>? bookRes;
      try {
        final raw = await Supabase.instance.client
            .from('shop_books')
            .select('id, title, price_kr')
            .eq('id', widget.bookId)
            .maybeSingle();
        if (raw != null) {
          bookRes = Map<String, dynamic>.from(raw);
        }
      } on PostgrestException catch (_) {
        final raw = await Supabase.instance.client
            .from('shop_books')
            .select('id, title')
            .eq('id', widget.bookId)
            .maybeSingle();
        if (raw != null) {
          bookRes = Map<String, dynamic>.from(raw);
        }
      }

      if (bookRes == null) {
        if (mounted) {
          setState(() {
            _error = 'Bog ikke fundet';
            _loading = false;
          });
        }
        return;
      }

      _titleController.text = bookRes['title']?.toString() ?? '';
      if (bookRes.containsKey('price_kr')) {
        final pk = bookRes['price_kr'];
        _priceController.text = pk is num
            ? pk.toString()
            : (double.tryParse(pk?.toString() ?? '')?.toString() ?? '0');
      } else {
        _priceController.text = '0';
      }

      // Hent sider
      List<Map<String, dynamic>> pages = [];
      try {
        final pagesRes = await Supabase.instance.client
            .from('shop_book_pages')
            .select('id, spread_index, left_text, right_image_url')
            .eq('book_id', widget.bookId)
            .order('spread_index');

        final list = pagesRes as List;
        pages = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        pages.sort((a, b) => ((a['spread_index'] ?? 0) as num).toInt().compareTo(((b['spread_index'] ?? 0) as num).toInt()));
      } catch (e) {
        debugPrint('Fejl ved hentning af sider: $e');
      }

      if (mounted) {
        setState(() {
          _pages = pages;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('Fejl ved load af bog: $e\n$st');
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final title = _titleController.text.trim().isEmpty ? 'Ny bog' : _titleController.text.trim();
      final priceKr = double.tryParse(_priceController.text.trim()) ?? 0.0;

      // Forsøg med price_kr; hvis kolonnen ikke findes (migration ikke kørt), prøv uden
      var savedWithPrice = true;
      try {
        await Supabase.instance.client.from('shop_books').update({
          'title': title,
          'price_kr': priceKr,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.bookId);
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST204' && e.message.contains('price_kr')) {
          savedWithPrice = false;
          await Supabase.instance.client.from('shop_books').update({
            'title': title,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', widget.bookId);
        } else {
          rethrow;
        }
      }

      final keptIds = _pages.map((p) => p['id'] as String).toSet();
      final existing = await Supabase.instance.client
          .from('shop_book_pages')
          .select('id')
          .eq('book_id', widget.bookId);
      for (final row in existing as List) {
        final id = row['id'] as String;
        if (!keptIds.contains(id)) {
          await Supabase.instance.client.from('shop_book_pages').delete().eq('id', id);
        }
      }

      for (var i = 0; i < _pages.length; i++) {
        final p = _pages[i];
        await Supabase.instance.client.from('shop_book_pages').update({
          'spread_index': i,
          'left_text': p['left_text'] ?? '',
          'right_image_url': p['right_image_url'],
        }).eq('id', p['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(savedWithPrice ? 'Bog gemt' : 'Bog gemt. Kør migration 20250319000000_shop_books_price_purchases.sql i Supabase for at gemme pris.'),
            duration: savedWithPrice ? const Duration(seconds: 2) : const Duration(seconds: 5),
          ),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl ved gem: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  void _reorderPages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, item);
    });
  }

  Future<void> _deletePageById(String pageId) async {
    final index = _pages.indexWhere((p) => p['id'] == pageId);
    if (index < 0) return;
    if (_pages.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bogen skal have mindst én side')),
        );
      }
      return;
    }
    final label = _spreadLabel(index);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet opslag?'),
        content: Text('Vil du slette "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuller'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final idx = _pages.indexWhere((p) => p['id'] == pageId);
      if (idx >= 0) {
        setState(() => _pages.removeAt(idx));
      }
    }
  }

  Future<void> _pickImage(int pageIndex) async {
    FilePickerResult? result;
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'],
        allowMultiple: false,
        withData: true,
        dialogTitle: 'Vælg billede (1024×1024 px)',
      );
    } catch (e, st) {
      debugPrint('FilePicker fejl: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vælg billede fejlede: $e'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingen fil valgt. Tjek om filvælgeren åbnede bag appen.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final file = result.files.single;
    final ext = file.extension ?? 'jpg';
    final fileName = '${widget.bookId}_${_pages[pageIndex]['spread_index']}.$ext';

    List<int>? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      try {
        bytes = await file_reader.readFileBytes(file.path!);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke læse fil')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.storage.from(_bucketName).uploadBinary(
            fileName,
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            fileOptions: const FileOptions(upsert: true),
          );

      final url = Supabase.instance.client.storage.from(_bucketName).getPublicUrl(fileName);

      setState(() {
        _pages[pageIndex]['right_image_url'] = url;
        _saving = false;
      });
    } catch (e, st) {
      debugPrint('Upload fejl: $e\n$st');
      if (mounted) {
        String msg = 'Upload fejl: $e';
        if (e.toString().contains('bucket') || e.toString().contains('not found')) {
          msg = 'Storage-bucket "$_bucketName" findes ikke. Opret den i Supabase Dashboard → Storage.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
        );
        setState(() => _saving = false);
      }
    }
  }

  String _spreadLabel(int index) {
    if (index == 0) return 'Forside';
    final left = index * 2;
    final right = left + 1;
    return 'Side $left-$right';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Indlæser...'),
          backgroundColor: const Color(0xFF5A1A0D),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/admin/book-builder'),
          ),
          actions: const [AdminMenuToolbarButton()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fejl'),
          backgroundColor: const Color(0xFF5A1A0D),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/admin/book-builder'),
          ),
          actions: const [AdminMenuToolbarButton()],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Prøv igen'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => context.go('/admin/book-builder'),
                      child: const Text('Tilbage'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleController.text.trim().isEmpty ? 'Rediger bog' : _titleController.text.trim()),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/book-builder'),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: Colors.white, size: 20),
              label: const Text('Gem', style: TextStyle(color: Colors.white)),
            ),
          const AdminMenuToolbarButton(),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A1A0D), Color(0xFFE85A4A)],
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 90),
                Expanded(
                  child: ReorderableListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16),
                itemExtent: 484,
                onReorder: _reorderPages,
                proxyDecorator: (child, index, animation) => Material(
                  elevation: 8,
                  color: Colors.transparent,
                  child: child,
                ),
                buildDefaultDragHandles: false,
                children: [
                  for (var i = 0; i < _pages.length; i++) ...[
                    () {
                      final pageId = _pages[i]['id'] as String;
                      final canDelete = _pages.length > 1;
                      return SizedBox(
                        key: ValueKey(pageId),
                        width: 484,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (canDelete)
                              SizedBox(
                                width: 48,
                                child: Center(
                                  child: IconButton(
                                    onPressed: () => _deletePageById(pageId),
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                                    tooltip: 'Slet opslag',
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: i < _pages.length - 1 ? 16 : 0),
                                child: _SpreadCard(
                                  reorderIndex: i,
                                  label: _spreadLabel(i),
                                  isCover: i == 0,
                                  leftText: _pages[i]['left_text'] as String? ?? '',
                                  onLeftTextChanged: (v) {
                                    setState(() => _pages[i]['left_text'] = v);
                                  },
                                  rightImageUrl: _pages[i]['right_image_url'] as String?,
                                  onUploadTap: () => _pickImage(i),
                                  onDeleteTap: null,
                                  pageSize: _pageSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            ),
          ],
        ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 90,
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Bogtitel',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          controller: _titleController,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Pris (kr)',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpreadCard extends StatefulWidget {
  final int reorderIndex;
  final String label;
  final bool isCover;
  final String leftText;
  final ValueChanged<String> onLeftTextChanged;
  final String? rightImageUrl;
  final VoidCallback onUploadTap;
  final VoidCallback? onDeleteTap;
  final int pageSize;

  const _SpreadCard({
    required this.reorderIndex,
    required this.label,
    required this.isCover,
    required this.leftText,
    required this.onLeftTextChanged,
    required this.rightImageUrl,
    required this.onUploadTap,
    this.onDeleteTap,
    required this.pageSize,
  });

  @override
  State<_SpreadCard> createState() => _SpreadCardState();
}

class _SpreadCardState extends State<_SpreadCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.leftText);
  }

  @override
  void didUpdateWidget(_SpreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftText != widget.leftText && _controller.text != widget.leftText) {
      _controller.text = widget.leftText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardW = 420.0;
    const cardH = 320.0;

    return Card(
      color: const Color(0xFFF9C433).withOpacity(0.9),
      child: SizedBox(
        width: cardW,
        height: cardH,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReorderableDelayedDragStartListener(
                        index: widget.reorderIndex,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.drag_handle, size: 20, color: Colors.grey[700]),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (widget.onDeleteTap != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onDeleteTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red[700], size: 22),
                                const SizedBox(width: 4),
                                Text('Slet', style: TextStyle(color: Colors.red[700], fontSize: 13, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        // Venstre: tekst (skjult på forside)
                        if (!widget.isCover)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              maxLines: null,
                              expands: true,
                              decoration: const InputDecoration(
                                hintText: 'Indsæt tekst her...',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(8),
                              ),
                              controller: _controller,
                              onChanged: widget.onLeftTextChanged,
                            ),
                          ),
                        ),
                        if (!widget.isCover) const SizedBox(width: 8),
                        // Højre: billede
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (widget.rightImageUrl != null && widget.rightImageUrl!.isNotEmpty)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Image.network(
                                        widget.rightImageUrl!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48), // ignore: unnecessary_underscores
                                      ),
                                    ),
                                  )
                                else
                                  const Expanded(
                                    child: Center(
                                      child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    children: [
                                      Text(
                                        '${widget.pageSize}×${widget.pageSize} px',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      const SizedBox(height: 4),
                                      FilledButton.icon(
                                        onPressed: widget.onUploadTap,
                                        icon: const Icon(Icons.upload_file, size: 18),
                                        label: const Text('Upload billede'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF5A1A0D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
