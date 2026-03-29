import 'package:hive/hive.dart';

import '../models/progress.dart';

/// Offline storage for letter progress using Hive.
class ProgressStorage {
  ProgressStorage(this._box);

  final Box<LetterProgress> _box;

  static const String _boxName = 'letter_progress';

  /// Opens the progress box. Call after Hive.initFlutter().
  static Future<Box<LetterProgress>> openBox() {
    return Hive.openBox<LetterProgress>(_boxName);
  }

  /// Loads all progress from storage.
  Map<String, LetterProgress> loadAll() {
    final map = <String, LetterProgress>{};
    for (final key in _box.keys) {
      final progress = _box.get(key);
      if (progress != null) {
        map[key as String] = progress;
      }
    }
    return map;
  }

  /// Saves progress for a single letter.
  void save(String letterId, LetterProgress progress) {
    _box.put(letterId, progress);
  }

  /// Saves all progress.
  void saveAll(Map<String, LetterProgress> progress) {
    _box.clear();
    for (final entry in progress.entries) {
      _box.put(entry.key, entry.value);
    }
  }
}
