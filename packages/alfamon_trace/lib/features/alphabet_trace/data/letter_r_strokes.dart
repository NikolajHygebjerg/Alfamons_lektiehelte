import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter R with 2 strokes from SVG assets.
/// Stroke 1: oppefra og ned (vertical)
/// Stroke 2: oppefra og ned til midten, ud fra midten og ned til bunden i en streg
Future<Letter> loadLetterR() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/R_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/R_stroke2.svg'),
  ];
  return Letter(
    id: 'r',
    character: 'R',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Rminax2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Rminax1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Rminaxtale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Rminaxtale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Rminax.wav',
  );
}
