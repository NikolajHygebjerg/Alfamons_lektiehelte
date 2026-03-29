import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter G with 2 strokes from SVG assets.
/// Stroke 1: starter øverst til højre og kører hele vejen rundt til enden (curve)
/// Stroke 2: starter øverst til venstre og tegnes til enden (bar + tail)
Future<Letter> loadLetterG() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/G_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/G_stroke2.svg'),
  ];
  return Letter(
    id: 'g',
    character: 'G',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Gemibull2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Gemibull1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Gemibulltale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Gemibulltale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Gemibull.wav',
  );
}
