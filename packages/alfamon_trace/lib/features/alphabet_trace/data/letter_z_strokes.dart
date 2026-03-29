import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter Z with 1 stroke from SVG assets.
/// Stroke: starter i øverste venstre hjørne og hele vejen til enden (Z-form)
Future<Letter> loadLetterZ() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/Z_stroke.svg'),
  ];
  return Letter(
    id: 'z',
    character: 'Z',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Zetbra2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Zetbra1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Zetbratale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Zetbratale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Zetbra.wav',
  );
}
