import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/alphabet_trace_provider.dart';

/// Plays tale and waits for completion. Uses OneShotAudioService (stoppable via stopAllAudio).
Future<void> playTaleAndWait(WidgetRef ref, String? path) async {
  if (path == null || path.isEmpty) return;
  await ref.read(oneShotAudioProvider).playAndWait(path);
}
