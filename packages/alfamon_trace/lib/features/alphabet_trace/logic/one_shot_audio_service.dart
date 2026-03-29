import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Handles tale, tale2, and success sounds. All can be stopped via stop().
class OneShotAudioService {
  OneShotAudioService();

  AudioPlayer? _player;
  Completer<void>? _playCompleter;

  /// Plays and waits for completion. Stops when stop() is called.
  Future<void> playAndWait(String path) async {
    await stop();
    _player ??= AudioPlayer();
    _playCompleter = Completer<void>();
    StreamSubscription<PlayerState>? sub;
    try {
      await _player!.setAsset(path);
      await _player!.setSpeed(1.0);
      await _player!.play();
      sub = _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (_playCompleter != null && !_playCompleter!.isCompleted) {
            _playCompleter!.complete();
          }
        }
      });
      await _playCompleter!.future;
    } catch (_) {
      if (_playCompleter != null && !_playCompleter!.isCompleted) {
        _playCompleter!.complete();
      }
    } finally {
      await sub?.cancel();
      _playCompleter = null;
    }
  }

  /// Plays without waiting. Stops when stop() is called.
  Future<void> play(String path, {double speed = 1.0}) async {
    await stop();
    _player ??= AudioPlayer();
    try {
      await _player!.setAsset(path);
      await _player!.setSpeed(speed);
      await _player!.play();
    } catch (_) {}
  }

  /// Stops any playing one-shot audio.
  Future<void> stop() async {
    if (_playCompleter != null && !_playCompleter!.isCompleted) {
      _playCompleter!.complete();
    }
    _playCompleter = null;
    try {
      if (_player != null) {
        await _player!.stop();
        await _player!.seek(Duration.zero);
      }
    } catch (_) {}
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _playCompleter = null;
  }
}
