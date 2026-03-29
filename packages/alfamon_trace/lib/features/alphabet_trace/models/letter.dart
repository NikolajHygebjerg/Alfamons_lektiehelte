import 'dart:ui';

/// A letter that can be traced, with one or more strokes.
class Letter {
  const Letter({
    required this.id,
    required this.character,
    required this.strokes,
    this.pathStrokes,
    this.alfamonAssetPath,
    this.alfamonBackgroundPath,
    this.alfamonSuccessSoundPath,
    this.alfamonTalePath,
    this.alfamonTale2Path,
    this.scaleFactor = 1.0,
  });

  final String id;
  final String character;
  final List<List<Offset>> strokes;
  /// When non-null, use these Path strokes (e.g. from SVG) instead of [strokes].
  final List<Path>? pathStrokes;
  final String? alfamonAssetPath;
  /// Background image when letter is selected (e.g. Atiach1.png, Bezzle1.png).
  final String? alfamonBackgroundPath;
  /// Sound to play on success (e.g. Atiach.wav, Bezzle.aiff).
  final String? alfamonSuccessSoundPath;
  /// Sound when entering letter page (e.g. Atiachtale.m4a).
  final String? alfamonTalePath;
  /// Sound when completing letter, before success reveal (e.g. Atiachtale2.m4a).
  final String? alfamonTale2Path;
  /// Scale factor for display (e.g. 1.15 = 15% bigger).
  final double scaleFactor;

  /// Whether this letter uses Path-based strokes (from SVG).
  bool get usesPathStrokes => pathStrokes != null && pathStrokes!.isNotEmpty;
}
