import 'package:just_audio/just_audio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/audio_cache_service.dart';
import '../../services/task_completion_service.dart';
import '../../widgets/kid_parent_admin_corner.dart';
import 'widgets/gold_coins_earned_overlay.dart';

/// Bog-læser for Læs-let bøger.
class KidBookReaderScreen extends StatefulWidget {
  final String kidId;
  final String bookId;

  const KidBookReaderScreen({super.key, required this.kidId, required this.bookId});

  @override
  State<KidBookReaderScreen> createState() => _KidBookReaderScreenState();
}

enum _TextCase { sentence, upper, lower }

class _KidBookReaderScreenState extends State<KidBookReaderScreen> {
  List<Map<String, dynamic>> _pages = [];
  String? _title;
  bool _loading = true;
  String? _error;
  bool _bookOpened = false;
  int _currentSpreadIndex = 0;
  _TextCase _textCase = _TextCase.sentence;
  Map<String, String> _audioLibrary = {}; // word -> local path
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _flashGoldAmount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playWord(String path) async {
    await _audioPlayer.stop();
    final uri = Uri.tryParse(path);
    final isNetwork = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    if (isNetwork) {
      await _audioPlayer.setUrl(path);
    } else {
      await _audioPlayer.setFilePath(path);
    }
    await _audioPlayer.play();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final bookRes = await Supabase.instance.client
          .from('shop_books')
          .select('id, title')
          .eq('id', widget.bookId)
          .maybeSingle();
      if (bookRes == null || bookRes is! Map) {
        if (mounted) setState(() { _error = 'Bog ikke fundet'; _loading = false; });
        return;
      }
      _title = (bookRes['title'] as String?) ?? 'Bog';

      final pagesRes = await Supabase.instance.client
          .from('shop_book_pages')
          .select('id, spread_index, left_text, right_image_url')
          .eq('book_id', widget.bookId)
          .order('spread_index');
      final list = pagesRes is List ? pagesRes : <dynamic>[];
      _pages = list
          .map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{})
          .where((e) => e.isNotEmpty)
          .toList();
      _pages.sort((a, b) => ((a['spread_index'] ?? 0) as num).toInt().compareTo(((b['spread_index'] ?? 0) as num).toInt()));

      final lib = await AudioCacheService.getWordToLocalPath();
      if (mounted) setState(() { _loading = false; _audioLibrary = lib; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _openBook() {
    setState(() => _bookOpened = true);
  }

  void _prevPage() {
    if (_currentSpreadIndex > 0) {
      setState(() => _currentSpreadIndex--);
    }
  }

  Future<void> _nextPage() async {
    if (_currentSpreadIndex >= _pages.length - 1) {
      await _showFinishBookDialog();
    } else {
      setState(() => _currentSpreadIndex++);
    }
  }

  Future<void> _showFinishBookDialog() async {
    final pointsToAward = _pages.length - 1;
    if (pointsToAward < 1) {
      if (mounted) context.go('/kid/library/${widget.kidId}');
      return;
    }

    final storedRes = await Supabase.instance.client
        .from('settings')
        .select('value')
        .eq('key', 'approval_code')
        .maybeSingle();
    final storedCode = (storedRes?['value'] as String?)?.trim() ?? '';
    if (storedCode.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Forældrekode er ikke sat. En voksen skal logge ind som forælder og sætte koden.'),
          ),
        );
        context.go('/kid/library/${widget.kidId}');
      }
      return;
    }

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BookFinishDialog(pointsToAward: pointsToAward),
    );
    if (code == null) {
      if (mounted) context.go('/kid/library/${widget.kidId}');
      return;
    }
    if (code.trim() != storedCode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forkert forældrekode')),
        );
      }
      return;
    }

    try {
      final result = await TaskCompletionService.awardBookPoints(
        kidId: widget.kidId,
        points: pointsToAward,
        parentCode: code.trim(),
      );
      if (mounted) {
        if (result.dailyBonus != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🎉 Du fik ${result.dailyBonus} ekstra guldmønter for at have klaret alle dagens opgaver!',
              ),
            ),
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Du fik ${result.points} guldmønter i kisten for at læse bogen!',
            ),
          ),
        );
        final gained = result.points + (result.dailyBonus ?? 0);
        if (gained > 0) {
          setState(() => _flashGoldAmount = gained);
          Future.delayed(const Duration(milliseconds: 2800), () {
            if (mounted) setState(() => _flashGoldAmount = null);
          });
          await Future<void>.delayed(const Duration(milliseconds: 2900));
        }
        if (mounted) context.go('/kid/library/${widget.kidId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  void _cycleTextCase() {
    setState(() {
      _textCase = switch (_textCase) {
        _TextCase.sentence => _TextCase.upper,
        _TextCase.upper => _TextCase.lower,
        _TextCase.lower => _TextCase.sentence,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF5A1A0D),
        body: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF5A1A0D),
        appBar: AppBar(backgroundColor: const Color(0xFF5A1A0D), foregroundColor: Colors.white),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(onPressed: () => context.go('/kid/library/${widget.kidId}'), child: const Text('Tilbage', style: TextStyle(color: Colors.white))),
            ],
          ),
        ),
      );
    }

    final coverUrl = _pages.isNotEmpty ? _pages[0]['right_image_url'] as String? : null;

    return Scaffold(
      backgroundColor: const Color(0xFF2C1810),
      body: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (!_bookOpened)
            _BuildCoverView(coverUrl: coverUrl, title: _title ?? 'Bog', onTap: _openBook)
          else
            _BuildBookContent(
              pages: _pages,
              currentIndex: _currentSpreadIndex,
              textCase: _textCase,
              audioLibrary: _audioLibrary,
              onPlayWord: _playWord,
              onPrev: _prevPage,
              onNext: _nextPage,
              onClose: () => context.go('/kid/library/${widget.kidId}'),
              onCycleTextCase: _cycleTextCase,
            ),
          Positioned(
            top: 16,
            left: 16,
            child: GestureDetector(
              onTap: () => context.go('/kid/library/${widget.kidId}'),
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.close, size: 44, color: Colors.black87),
              ),
            ),
          ),
          const Positioned(
            top: 24,
            right: 16,
            child: KidParentAdminCornerButton(),
          ),
          if (_flashGoldAmount != null)
            Positioned.fill(
              child: GoldCoinsEarnedOverlay(amount: _flashGoldAmount!),
            ),
        ],
      ),
    );
  }
}

class _BuildCoverView extends StatelessWidget {
  final String? coverUrl;
  final String title;
  final VoidCallback onTap;

  const _BuildCoverView({this.coverUrl, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          coverUrl != null && coverUrl!.isNotEmpty
              ? Positioned.fill(
                  child: Center(
                    child: Image.network(coverUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _placeholder()),
                  ),
                )
              : _placeholder(),
          if (coverUrl != null && coverUrl!.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Tryk for at åbne', style: TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book, size: 80, color: Colors.brown.shade300),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.all(16), child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown.shade800))),
          const SizedBox(height: 24),
          Text('Tryk for at åbne', style: TextStyle(fontSize: 14, color: Colors.brown.shade600)),
        ],
      ),
    );
  }
}

/// Fuld skærm: venstre halvdel = tekst (hvid baggrund), højre halvdel = billede. Forside centreret.
class _BuildBookContent extends StatelessWidget {
  final List<Map<String, dynamic>> pages;
  final int currentIndex;
  final _TextCase textCase;
  final Map<String, String> audioLibrary;
  final void Function(String audioUrl) onPlayWord;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final VoidCallback onCycleTextCase;

  const _BuildBookContent({
    required this.pages,
    required this.currentIndex,
    required this.textCase,
    required this.audioLibrary,
    required this.onPlayWord,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
    required this.onCycleTextCase,
  });

  String _applyTextCase(String text) {
    return switch (textCase) {
      _TextCase.sentence => _toSentenceCase(text),
      _TextCase.upper => text.toUpperCase(),
      _TextCase.lower => text.toLowerCase(),
    };
  }

  /// Stort begyndelsesbogstav og stort efter sætningstegn. Følger den indsatte tekst, ingen navneregler.
  String _toSentenceCase(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    var capitalizeNext = true;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (capitalizeNext && char.trim().isNotEmpty) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
        if (char == '.' || char == '!' || char == '?' || char == '\n') {
          capitalizeNext = true;
        }
      }
    }
    return buffer.toString();
  }

  String _caseButtonLabel() {
    return switch (textCase) {
      _TextCase.sentence => 'Aa',
      _TextCase.upper => 'AA',
      _TextCase.lower => 'aa',
    };
  }

  Widget _buildTappableText(String text, TextStyle baseStyle) {
    if (audioLibrary.isEmpty) {
      return Text(text, textAlign: TextAlign.center, style: baseStyle);
    }
    final wordRegex = RegExp(r'\b\w+\b');
    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in wordRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
      }
      final word = match.group(0)!;
      final path = audioLibrary[word.toLowerCase()];
      if (path != null) {
        spans.add(TextSpan(
          text: word,
          style: baseStyle.copyWith(
            color: const Color(0xFF5A1A0D),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF5A1A0D),
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => onPlayWord(path),
        ));
      } else {
        spans.add(TextSpan(text: word, style: baseStyle));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(children: spans, style: baseStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Center(child: Text('Ingen sider', style: TextStyle(color: Colors.white)));
    }

    final spread = pages[currentIndex];
    final isCover = currentIndex == 0;
    final leftText = spread['left_text'] as String? ?? '';
    final rightImageUrl = spread['right_image_url'] as String?;
    final isLast = currentIndex >= pages.length - 1;
    final canGoBack = currentIndex > 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isCover)
          rightImageUrl != null && rightImageUrl.isNotEmpty
              ? Positioned.fill(
                  child: Center(
                    child: Image.network(rightImageUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _coverPlaceholder()),
                  ),
                )
              : _coverPlaceholder()
        else
          Row(
            children: [
              Expanded(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: SingleChildScrollView(
                      child: _buildTappableText(
                        _applyTextCase(leftText),
                        const TextStyle(fontSize: 36, height: 1.6, color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: rightImageUrl != null && rightImageUrl.isNotEmpty
                    ? Image.network(rightImageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ],
          ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, size: 48, color: Colors.black),
              onPressed: canGoBack ? onPrev : (isCover ? onClose : null),
              style: IconButton.styleFrom(backgroundColor: isCover ? Colors.white.withOpacity(0.9) : Colors.transparent),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: IconButton(
              icon: Icon(isLast ? Icons.check_circle : Icons.arrow_forward, size: 48, color: Colors.black),
              onPressed: onNext,
              style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.85)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: TextButton(
              onPressed: onCycleTextCase,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(_caseButtonLabel(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(child: Icon(Icons.menu_book, size: 80, color: Colors.grey)),
    );
  }

  Widget _placeholder() {
    return Container(color: Colors.grey.shade200, child: const Center(child: Icon(Icons.image, size: 48, color: Colors.grey)));
  }
}

/// Dialog til forældrekode ved afslutning af bog – tildeler point.
class _BookFinishDialog extends StatefulWidget {
  final int pointsToAward;

  const _BookFinishDialog({required this.pointsToAward});

  @override
  State<_BookFinishDialog> createState() => _BookFinishDialogState();
}

class _BookFinishDialogState extends State<_BookFinishDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Afslut bog'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Barnet har læst bogen og kan få ${widget.pointsToAward} point. Indtast forældrekoden for at tildele point.',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
            decoration: const InputDecoration(
              hintText: '••••',
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Spring over'),
        ),
        FilledButton(
          onPressed: _controller.text.length == 4 ? _submit : null,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5A1A0D)),
          child: const Text('Tildel point'),
        ),
      ],
    );
  }

  void _submit() {
    if (_controller.text.length != 4) return;
    Navigator.of(context).pop(_controller.text);
  }
}
