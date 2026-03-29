import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter Y with 3 strokes from SVG assets.
/// Stroke 1: oppefra og ned (left diagonal)
/// Stroke 2: oppefra og ned (right diagonal)
/// Stroke 3: oppefra og ned (vertical stem)
Future<Letter> loadLetterY() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/Y_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/Y_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/Y_stroke3.svg'),
  ];
  return Letter(
    id: 'y',
    character: 'Y',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Yglifax2.png',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Yglifax1.png',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Yglifaxtale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Yglifaxtale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Yglifax.wav',
  );
}
