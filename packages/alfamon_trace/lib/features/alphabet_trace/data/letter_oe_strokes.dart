import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter Ø with 2 strokes from SVG assets.
/// Stroke 1: oppe fra midten og hele vejen rundt (circle)
/// Stroke 2: oppe fra højre hjørne og ned til venstre (diagonal)
Future<Letter> loadLetterOe() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/OE_Stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/OE_Stroke2.svg'),
  ];
  return Letter(
    id: 'oe',
    character: 'Ø',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Oegleon2.png',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Oegleon1.png',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Oegleontale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Oegleontale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Oegleon.mp3',
  );
}
