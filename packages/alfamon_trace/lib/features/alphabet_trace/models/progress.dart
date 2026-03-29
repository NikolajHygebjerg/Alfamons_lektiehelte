/// Progress for a single letter (0.0 to 1.0).
class LetterProgress {
  const LetterProgress({
    required this.letterId,
    required this.percentage,
    this.completedAt,
  });

  final String letterId;
  final double percentage;
  final DateTime? completedAt;

  LetterProgress copyWith({
    String? letterId,
    double? percentage,
    DateTime? completedAt,
  }) {
    return LetterProgress(
      letterId: letterId ?? this.letterId,
      percentage: percentage ?? this.percentage,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
