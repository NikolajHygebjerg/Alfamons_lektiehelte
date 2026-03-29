import 'package:hive/hive.dart';

import '../models/progress.dart';

/// Hive TypeAdapter for [LetterProgress].
class LetterProgressAdapter extends TypeAdapter<LetterProgress> {
  @override
  final int typeId = 0;

  @override
  LetterProgress read(BinaryReader reader) {
    final letterId = reader.read() as String;
    final percentage = reader.read() as double;
    final completedAtMs = reader.read() as int;
    final completedAt = completedAtMs >= 0
        ? DateTime.fromMillisecondsSinceEpoch(completedAtMs)
        : null;

    return LetterProgress(
      letterId: letterId,
      percentage: percentage,
      completedAt: completedAt,
    );
  }

  @override
  void write(BinaryWriter writer, LetterProgress obj) {
    writer.write(obj.letterId);
    writer.write(obj.percentage);
    writer.write(obj.completedAt?.millisecondsSinceEpoch ?? -1);
  }
}
