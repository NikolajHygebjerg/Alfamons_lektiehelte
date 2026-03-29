import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:svg_path_parser/svg_path_parser.dart';

/// SVG viewBox used by letter stroke assets (0 0 11812 11812).
const double _svgViewBoxSize = 11812;

/// Target coordinate range for canvas (0–100).
const double _targetSize = 100;

/// Loads a Path from an SVG asset and normalizes to 0–100 coordinates.
///
/// Expects the SVG to have a single `path` element with a `d` attribute.
/// The path is scaled from [viewBox] to fit in [0, 100].
Future<Path> loadPathFromSvg(String assetPath) async {
  final svgString = await rootBundle.loadString(assetPath);
  final pathD = _extractPathD(svgString);
  if (pathD == null || pathD.isEmpty) {
    return Path();
  }

  final rawPath = parseSvgPath(pathD);
  return _normalizePath(rawPath);
}

String? _extractPathD(String svg) {
  final match = RegExp(r'<path\s[^>]*\bd="([^"]+)"').firstMatch(svg);
  return match?.group(1);
}

/// Scales path from SVG viewBox (11812) to 0–100.
Path _normalizePath(Path path) {
  const scale = _targetSize / _svgViewBoxSize;
  final matrix = Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
  return path.transform(matrix.storage);
}

/// Offsets path points toward center (for A: stroke1 toward triangle center).
Path offsetPathTowardCenter(Path path, double centerX, double centerY, double amount) {
  final result = Path();
  for (final metric in path.computeMetrics()) {
    final len = metric.length;
    if (len <= 0) continue;
    var first = true;
    for (var i = 0; i <= 80; i++) {
      final t = len * i / 80;
      final tangent = metric.getTangentForOffset(t);
      if (tangent != null) {
        var x = tangent.position.dx;
        var y = tangent.position.dy;
        final dx = centerX - x;
        final dy = centerY - y;
        final dist = (dx * dx + dy * dy).abs();
        if (dist > 0.01) {
          final factor = amount / math.sqrt(dist);
          x += dx * factor;
          y += dy * factor;
        }
        if (first) {
          result.moveTo(x, y);
          first = false;
        } else {
          result.lineTo(x, y);
        }
      }
    }
  }
  return result;
}

/// Offsets path vertically (for A: stroke2 bar down into crossbar center).
Path offsetPathVertical(Path path, double dy) {
  final result = Path();
  for (final metric in path.computeMetrics()) {
    final len = metric.length;
    if (len <= 0) continue;
    var first = true;
    for (var i = 0; i <= 80; i++) {
      final t = len * i / 80;
      final tangent = metric.getTangentForOffset(t);
      if (tangent != null) {
        final x = tangent.position.dx;
        final y = tangent.position.dy + dy;
        if (first) {
          result.moveTo(x, y);
          first = false;
        } else {
          result.lineTo(x, y);
        }
      }
    }
  }
  return result;
}
