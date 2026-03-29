import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter U with 1 stroke from SVG assets.
/// Stroke: starter i venstre hjørne og kører hele vejen rundt (U-form)
Future<Letter> loadLetterU() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/U_stroke.svg'),
  ];
  return Letter(
    id: 'u',
    character: 'U',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Ummiroo2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Ummiroo1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Ummirootale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Ummirootale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Ummiroo.wav',
  );
}
