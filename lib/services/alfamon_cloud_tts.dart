import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/math_tutor_lesson.dart';

/// Oplæsning via Supabase Edge Function + Google TTS — samme stemme for alle,
/// uafhængigt af enhedens systemstemmer. Kræver logget-in session og internet.
class AlfamonCloudTts {
  AlfamonCloudTts() : _player = AudioPlayer();

  final AudioPlayer _player;

  /// Sand når brugeren har et gyldigt session — så kan cloud-tale forsøges.
  static bool get hasSession {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Afspil én tekststreng (trimmet/rensning som til system-TTS).
  /// Returnerer `true` hvis oplæsning startede og spillede færdig.
  Future<bool> speak(String text) async {
    final plain = mathTutorPlainTextForTts(text);
    if (plain.isEmpty) return false;
    if (!hasSession) return false;

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'synthesize-speech',
        body: {'text': plain},
      );
      if (res.status != 200) {
        debugPrint(
          'synthesize-speech: HTTP ${res.status} data=${res.data}',
        );
        return false;
      }
      if (res.data is! Map) return false;
      final map = Map<String, dynamic>.from(res.data as Map);
      final b64 = map['audioContent'] as String?;
      if (b64 == null || b64.isEmpty) return false;

      final bytes = base64Decode(b64);
      await _player.stop();

      if (kIsWeb) {
        final uri = Uri.dataFromBytes(bytes, mimeType: 'audio/mpeg');
        await _player.setAudioSource(AudioSource.uri(uri));
      } else {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/alfamon_tts_${DateTime.now().microsecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        await _player.setFilePath(file.path);
      }

      final doneFuture = _player.processingStateStream
          .where((s) => s == ProcessingState.completed)
          .first;
      await _player.play();
      await doneFuture.timeout(const Duration(minutes: 2));
      return true;
    } catch (e, st) {
      debugPrint('AlfamonCloudTts: $e\n$st');
      return false;
    }
  }
}
