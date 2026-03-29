import 'dart:ui';

/// Samples points along a [Path] for progress detection.
List<Offset> samplePathPoints(Path path, {int count = 50}) {
  final points = <Offset>[];
  final metrics = path.computeMetrics();
  for (final metric in metrics) {
    final length = metric.length;
    if (length <= 0) continue;
    for (var i = 0; i <= count; i++) {
      final offset = length * i / count;
      final tangent = metric.getTangentForOffset(offset);
      if (tangent != null) {
        points.add(tangent.position);
      }
    }
  }
  return points;
}

/// Computes progress (0.0–1.0) for tracing a path based on trace points.
double computePathProgress(
  Path path,
  List<Offset> tracePoints, {
  double tolerance = 12.0,
}) {
  final samplePoints = samplePathPoints(path);
  if (samplePoints.isEmpty) return 0.0;

  var visited = 0;
  for (final sample in samplePoints) {
    for (final pt in tracePoints) {
      if ((pt - sample).distance <= tolerance) {
        visited++;
        break;
      }
    }
  }
  return (visited / samplePoints.length).clamp(0.0, 1.0);
}

/// Minimum distance from point to any point on the path.
double distanceFromPointToPath(Path path, Offset point) {
  final samplePoints = samplePathPoints(path, count: 80);
  if (samplePoints.isEmpty) return double.infinity;
  var minDist = double.infinity;
  for (final p in samplePoints) {
    final d = (point - p).distance;
    if (d < minDist) minDist = d;
  }
  return minDist;
}

/// True if trace is markedly wrong (points far outside the path).
/// [failThresholdUnits] in normalized 0-100 space.
/// For ~5mm: use failThresholdUnits = 31.5 / scale, where scale = (shortest*0.8)/100.
bool isTraceMarkedlyWrong(
  Path path,
  List<Offset> tracePoints, {
  required double failThresholdUnits,
  int minPointsToCheck = 2,
}) {
  if (tracePoints.length < minPointsToCheck) return false;
  for (var i = tracePoints.length - minPointsToCheck; i < tracePoints.length; i++) {
    if (distanceFromPointToPath(path, tracePoints[i]) > failThresholdUnits) {
      return true;
    }
  }
  return false;
}

/// True if the user has traced near the end of the path (reached the bottom/end).
bool hasReachedEndOfPath(
  Path path,
  List<Offset> tracePoints, {
  double tolerance = 18.0,
}) {
  final samplePoints = samplePathPoints(path);
  if (samplePoints.isEmpty || tracePoints.isEmpty) return false;

  final endPoint = samplePoints.last;
  for (final pt in tracePoints) {
    if ((pt - endPoint).distance <= tolerance) return true;
  }
  return false;
}
