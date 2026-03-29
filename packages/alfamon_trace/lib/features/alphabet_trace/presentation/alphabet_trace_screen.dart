import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../logic/alphabet_trace_provider.dart';
import '../utils/play_tale.dart';
import 'widgets/alfamon_reveal.dart';
import 'widgets/arrow_overlay.dart';
import 'widgets/blink_overlay.dart';
import 'widgets/letter_selector.dart';
import 'widgets/letter_trace_canvas.dart';
import 'widgets/retry_overlay.dart';
import 'widgets/stroke_progress_indicator.dart';

/// Letters with tracing area on the left.
const _leftLetters = {
  'b', 'c', 'd', 'e', 'f', 'j', 'k', 'l', 'n', 'p', 'q', 'r', 's', 't',
  'v', 'x', 'y', 'ae', 'oe', 'aa',
};

bool _tracingOnLeft(String letterId) => _leftLetters.contains(letterId);

/// Right margin for left-side letters. B og J helt ud til venstre = 5%.
double _rightMarginForLeftLetter(String letterId) {
  if (letterId == 'b' || letterId == 'j') return 0.05;
  if (letterId == 'p') return 0.15;
  return 0.25;
}

/// Tablet-friendly screen for tracing letters.
/// Full-screen letter grid; when A or B selected, shows split layout with tracing.
class AlphabetTraceScreen extends ConsumerWidget {
  const AlphabetTraceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showReveal = ref.watch(showRevealProvider);
    final selectedLetter = ref.watch(selectedLetterProvider);
    final hasBackground = selectedLetter?.alfamonBackgroundPath != null && !showReveal;

    return Scaffold(
      extendBodyBehindAppBar: hasBackground,
      backgroundColor: selectedLetter == null ? Colors.black : null,
      appBar: selectedLetter != null
          ? AppBar(
              backgroundColor: hasBackground ? Colors.transparent : null,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () async {
                  await stopAllAudio(ref);
                  if (!context.mounted) return;
                  ref.read(selectedLetterProvider.notifier).state = null;
                  ref.read(tracingProgressProvider.notifier).state = 0;
                  ref.read(currentStrokeIndexProvider.notifier).state = 0;
                  ref.read(completedTracePointsProvider.notifier).state = [];
                  ref.read(showRetryOverlayProvider.notifier).state = false;
                  ref.read(showBlinkProvider.notifier).state = false;
                  ref.read(currentStrokeProgressProvider.notifier).state = 0;
                },
              ),
              title: const SizedBox.shrink(),
              toolbarHeight: 48,
            )
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  await stopAllAudio(ref);
                  if (!context.mounted) return;
                  if (context.canPop()) context.pop();
                },
              ),
              title: const Text('Vælg bogstav'),
              toolbarHeight: 48,
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (selectedLetter?.alfamonBackgroundPath != null && !showReveal)
            Positioned.fill(
              child: Image.asset(
                selectedLetter!.alfamonBackgroundPath!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          if (showReveal)
            AlfamonReveal(
              onGenindlaes: () {
                ref.read(showRevealProvider.notifier).state = false;
                ref.read(tracingProgressProvider.notifier).state = 0;
                ref.read(currentStrokeIndexProvider.notifier).state = 0;
                ref.read(completedTracePointsProvider.notifier).state = [];
                ref.read(showRetryOverlayProvider.notifier).state = false;
                ref.read(showBlinkProvider.notifier).state = false;
                ref.read(currentStrokeProgressProvider.notifier).state = 0;
              },
              onAfbryd: () async {
                await stopAllAudio(ref);
                ref.read(showRevealProvider.notifier).state = false;
                ref.read(selectedLetterProvider.notifier).state = null;
                ref.read(tracingProgressProvider.notifier).state = 0;
                ref.read(currentStrokeIndexProvider.notifier).state = 0;
                ref.read(completedTracePointsProvider.notifier).state = [];
                ref.read(showRetryOverlayProvider.notifier).state = false;
                ref.read(showBlinkProvider.notifier).state = false;
                ref.read(currentStrokeProgressProvider.notifier).state = 0;
              },
              onNaeste: () async {
                final next = ref.read(nextLetterProvider);
                if (next == null) return;
                await stopAllAudio(ref);
                ref.read(showRevealProvider.notifier).state = false;
                ref.read(selectedLetterProvider.notifier).state = next;
                ref.read(tracingProgressProvider.notifier).state = 0;
                ref.read(currentStrokeIndexProvider.notifier).state = 0;
                ref.read(completedTracePointsProvider.notifier).state = [];
                ref.read(showRetryOverlayProvider.notifier).state = false;
                ref.read(showBlinkProvider.notifier).state = false;
                ref.read(currentStrokeProgressProvider.notifier).state = 0;
                ref.read(hasStartedCurrentStrokeProvider.notifier).state = false;
                await playTaleAndWait(ref, next.alfamonTalePath);
                final music = ref.read(drawingMusicProvider);
                await music.start();
                music.setMuted(ref.read(musicMutedProvider));
              },
            )
          else if (selectedLetter != null)
            Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    if (_tracingOnLeft(selectedLetter!.id)) ...[
                      const Expanded(child: _TracingArea()),
                      SizedBox(
                          width: MediaQuery.of(context).size.width *
                              (_rightMarginForLeftLetter(selectedLetter!.id))),
                    ] else if (selectedLetter!.id == 'g') ...[
                      SizedBox(
                          width: MediaQuery.of(context).size.width * 0.15),
                      const Expanded(child: _TracingArea()),
                    ] else ...[
                      SizedBox(
                          width: MediaQuery.of(context).size.width * 0.25),
                      const Expanded(child: _TracingArea()),
                    ],
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).size.height * 0.08,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _MusicMuteButton(),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            const SafeArea(child: LetterSelector()),
        ],
      ),
    );
  }
}

class _MusicMuteButton extends ConsumerWidget {
  static const _size = 56.0;
  static const _iconSize = 28.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMuted = ref.watch(musicMutedProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final newMuted = !ref.read(musicMutedProvider);
            ref.read(musicMutedProvider.notifier).state = newMuted;
            final music = ref.read(drawingMusicProvider);
            if (newMuted) {
              music.setMuted(true);
              await music.stop();
            } else {
              music.setMuted(false);
              music.start();
            }
          },
          borderRadius: BorderRadius.circular(_size / 2),
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isMuted ? Icons.music_off : Icons.music_note,
              color: Colors.blue.shade700,
              size: _iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _TracingArea extends StatelessWidget {
  const _TracingArea();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const LetterTraceCanvas(),
        const ArrowOverlay(),
        const BlinkOverlay(),
        const RetryOverlay(),
        const StrokeProgressIndicator(),
      ],
    );
  }
}

