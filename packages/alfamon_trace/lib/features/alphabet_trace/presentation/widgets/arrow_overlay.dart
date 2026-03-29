import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/alphabet_trace_provider.dart';
import '../../models/letter.dart';
import 'path_progress_helper.dart';

/// Blinkende cirkler (start/slut) + animeret prik langs stregen.
class ArrowOverlay extends ConsumerWidget {
  const ArrowOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letter = ref.watch(selectedLetterProvider);
    final progress = ref.watch(tracingProgressProvider);
    final showReveal = ref.watch(showRevealProvider);
    final showRetry = ref.watch(showRetryOverlayProvider);

    if (letter == null || showReveal || showRetry) return const SizedBox.shrink();

    final currentStrokeIndex = ref.watch(currentStrokeIndexProvider);
    final hasStarted = ref.watch(hasStartedCurrentStrokeProvider);

    return IgnorePointer(
      child: _StrokeGuideOverlay(
        letter: letter,
        progress: progress,
        currentStrokeIndex: currentStrokeIndex,
        hasStartedCurrentStroke: hasStarted,
      ),
    );
  }
}

class _StrokeGuideOverlay extends StatefulWidget {
  const _StrokeGuideOverlay({
    required this.letter,
    required this.progress,
    required this.currentStrokeIndex,
    required this.hasStartedCurrentStroke,
  });

  final Letter letter;
  final double progress;
  final int currentStrokeIndex;
  final bool hasStartedCurrentStroke;

  @override
  State<_StrokeGuideOverlay> createState() => _StrokeGuideOverlayState();
}

class _StrokeGuideOverlayState extends State<_StrokeGuideOverlay>
    with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  (Offset start, Offset end)? _startEndForPath(Path path) {
    final points = samplePathPoints(path, count: 2);
    if (points.length < 2) return null;
    return (points.first, points.last);
  }

  Offset? _pointAtProgress(Path path, double t) {
    final points = samplePathPoints(path, count: 100);
    if (points.isEmpty) return null;
    final i = (t * (points.length - 1)).round().clamp(0, points.length - 1);
    return points[i];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.progress >= 1.0) return const SizedBox.shrink();
    if (!widget.letter.usesPathStrokes || widget.letter.pathStrokes == null) {
      return const SizedBox.shrink();
    }

    final strokes = widget.letter.pathStrokes!;
    final idx = widget.currentStrokeIndex;
    if (idx >= strokes.length) return const SizedBox.shrink();

    final path = strokes[idx];
    final startEnd = _startEndForPath(path);
    if (startEnd == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final shortest = w < h ? w : h;
        final scale = (shortest - shortest * 0.2) / 100.0 * widget.letter.scaleFactor;
        final padding = shortest * 0.1;

        Offset toScreen(Offset p) => Offset(
              padding + p.dx * scale,
              padding + p.dy * scale,
            );

        final startScreen = toScreen(startEnd.$1);
        final endScreen = toScreen(startEnd.$2);

        final showEndCircle = idx == 0 || widget.hasStartedCurrentStroke;

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _blinkController,
                builder: (context, _) {
                  final opacity = 0.5 + 0.5 * _blinkController.value;
                  return Stack(
                    children: [
                      _BlinkingCircle(center: startScreen, opacity: opacity),
                      if (showEndCircle)
                        _BlinkingCircle(center: endScreen, opacity: opacity),
                    ],
                  );
                },
              ),
              AnimatedBuilder(
                animation: _dotController,
                builder: (context, _) {
                  final t = _dotController.value;
                  final pt = _pointAtProgress(path, t);
                  if (pt == null) return const SizedBox.shrink();
                  final screenPt = toScreen(pt);
                  return Positioned(
                    left: screenPt.dx - 8,
                    top: screenPt.dy - 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade400,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlinkingCircle extends StatelessWidget {
  const _BlinkingCircle({
    required this.center,
    required this.opacity,
  });

  final Offset center;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 16,
      top: center.dy - 16,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.orange.shade400.withOpacity(opacity),
            width: 4,
          ),
          color: Colors.transparent,
        ),
      ),
    );
  }
}
