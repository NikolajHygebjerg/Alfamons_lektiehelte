import 'package:just_audio/just_audio.dart';

/// Plays drawingmusic.mp3 while user traces. Loop mode. Volume 30%.
/// AudioPlayer and asset loaded only when start() is called (lazy).
class DrawingMusicService {
  DrawingMusicService();

  static const _musicVolume = 0.3;

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _muted = false;

  AudioPlayer get _ensurePlayer {
    _player ??= AudioPlayer();
    return _player!;
  }

  Future<void> start({Future<void> Function()? stopOtherMusic}) async {
    if (stopOtherMusic != null) {
      await stopOtherMusic();
    }
    if (_isPlaying) return;
    try {
      final player = _ensurePlayer;
      await player.setAsset('packages/alfamon_trace/Assets/drawingmusic.mp3');
      await player.setLoopMode(LoopMode.all);
      await player.setVolume(_muted ? 0.0 : _musicVolume);
      await player.play();
      _isPlaying = true;
    } catch (e) {
      // ignore
    }
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    try {
      if (_player != null) {
        await _player!.setVolume(muted ? 0.0 : _musicVolume);
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    try {
      if (_player != null) {
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
