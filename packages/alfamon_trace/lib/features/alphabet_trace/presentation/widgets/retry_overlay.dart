import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/alphabet_trace_provider.dart';
import '../../utils/play_tale.dart';

/// Overlay when stroke is drawn unsatisfactorily: Reload + X.
class RetryOverlay extends ConsumerWidget {
  const RetryOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showRetryOverlayProvider);
    if (!show) return const SizedBox.shrink();

    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RetryIconButton(
                    icon: Icons.replay,
                    onPressed: () {
                      ref.read(showRetryOverlayProvider.notifier).state = false;
                      ref.read(completedTracePointsProvider.notifier).state = [];
                      ref.read(currentStrokeIndexProvider.notifier).state = 0;
                      ref.read(tracingProgressProvider.notifier).state = 0;
                      ref.read(currentStrokeProgressProvider.notifier).state = 0;
                      ref.read(hasStartedCurrentStrokeProvider.notifier).state = false;
                      ref.read(retryTriggerProvider.notifier).state++;
                    },
                  ),
                  const SizedBox(width: 32),
                  _RetryIconButton(
                    icon: Icons.close,
                    onPressed: () async {
                      await stopAllAudio(ref);
                      ref.read(showRetryOverlayProvider.notifier).state = false;
                      ref.read(selectedLetterProvider.notifier).state = null;
                      ref.read(hasStartedCurrentStrokeProvider.notifier).state = false;
                      ref.read(completedTracePointsProvider.notifier).state = [];
                      ref.read(currentStrokeIndexProvider.notifier).state = 0;
                      ref.read(tracingProgressProvider.notifier).state = 0;
                      ref.read(currentStrokeProgressProvider.notifier).state = 0;
                    },
                  ),
                  const SizedBox(width: 32),
                  _RetryIconButton(
                    icon: Icons.arrow_forward,
                    onPressed: () async {
                      final next = ref.read(nextLetterProvider);
                      if (next == null) return;
                      await stopAllAudio(ref);
                      ref.read(showRetryOverlayProvider.notifier).state = false;
                      ref.read(selectedLetterProvider.notifier).state = next;
                      ref.read(tracingProgressProvider.notifier).state = 0;
                      ref.read(showRevealProvider.notifier).state = false;
                      ref.read(currentStrokeIndexProvider.notifier).state = 0;
                      ref.read(completedTracePointsProvider.notifier).state = [];
                      ref.read(showBlinkProvider.notifier).state = false;
                      ref.read(currentStrokeProgressProvider.notifier).state = 0;
                      ref.read(hasStartedCurrentStrokeProvider.notifier).state = false;
                      await playTaleAndWait(ref, next.alfamonTalePath);
                      final music = ref.read(drawingMusicProvider);
                      await music.start();
                      music.setMuted(ref.read(musicMutedProvider));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large child-friendly icon-only button.
class _RetryIconButton extends StatelessWidget {
  const _RetryIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(56),
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 56, color: Colors.blue.shade700),
        ),
      ),
    );
  }
}
