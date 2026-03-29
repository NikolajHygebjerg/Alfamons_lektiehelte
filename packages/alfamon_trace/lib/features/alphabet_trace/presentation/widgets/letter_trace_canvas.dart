import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/alphabet_trace_provider.dart';
import '../../models/letter.dart';
import 'letter_trace_painter.dart';
import 'path_progress_helper.dart';

/// Canvas for tracing a letter with finger. Uses CustomPainter.
class LetterTraceCanvas extends ConsumerStatefulWidget {
  const LetterTraceCanvas({super.key});

  @override
  ConsumerState<LetterTraceCanvas> createState() => _LetterTraceCanvasState();
}

class _LetterTraceCanvasState extends ConsumerState<LetterTraceCanvas> {
  final List<Offset> _tracePoints = [];
  String? _lastLetterId;
  int _lastRetryTrigger = 0;
  int? _activePointerId;
  static const double _tolerance = 18.0;

  void _onPanStart(Letter letter) {
    if (!ref.read(musicMutedProvider)) {
      ref.read(drawingMusicProvider).start();
    }
  }

  void _onPanUpdate(Letter letter, Size size, Offset local) {
    if (_lastLetterId != letter.id) {
      _lastLetterId = letter.id;
      _tracePoints.clear();
    }

    if (letter.usesPathStrokes) {
      _onPanUpdatePathStrokes(letter, size, local);
    } else {
      _onPanUpdateOffsetStrokes(letter, size, local);
    }
    setState(() {});
  }

  void _onPanUpdatePathStrokes(Letter letter, Size size, Offset local) {
    final strokes = letter.pathStrokes!;
    final currentIndex = ref.read(currentStrokeIndexProvider);
    if (currentIndex >= strokes.length) return;

    final scale = _scaleFor(size) * letter.scaleFactor;
    final padding = size.shortestSide * 0.1;
    final normalized = Offset(
      (local.dx - padding) / scale,
      (local.dy - padding) / scale,
    );

    _tracePoints.add(normalized);
    ref.read(hasStartedCurrentStrokeProvider.notifier).state = true;

    final currentPath = strokes[currentIndex];
    final failThreshold = 31.5 / scale;

    // Fail if drawing >5mm outside path (streger fra hånden)
    if (isTraceMarkedlyWrong(currentPath, _tracePoints, failThresholdUnits: failThreshold)) {
      _activePointerId = null;
      ref.read(drawingMusicProvider).stop();
      ref.read(showRetryOverlayProvider.notifier).state = true;
      return;
    }

    final strokeProgress =
        computePathProgress(currentPath, _tracePoints, tolerance: _tolerance);

    final completedCount = ref.read(completedTracePointsProvider).length;
    final totalStrokes = strokes.length;
    final overallProgress =
        (completedCount + strokeProgress) / totalStrokes;

    ref.read(tracingProgressProvider.notifier).state = overallProgress;
    ref.read(progressProvider.notifier).setProgress(letter.id, overallProgress);
    ref.read(currentStrokeProgressProvider.notifier).state = strokeProgress;
  }

  void _onPanEndPathStrokes(Letter letter, Size size) {
    final strokes = letter.pathStrokes!;
    final currentIndex = ref.read(currentStrokeIndexProvider);
    if (currentIndex >= strokes.length) return;

    final currentPath = strokes[currentIndex];
    final scale = _scaleFor(size) * letter.scaleFactor;

    // If user hasn't reached the end: fail if markedly wrong, else wait for more drawing.
    if (!hasReachedEndOfPath(currentPath, _tracePoints, tolerance: 20.0)) {
      final failThreshold = 31.5 / scale;
      if (isTraceMarkedlyWrong(currentPath, _tracePoints, failThresholdUnits: failThreshold)) {
        _activePointerId = null;
        ref.read(drawingMusicProvider).stop();
        ref.read(showRetryOverlayProvider.notifier).state = true;
      }
      return;
    }

    final strokeProgress =
        computePathProgress(currentPath, _tracePoints, tolerance: _tolerance);

    final isLastStroke = currentIndex == strokes.length - 1;

    if (strokeProgress >= 0.45) {
      ref.read(completedTracePointsProvider.notifier).state = [
        ...ref.read(completedTracePointsProvider),
        List.from(_tracePoints),
      ];
      _tracePoints.clear();

      if (isLastStroke) {
        _onLetterCompleted(letter);
      } else {
        ref.read(currentStrokeIndexProvider.notifier).state = currentIndex + 1;
        final newProgress = (currentIndex + 1) / strokes.length;
        ref.read(tracingProgressProvider.notifier).state = newProgress;
        ref.read(progressProvider.notifier).setProgress(letter.id, newProgress);
        ref.read(showBlinkProvider.notifier).state = true;
        ref.read(currentStrokeProgressProvider.notifier).state = 0;
        ref.read(hasStartedCurrentStrokeProvider.notifier).state = false;
      }
    } else {
      _activePointerId = null;
      ref.read(drawingMusicProvider).stop();
      ref.read(showRetryOverlayProvider.notifier).state = true;
    }
  }

  void _onPanUpdateOffsetStrokes(Letter letter, Size size, Offset local) {
    final scale = _scaleFor(size) * letter.scaleFactor;
    final padding = size.shortestSide * 0.1;
    final normalized = Offset(
      (local.dx - padding) / scale,
      (local.dy - padding) / scale,
    );

    _tracePoints.add(normalized);

    final progress = _computeOffsetProgress(letter);
    ref.read(tracingProgressProvider.notifier).state = progress;
    ref.read(progressProvider.notifier).setProgress(letter.id, progress);

    if (progress >= 1.0) {
      _onLetterCompleted(letter);
    }
  }

  Future<void> _onLetterCompleted(Letter letter) async {
    ref.read(drawingMusicProvider).stop();
    ref.read(progressProvider.notifier).markCompleted(letter.id);
    final tale2Path = letter.alfamonTale2Path;
    if (tale2Path != null && tale2Path.isNotEmpty) {
      await ref.read(oneShotAudioProvider).playAndWait(tale2Path);
    }
    if (!mounted) return;
    ref.read(showRevealProvider.notifier).state = true;
  }

  double _scaleFor(Size size) {
    final padding = size.shortestSide * 0.2;
    final available = size.shortestSide - padding;
    return available / 100.0;
  }

  double _computeOffsetProgress(Letter letter) {
    final visited = <int>{};
    var segmentIndex = 0;

    for (final stroke in letter.strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        final a = stroke[i];
        final b = stroke[i + 1];

        for (final pt in _tracePoints) {
          final dist = _pointToSegmentDistance(pt, a, b);
          if (dist <= _tolerance) {
            visited.add(segmentIndex);
            break;
          }
        }
        segmentIndex++;
      }
    }

    if (segmentIndex == 0) return 0.0;
    return (visited.length / segmentIndex).clamp(0.0, 1.0);
  }

  double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) /
        (ab.dx * ab.dx + ab.dy * ab.dy + 1e-10);
    final tClamped = t.clamp(0.0, 1.0);
    final closest = Offset(
      a.dx + tClamped * ab.dx,
      a.dy + tClamped * ab.dy,
    );
    return (p - closest).distance;
  }

  @override
  Widget build(BuildContext context) {
    final letter = ref.watch(selectedLetterProvider);
    final progress = ref.watch(tracingProgressProvider);
    final currentStrokeIndex = ref.watch(currentStrokeIndexProvider);
    final completedTracePoints = ref.watch(completedTracePointsProvider);
    final retryTrigger = ref.watch(retryTriggerProvider);

    if (retryTrigger != _lastRetryTrigger) {
      _lastRetryTrigger = retryTrigger;
      _tracePoints.clear();
      _activePointerId = null;
    }

    if (letter == null) {
      return Center(
        child: Text(
          'Vælg et bogstav',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return Listener(
          onPointerDown: (event) {
            if (_activePointerId != null) return;
            _activePointerId = event.pointer;
            _onPanStart(letter);
          },
          onPointerMove: (event) {
            if (event.pointer != _activePointerId) return;
            _onPanUpdate(letter, size, event.localPosition);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) return;
            if (letter.usesPathStrokes) {
              _onPanEndPathStrokes(letter, size);
            }
            _activePointerId = null;
          },
          onPointerCancel: (event) {
            if (event.pointer == _activePointerId) {
              _activePointerId = null;
            }
          },
          child: CustomPaint(
            size: size,
            painter: LetterTracePainter(
              letter: letter,
              tracePoints: List.from(_tracePoints),
              progress: progress,
              currentStrokeIndex: currentStrokeIndex,
              completedTracePoints: completedTracePoints,
              outlineColor: Colors.blue.shade300,
              traceColor: Colors.orange,
              traceWidth: 20,
            ),
          ),
        );
      },
    );
  }
}
