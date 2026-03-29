import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter K with 3 strokes from SVG assets.
/// Stroke 1: oppefra og ned (left vertical)
/// Stroke 2: oppefra og ned (upper diagonal)
/// Stroke 3: oppefra og ned (lower diagonal)
Future<Letter> loadLetterK() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/K_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/K_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/K_stroke3.svg'),
  ];
  return Letter(
    id: 'k',
    character: 'K',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Kaavax2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Kaavax1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Kaavaxtale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Kaavaxtale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Kaavax.wav',
  );
}
