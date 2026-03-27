import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

/// Testside til at afspille alle lydfiler (tale-m4a og mp3).
class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key});

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen> {
  late final AudioPlayer _player;
  String? _playingPath;

  static const _taleFiles = [
    'Aarmoktale2.m4a',
    'Aelgortale2.m4a',
    'Atiachtale2.m4a',
    'Bezzletale2.m4a',
    'Cekimostale2.m4a',
    'Gemibulltale2.m4a',
    'Haaghaitale2.m4a',
    'Iffletale2.m4a',
    'Jaadriktale2.m4a',
    'Kaavaxtale2.m4a',
    'Lmitale2.m4a',
    'maxtortale2.m4a',
    'Nimbrootale2.m4a',
    'Oegleontale2.m4a',
    'Oodlobtale2.m4a',
    'Peppapoptale1.m4a',
    'Quiblytale2.m4a',
    'Rminaxtale2.m4a',
    'Snaketale2.m4a',
    'Tegormtale2.m4a',
    'Ummirootale2.m4a',
    'Vindleektale2.m4a',
    'Wiglootale2.m4a',
    'Xbugtale2.m4a',
    'Yglifaxtale2.m4a',
    'Zetbratale2.m4a',
  ];

  static const _mp3Files = [
    'Duvinder.mp3',
    'Mod.mp3',
    'Modstanderenvinder.mp3',
    'Modstandervaelgerevne.mp3',
    'Vaelgevne.mp3',
    'rising.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.audioCache.prefix = '';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(String path) async {
    setState(() => _playingPath = path);
    try {
      await _player.stop();
      await _player.play(AssetSource('assets/$path'));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playingPath = null);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playingPath = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lydtest'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin'),
        ),
        actions: const [
          AdminMenuToolbarButton(lightOnDark: false),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tale-lyde (m4a)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _taleFiles.map((f) => _SoundButton(
                label: f.replaceAll('.m4a', ''),
                path: f,
                isPlaying: _playingPath == f,
                onTap: () => _play(f),
              )).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Spillyde (mp3)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _mp3Files.map((f) => _SoundButton(
                label: f.replaceAll('.mp3', ''),
                path: f,
                isPlaying: _playingPath == f,
                onTap: () => _play(f),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoundButton extends StatelessWidget {
  final String label;
  final String path;
  final bool isPlaying;
  final VoidCallback onTap;

  const _SoundButton({
    required this.label,
    required this.path,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPlaying ? Colors.green.shade700 : Colors.blue.shade700,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPlaying ? Icons.stop : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
