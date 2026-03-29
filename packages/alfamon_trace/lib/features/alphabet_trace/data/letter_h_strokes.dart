import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter H with 3 strokes from SVG assets.
/// Stroke 1: oppefra og ned (left vertical)
/// Stroke 2: oppefra og ned (right vertical)
/// Stroke 3: fra højre mod venstre (middle bar)
Future<Letter> loadLetterH() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/H_Stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/H_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/H_stroke3.svg'),
  ];
  return Letter(
    id: 'h',
    character: 'H',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Haaghai2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Haaghai1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Haaghaitale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Haaghaitale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Haaghai.wav',
  );
}
