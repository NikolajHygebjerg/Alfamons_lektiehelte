import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter T with 2 strokes from SVG assets.
/// Stroke 1: oppefra og ned (vertical)
/// Stroke 2: fra venstre mod højre (horizontal bar)
Future<Letter> loadLetterT() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/T_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/T_stroke2.svg'),
  ];
  return Letter(
    id: 't',
    character: 'T',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Tegorm2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Tegorm1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Tegormtale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Tegormtale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Tegorm.wav',
  );
}
