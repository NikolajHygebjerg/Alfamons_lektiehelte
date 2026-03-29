import 'package:just_audio/just_audio.dart';

/// Plays music on the letter selection screen.
/// First visit: Velkommentale.mp3 (one-shot). Subsequent: bogstavmusik.mp3 (loop).
/// AudioPlayer and assets are created/loaded only when start() is called (lazy).
class LetterScreenMusicService {
  LetterScreenMusicService();

  AudioPlayer? _player;
  bool _isPlaying = false;

  AudioPlayer get _ensurePlayer {
    _player ??= AudioPlayer();
    return _player!;
  }

  /// [isFirstVisit] true = play Velkommentale.mp3 once. false = play bogstavmusik loop.
  Future<void> start({required bool isFirstVisit}) async {
    if (_isPlaying) return;
    try {
      final player = _ensurePlayer;
      if (isFirstVisit) {
        await player.setAsset('packages/alfamon_trace/Assets/Velkommentale.mp3');
        await player.setLoopMode(LoopMode.off);
        await player.setVolume(1.0);
        await player.play();
        _isPlaying = true;
      } else {
        await player.setAsset('packages/alfamon_trace/Assets/bogstavmusik.mp3');
        await player.setLoopMode(LoopMode.all);
        await player.setVolume(1.0);
        await player.play();
        _isPlaying = true;
      }
    } catch (e) {
      // ignore
    }
  }

  /// Stops the music. Call and AWAIT this before starting drawing music.
  Future<void> stop() async {
    _isPlaying = false;
    try {
      if (_player != null) {
        await _player!.setVolume(0);
        await _player!.stop();
        await _player!.seek(Duration.zero);
      }
    } catch (e) {
      // ignore
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
