import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/letters_repository.dart';
import 'drawing_music_service.dart';
import 'letter_screen_music_service.dart';
import 'one_shot_audio_service.dart';
import '../data/progress_storage.dart';
import '../models/letter.dart';
import '../models/progress.dart';

final lettersRepositoryProvider = Provider<LettersRepository>((ref) {
  return LettersRepository.instance;
});

final lettersProvider = FutureProvider<List<Letter>>((ref) {
  return ref.watch(lettersRepositoryProvider).loadLetters();
});

/// Storage for letter progress. Must be overridden in main() with Hive-backed storage.
final progressStorageProvider = Provider<ProgressStorage>((ref) {
  throw StateError('progressStorageProvider must be overridden in main()');
});

/// Progress per letter (0.0–1.0). Persisted via Hive when a letter is completed.
final progressProvider =
    StateNotifierProvider<ProgressNotifier, Map<String, LetterProgress>>((ref) {
  final storage = ref.watch(progressStorageProvider);
  return ProgressNotifier(storage);
});

class ProgressNotifier extends StateNotifier<Map<String, LetterProgress>> {
  ProgressNotifier(this._storage) : super(_storage.loadAll());

  final ProgressStorage _storage;

  void setProgress(String letterId, double percentage) {
    final progress = LetterProgress(
      letterId: letterId,
      percentage: percentage.clamp(0.0, 1.0),
      completedAt: percentage >= 1.0 ? DateTime.now() : null,
    );
    state = {...state, letterId: progress};
    if (percentage >= 1.0) {
      _storage.save(letterId, progress);
    }
  }

  void markCompleted(String letterId) {
    final progress = LetterProgress(
      letterId: letterId,
      percentage: 1.0,
      completedAt: DateTime.now(),
    );
    state = {...state, letterId: progress};
    _storage.save(letterId, progress);
  }

  LetterProgress progressFor(String letterId) {
    return state[letterId] ??
        LetterProgress(letterId: letterId, percentage: 0.0);
  }
}

/// Selected letter for tracing.
final selectedLetterProvider = StateProvider<Letter?>((ref) => null);

/// Next letter in alphabet order (wraps from Å to A). Null if loading/error.
final nextLetterProvider = Provider<Letter?>((ref) {
  final selected = ref.watch(selectedLetterProvider);
  final lettersAsync = ref.watch(lettersProvider);
  return lettersAsync.whenOrNull(
    data: (letters) {
      if (selected == null || letters.isEmpty) return null;
      final idx = letters.indexWhere((l) => l.id == selected.id);
      if (idx < 0) return null;
      final nextIdx = (idx + 1) % letters.length;
      return letters[nextIdx];
    },
  );
});

/// Current tracing progress for the selected letter (0.0–1.0).
final tracingProgressProvider = StateProvider<double>((ref) => 0.0);

/// Whether the letter has been fully traced and reveal is showing.
final showRevealProvider = StateProvider<bool>((ref) => false);

/// For path-based letters: index of the stroke currently being traced (0-based).
final currentStrokeIndexProvider = StateProvider<int>((ref) => 0);

/// For path-based letters: trace points for each completed stroke (persisted orange lines).
final completedTracePointsProvider =
    StateProvider<List<List<Offset>>>((ref) => []);

/// When true, show retry/X overlay (stroke drawn unsatisfactorily).
final showRetryOverlayProvider = StateProvider<bool>((ref) => false);

/// Trigger screen blink when stroke 1 completes (transition to stroke 2).
final showBlinkProvider = StateProvider<bool>((ref) => false);

/// Incremented when retry pressed; canvas clears trace on change.
final retryTriggerProvider = StateProvider<int>((ref) => 0);

/// Current stroke progress 0.0–1.0 for display (path-based letters).
final currentStrokeProgressProvider = StateProvider<double>((ref) => 0.0);

/// True when user has started drawing on current stroke (for showing end circle on stroke 2).
final hasStartedCurrentStrokeProvider = StateProvider<bool>((ref) => false);

/// Drawing music (drawingmusic.mp3) played while tracing.
final drawingMusicProvider = Provider<DrawingMusicService>((ref) {
  final service = DrawingMusicService();
  ref.onDispose(service.dispose);
  return service;
});

/// Whether drawing music is muted (does not affect success sound effects).
final musicMutedProvider = StateProvider<bool>((ref) => false);

/// True after first visit to letter screen (for Velkommentale vs bogstavmusik).
final hasVisitedLetterScreenProvider = StateProvider<bool>((ref) => false);

/// Optjente guldmønter i den aktuelle trace-session (synk til kiste når barnet forlader Trace).
final traceSessionCoinsEarnedProvider = StateProvider<int>((ref) => 0);

/// Bogstav-id'er der allerede har givet én mønt i **denne** trace-session.
/// ([setProgress] kan ramme 100% før [markCompleted], så "var bogstavet færdigt før?" er upålidelig.)
final traceSessionAwardedLetterIdsProvider =
    StateProvider<Set<String>>((ref) => {});

/// Letter screen music (bogstavmusik.mp3 or Velkommentale.mp3) on the letter grid.
final letterScreenMusicProvider = Provider<LetterScreenMusicService>((ref) {
  final service = LetterScreenMusicService();
  ref.onDispose(service.dispose);
  return service;
});

/// Tale, tale2, success sounds. Can be stopped via stop().
final oneShotAudioProvider = Provider<OneShotAudioService>((ref) {
  final service = OneShotAudioService();
  ref.onDispose(service.dispose);
  return service;
});

/// Stops all audio (letter music, drawing music, tale/tale2/success).
Future<void> stopAllAudio(WidgetRef ref) async {
  await ref.read(letterScreenMusicProvider).stop();
  await ref.read(drawingMusicProvider).stop();
  await ref.read(oneShotAudioProvider).stop();
}
