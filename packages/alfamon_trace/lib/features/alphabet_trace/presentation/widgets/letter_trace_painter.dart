import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/letter.dart';

/// Paints the letter outline and the user's trace.
/// Paths are scaled from normalized (0–100) to [size].
class LetterTracePainter extends CustomPainter {
  LetterTracePainter({
    required this.letter,
    required this.tracePoints,
    required this.progress,
    this.currentStrokeIndex = 0,
    this.completedTracePoints = const [],
    required this.outlineColor,
    required this.traceColor,
    required this.traceWidth,
  });

  final Letter letter;
  final List<Offset> tracePoints;
  final double progress;
  final int currentStrokeIndex;
  final List<List<Offset>> completedTracePoints;
  final Color outlineColor;
  final Color traceColor;
  final double traceWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _scaleFor(size) * letter.scaleFactor;
    final padding = size.shortestSide * 0.1;

    if (letter.usesPathStrokes) {
      _paintPathStrokes(canvas, size, scale, padding);
    } else {
      _paintOffsetStrokes(canvas, size, scale, padding);
    }
  }

  void _paintPathStrokes(
    Canvas canvas,
    Size size,
    double scale,
    double padding,
  ) {
    final tracePaint = Paint()
      ..color = traceColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = traceWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw letter outline from stroke paths (A, B, etc.)
    _paintPathStrokesOutline(canvas, size, scale, padding);

    // DEBUG: Vis stroke1 og stroke2
    _paintDebugStrokes(canvas, scale, padding);

    // Draw completed stroke traces (orange lines where user drew)
    for (final points in completedTracePoints) {
      if (points.isEmpty) continue;
      final path = Path();
      path.moveTo(
        padding + points[0].dx * scale,
        padding + points[0].dy * scale,
      );
      for (var i = 1; i < points.length; i++) {
        path.lineTo(
          padding + points[i].dx * scale,
          padding + points[i].dy * scale,
        );
      }
      canvas.drawPath(path, tracePaint);
    }

    // Draw trace points on current stroke
    if (tracePoints.isNotEmpty) {
      final path = Path();
      path.moveTo(
        padding + tracePoints[0].dx * scale,
        padding + tracePoints[0].dy * scale,
      );
      for (var i = 1; i < tracePoints.length; i++) {
        path.lineTo(
          padding + tracePoints[i].dx * scale,
          padding + tracePoints[i].dy * scale,
        );
      }
      canvas.drawPath(path, tracePaint);
    }
  }

  void _paintOffsetStrokes(
    Canvas canvas,
    Size size,
    double scale,
    double padding,
  ) {
    final outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = traceWidth * 0.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in letter.strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      path.moveTo(
        padding + stroke[0].dx * scale,
        padding + stroke[0].dy * scale,
      );
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(
          padding + stroke[i].dx * scale,
          padding + stroke[i].dy * scale,
        );
      }
      canvas.drawPath(path, outlinePaint);
    }

    if (tracePoints.isNotEmpty) {
      final tracePaint = Paint()
        ..color = traceColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = traceWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(
        padding + tracePoints[0].dx * scale,
        padding + tracePoints[0].dy * scale,
      );
      for (var i = 1; i < tracePoints.length; i++) {
        path.lineTo(
          padding + tracePoints[i].dx * scale,
          padding + tracePoints[i].dy * scale,
        );
      }
      canvas.drawPath(path, tracePaint);
    }
  }

  /// Tegner bogstavets outline ud fra stroke-paths.
  void _paintPathStrokesOutline(
    Canvas canvas,
    Size size,
    double scale,
    double padding,
  ) {
    if (letter.pathStrokes == null) return;

    final strokes = letter.pathStrokes!;
    final strokeWidth = size.shortestSide * 0.08;

    for (final path in strokes) {
      final scaledPath = Path();
      for (final metric in path.computeMetrics()) {
        final len = metric.length;
        if (len <= 0) continue;
        var first = true;
        for (var j = 0; j <= 80; j++) {
          final t = len * j / 80;
          final tangent = metric.getTangentForOffset(t);
          if (tangent != null) {
            final x = padding + tangent.position.dx * scale;
            final y = padding + tangent.position.dy * scale;
            if (first) {
              scaledPath.moveTo(x, y);
              first = false;
            } else {
              scaledPath.lineTo(x, y);
            }
          }
        }
      }

      // Hvid fyld (tynd) under sort streg
      final fillPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(scaledPath, fillPaint);

      // Sort streg (outline)
      final strokePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(scaledPath, strokePaint);
    }
  }

  void _paintDebugStrokes(Canvas canvas, double scale, double padding) {
    const showDebugStrokes = false; // Skjult
    if (!showDebugStrokes || letter.pathStrokes == null) return;

    final strokes = letter.pathStrokes!;
    final colors = [Colors.red, Colors.blue];
    for (var i = 0; i < strokes.length; i++) {
      final path = strokes[i];
      final paint = Paint()
        ..color = colors[i % colors.length].withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final scaledPath = Path();
      for (final metric in path.computeMetrics()) {
        final len = metric.length;
        if (len <= 0) continue;
        var first = true;
        for (var j = 0; j <= 50; j++) {
          final t = len * j / 50;
          final tangent = metric.getTangentForOffset(t);
          if (tangent != null) {
            final x = padding + tangent.position.dx * scale;
            final y = padding + tangent.position.dy * scale;
            if (first) {
              scaledPath.moveTo(x, y);
              first = false;
            } else {
              scaledPath.lineTo(x, y);
            }
          }
        }
      }
      canvas.drawPath(scaledPath, paint);
    }
  }

  double _scaleFor(Size size) {
    final padding = size.shortestSide * 0.2;
    final available = size.shortestSide - padding;
    return available / 100.0;
  }

  @override
  bool shouldRepaint(LetterTracePainter oldDelegate) {
    return oldDelegate.letter != letter ||
        oldDelegate.tracePoints != tracePoints ||
        oldDelegate.progress != progress ||
        oldDelegate.currentStrokeIndex != currentStrokeIndex ||
        oldDelegate.completedTracePoints != completedTracePoints;
  }
}
