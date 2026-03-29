import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter D with 2 strokes from SVG assets.
/// Stroke 1: oppefra og ned (vertical)
/// Stroke 2: oppe fra venstre hjørne og hele vejen ned til venstre nederste hjørne (curve)
Future<Letter> loadLetterD() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/D_Stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/D_stroke2.svg'),
  ];
  return Letter(
    id: 'd',
    character: 'D',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Deedoo2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Deedoo1.jpg',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Deedoo.wav',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Dedootale.mp3',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Dedootale2.mp3',
    scaleFactor: 1.15,
  );
}
