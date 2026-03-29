import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter F with 3 strokes from SVG assets.
/// Stroke 1: oppefra og ned (vertical)
/// Stroke 2: højre til venstre (top bar)
/// Stroke 3: højre til venstre (middle bar)
Future<Letter> loadLetterF() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/F_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/F_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/F_stroke3.svg'),
  ];
  return Letter(
    id: 'f',
    character: 'F',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Flizard2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Flizard1.jpg',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Flizard.wav',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Flizardtale.mp3',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Flizardtale2.mp3',
  );
}
