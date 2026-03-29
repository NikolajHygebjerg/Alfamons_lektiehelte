import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter W with 1 stroke from SVG assets.
/// Stroke: starter i venstre hjørne og kører til lenden (W-form)
Future<Letter> loadLetterW() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/W_stroke.svg'),
  ];
  return Letter(
    id: 'w',
    character: 'W',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Wigloo2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Wigloo1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Wiglootale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Wiglootale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Wigloo.wav',
  );
}
