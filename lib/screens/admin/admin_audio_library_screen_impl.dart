import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/profile_role_provider.dart';
import '../../services/audio_cache_service.dart';
import '../../utils/read_file_bytes_stub.dart' if (dart.library.io) '../../utils/read_file_bytes_io.dart' as file_reader;
import '../../widgets/admin/admin_menu_toolbar_button.dart';
const _bucketName = 'book-audio';

/// Lydbibliotek – opret ord med optaget lyd til brug i Læs-let bøger.
class AdminAudioLibraryScreen extends StatefulWidget {
  const AdminAudioLibraryScreen({super.key});

  @override
  State<AdminAudioLibraryScreen> createState() => _AdminAudioLibraryScreenState();
}

class _AdminAudioLibraryScreenState extends State<AdminAudioLibraryScreen> {
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;
  String? _error;
  final _record = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _playingUrl;
  final TextEditingController _wordController = TextEditingController();
  List<InputDevice> _inputDevices = [];
  InputDevice? _selectedDevice;
  bool _loadingDevices = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadInputDevices();
  }

  Future<void> _loadInputDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final devices = await _record.listInputDevices();
      if (mounted) {
        // Find indbygget mikrofon – undgå BlackHole, Loopback osv. som giver stille lyd
        final micKeywords = ['mikrofon', 'microphone', 'built-in', 'builtin', 'indbygget', 'macbook', 'internal'];
        final excludeKeywords = ['blackhole', 'loopback', 'virtual', 'aggregate'];
        InputDevice? preferred;
        for (final d in devices) {
          final label = d.label.toLowerCase();
          if (excludeKeywords.any((k) => label.contains(k))) continue;
          if (micKeywords.any((k) => label.contains(k))) {
            preferred = d;
            break;
          }
        }
        setState(() {
          _inputDevices = devices;
          _loadingDevices = false;
          if (_selectedDevice != null &&
              !devices.any((d) => d.id == _selectedDevice!.id)) {
            _selectedDevice = null;
          }
          // Vælg indbygget mikrofon som standard hvis ingen er valgt
          if (_selectedDevice == null && preferred != null) {
            _selectedDevice = preferred;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }


  @override
  void dispose() {
    _record.dispose();
    _audioPlayer.dispose();
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _playWord(String url) async {
    if (_playingUrl == url) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingUrl = null);
      return;
    }
    setState(() => _playingUrl = url);
    try {
      await _audioPlayer.stop();
      final localPath = await AudioCacheService.ensureCached(url);
      await _audioPlayer.setFilePath(localPath);
      await _audioPlayer.play();
      _audioPlayer.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed)
          .timeout(const Duration(seconds: 30))
          .then((_) {
        if (mounted) setState(() => _playingUrl = null);
      }).catchError((_) {});
    } catch (e) {
      if (mounted) {
        setState(() => _playingUrl = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke afspille: $e')),
        );
      }
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client
          .from('audio_library')
          .select('id, word, audio_url, created_at')
          .order('word');
      if (mounted) {
        setState(() {
          _words = List<Map<String, dynamic>>.from(res as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _addWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv et ord først')),
      );
      return;
    }

    if (!await _record.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofonadgang er nødvendig for at optage')),
        );
      }
      return;
    }

    setState(() => _isRecording = true);
    // På macOS kræver sandbox at vi bruger app-dokumenter mappen
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await _record.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 44100,
          device: _selectedDevice,
          autoGain: true,
        ),
        path: path,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Optagelse fejlede: $e')),
        );
      }
      return;
    }

    final stopRecording = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RecordingDialog(word: word),
    );
    if (!mounted) return;

    String? recordedPath;
    if (stopRecording == true) {
      try {
        recordedPath = await _record.stop();
      } catch (_) {
        recordedPath = null;
      }
    } else {
      await _record.cancel();
    }
    if (mounted) setState(() => _isRecording = false);

    if (recordedPath == null || recordedPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Optagelse blev annulleret')),
        );
      }
      return;
    }

    final file = File(recordedPath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Optaget fil blev ikke fundet')),
        );
      }
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length < 1000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Optagelsen er for kort eller tom. Prøv igen og tal tydeligt i mindst 1 sekund.')),
        );
      }
      return;
    }
    final wordLower = word.toLowerCase();
    final safeWord = wordLower
        .replaceAll('æ', 'ae')
        .replaceAll('ø', 'o')
        .replaceAll('å', 'aa')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '_');
    final fileName = '${safeWord}_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await Supabase.instance.client.storage.from(_bucketName).uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final url = Supabase.instance.client.storage.from(_bucketName).getPublicUrl(fileName);

      await Supabase.instance.client.from('audio_library').insert({
        'word': wordLower,
        'audio_url': url,
      });

      final noiseReduced = await _runNoiseReduction(fileName);

      _wordController.clear();
      await _load();
      if (mounted) {
        final msg = noiseReduced
            ? '"$word" er tilføjet (med støjreduktion)'
            : '"$word" er tilføjet til lydbiblioteket';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl ved gem: $e')),
        );
      }
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Returnerer true hvis støjreduktion gennemførtes, false ellers.
  Future<bool> _runNoiseReduction(String fileName) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'process-audio-noise-reduction',
        body: {'path': fileName},
      );
      if (!mounted) return false;
      if (res.status == 200 && res.data is Map && res.data?['success'] == true) {
        return true;
      }
      if (res.status == 503 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Støjreduktion ikke konfigureret. Lyden er gemt.'),
            duration: Duration(seconds: 3),
          ),
        );
      } else if (res.status != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data is Map && res.data?['error'] != null
                ? '${res.data!['error']}. Lyden er gemt.'
                : 'Støjreduktion fejlede. Lyden er gemt.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Støjreduktion ikke tilgængelig. Lyden er gemt.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _uploadWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv ordet først')),
      );
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m4a', 'wav', 'mp3', 'aac'],
        allowMultiple: false,
        withData: true,
        dialogTitle: 'Vælg lydfil',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vælg fil fejlede: $e')),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
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

    final wordLower = word.toLowerCase();
    final safeWord = wordLower
        .replaceAll('æ', 'ae')
        .replaceAll('ø', 'o')
        .replaceAll('å', 'aa')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '_');
    final ext = file.extension ?? 'm4a';
    final fileName = '${safeWord}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await Supabase.instance.client.storage.from(_bucketName).uploadBinary(
        fileName,
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        fileOptions: const FileOptions(upsert: true),
      );
      final url = Supabase.instance.client.storage.from(_bucketName).getPublicUrl(fileName);

      await Supabase.instance.client.from('audio_library').insert({
        'word': wordLower,
        'audio_url': url,
      });

      final noiseReduced = await _runNoiseReduction(fileName);

      _wordController.clear();
      await _load();
      if (mounted) {
        final msg = noiseReduced
            ? '"$word" er tilføjet (med støjreduktion)'
            : '"$word" er tilføjet til lydbiblioteket';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl ved upload: $e')),
        );
      }
    }
  }

  Future<void> _deleteWord(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slet ord?'),
        content: Text('Vil du slette "${item['word']}" fra lydbiblioteket?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuller'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slet'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('audio_library').delete().eq('id', item['id']);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ord slettet')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAppAdmin = context.watch<ProfileRoleProvider>().isAdmin;
    if (!isAppAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lydbibliotek'),
          backgroundColor: const Color(0xFF5A1A0D),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/admin/book-builder'),
          ),
          actions: const [AdminMenuToolbarButton()],
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Du har ikke adgang til denne side.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lydbibliotek'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/book-builder'),
        ),
        actions: [
          const AdminMenuToolbarButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _load, child: const Text('Prøv igen')),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          color: const Color(0xFFF9C433).withValues(alpha: 0.9),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tilføj nyt ord',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Skriv ordet og tryk på Optag for at optage lyden. Ord i lydbiblioteket fremhæves i bøgerne, og barnet kan trykke på dem for at få dem læst op.',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text('Lydinput:', style: TextStyle(fontSize: 13)),
                                    const SizedBox(width: 8),
                                    if (_loadingDevices)
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    else
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(color: Colors.grey),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<InputDevice?>(
                                              value: _selectedDevice,
                                              isExpanded: true,
                                              hint: const Text('Systemstandard'),
                                              items: [
                                                const DropdownMenuItem<InputDevice?>(
                                                  value: null,
                                                  child: Text('Systemstandard'),
                                                ),
                                                ..._inputDevices.map((d) => DropdownMenuItem<InputDevice?>(
                                                  value: d,
                                                  child: Text(d.label, overflow: TextOverflow.ellipsis),
                                                )),
                                              ],
                                              onChanged: _isRecording ? null : (v) => setState(() => _selectedDevice = v),
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.refresh),
                                      onPressed: _loadingDevices || _isRecording ? null : _loadInputDevices,
                                      tooltip: 'Opdater lydinput-liste',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _wordController,
                                        decoration: const InputDecoration(
                                          labelText: 'Ord',
                                          hintText: 'f.eks. hund',
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(),
                                        ),
                                        textCapitalization: TextCapitalization.none,
                                        onSubmitted: (_) => _addWord(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      onPressed: _isRecording ? null : _addWord,
                                      icon: Icon(_isRecording ? Icons.mic : Icons.mic_none, size: 24),
                                      label: Text(_isRecording ? 'Optager...' : 'Optag'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _isRecording ? Colors.grey : const Color(0xFF5A1A0D),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _uploadWord,
                                      icon: const Icon(Icons.upload_file, size: 24),
                                      label: const Text('Upload'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF5A1A0D),
                                        side: const BorderSide(color: Color(0xFF5A1A0D)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Vælg indbygget mikrofon i menuen ovenfor hvis optagelsen er stille (fx fordi systemet bruger BlackHole). Eller brug Upload med en lydfil (m4a, wav, mp3).',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Ord i lydbiblioteket (${_words.length})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        if (_words.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Ingen ord endnu. Tilføj ord med optaget lyd ovenfor.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _words.map((w) {
                              final word = w['word'] as String? ?? '';
                              final url = w['audio_url'] as String? ?? '';
                              final isPlaying = _playingUrl == url;
                              return Material(
                                color: const Color(0xFFF9C433).withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: url.isNotEmpty ? () => _playWord(url) : null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isPlaying ? Icons.stop : Icons.play_arrow,
                                          size: 24,
                                          color: const Color(0xFF5A1A0D),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(word),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () => _deleteWord(w),
                                          child: const Icon(Icons.close, size: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Dialog der kræver mindst 1,5 sek optagelse for at undgå tomme filer.
class _RecordingDialog extends StatefulWidget {
  final String word;

  const _RecordingDialog({required this.word});

  @override
  State<_RecordingDialog> createState() => _RecordingDialogState();
}

class _RecordingDialogState extends State<_RecordingDialog> {
  bool _canStop = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _canStop = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Optager'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Optager lyd for "${widget.word}".'),
          const SizedBox(height: 8),
          Text(
            _canStop ? 'Tryk Stop når du er færdig.' : 'Vent 1 sekund...',
            style: TextStyle(color: _canStop ? null : Colors.grey),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _canStop ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Stop'),
        ),
      ],
    );
  }
}
