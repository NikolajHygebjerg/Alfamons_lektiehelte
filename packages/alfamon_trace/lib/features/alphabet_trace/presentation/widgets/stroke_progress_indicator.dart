import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/alphabet_trace_provider.dart';

/// Shows current stroke progress as an orange fill bar (no numbers).
class StrokeProgressIndicator extends ConsumerWidget {
  const StrokeProgressIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letter = ref.watch(selectedLetterProvider);
    final currentStrokeIndex = ref.watch(currentStrokeIndexProvider);
    final progress = ref.watch(currentStrokeProgressProvider);
    final showReveal = ref.watch(showRevealProvider);
    final showRetry = ref.watch(showRetryOverlayProvider);

    if (letter == null ||
        !letter.usesPathStrokes ||
        showReveal ||
        showRetry ||
        currentStrokeIndex >= (letter.pathStrokes?.length ?? 0)) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 24,
      right: 24,
      bottom: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 14,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade400),
        ),
      ),
    );
  }
}
