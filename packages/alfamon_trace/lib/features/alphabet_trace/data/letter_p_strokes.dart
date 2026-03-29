import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter P with 2 strokes from SVG assets.
/// Stroke 1: oppefra og ned (vertical)
/// Stroke 2: oppefra og ned (curve)
Future<Letter> loadLetterP() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/P_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/P_Stroke2.svg'),
  ];
  return Letter(
    id: 'p',
    character: 'P',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Peppapop2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Peppapop1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Peppapoptale1.m4a',
    alfamonTale2Path: null,
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Peppapop.wav',
  );
}
