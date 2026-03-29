import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter X with 2 strokes from SVG assets.
/// Stroke 1: oppefra og ned (diagonal)
/// Stroke 2: oppefra og ned (diagonal)
Future<Letter> loadLetterX() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/X_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/X_stroke2.svg'),
  ];
  return Letter(
    id: 'x',
    character: 'X',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Xbug2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Xbug1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Xbugtale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Xbugtale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Xbug.wav',
  );
}
