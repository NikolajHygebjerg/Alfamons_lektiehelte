import 'dart:math' as math;

/// Faste udviklingstærskler for alle Alfamons (total point på den aktive avatar).
///
/// - 0 = æg
/// - 10 = niveau 1
/// - 40 = niveau 2
/// - 80 = niveau 3
/// - 130 = niveau 4 (fuldt udviklet)
///
/// Bruges ens i [task_completion], forsiden og Alfamons-biblioteket så billeder
/// altid matcher pointene.
class AlfamonEvolution {
  AlfamonEvolution._();

  static const int maxProgressPoints = 130;

  /// Kumulative tærskler: index = trin (0..4).
  static const List<int> stageThresholds = [0, 10, 40, 80, 130];

  /// Trin 0..4 (æg + 4 niveauer).
  static int tierFromTotalPoints(int points) {
    final p = math.min(math.max(0, points), maxProgressPoints);
    for (var i = stageThresholds.length - 1; i >= 0; i--) {
      if (p >= stageThresholds[i]) return i;
    }
    return 0;
  }

  /// PostgREST kan levere heltal som [num] — undgå `as int`-fejl ved runtime.
  static int stageIndexFromJson(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static int pointsFromJson(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return 0;
  }

  /// Sorterede `stage_index` fra `avatar_stages` (stigende).
  static List<int> sortedStageIndicesFromRows(List<dynamic> stages) {
    final list = <int>[];
    for (final s in stages) {
      list.add(stageIndexFromJson((s as Map)['stage_index']));
    }
    list.sort();
    return list;
  }

  /// Hvilken `stage_index` i databasen der skal vises for disse point.
  /// Mapper trin 0..4 til plads 0..n-1 i listen (fx 5 stadier i DB).
  static int stageIndexFromPoints(int points, List<int> sortedStageIndices) {
    if (sortedStageIndices.isEmpty) return 0;
    final tier = tierFromTotalPoints(points);
    final slot = math.min(tier, sortedStageIndices.length - 1);
    return sortedStageIndices[slot];
  }
}
