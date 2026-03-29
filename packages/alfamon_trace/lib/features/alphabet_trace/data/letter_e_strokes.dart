import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter E with 4 strokes from SVG assets.
/// Stroke 1: oppefra og ned (vertical)
/// Stroke 2: højre til venstre (top bar)
/// Stroke 3: højre til venstre (middle bar)
/// Stroke 4: højre til venstre (bottom bar)
Future<Letter> loadLetterE() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/E_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/E_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/E_stroke3.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/E_stroke4.svg'),
  ];
  return Letter(
    id: 'e',
    character: 'E',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Ellaboo2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Ellaboo1.jpg',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Ellaboo.wav',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Ellabootale.mp3',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Ellabootale2.mp3',
    scaleFactor: 1.15,
  );
}
