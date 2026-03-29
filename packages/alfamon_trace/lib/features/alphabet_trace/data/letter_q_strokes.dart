import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter Q with 2 strokes from SVG assets.
/// Stroke 1: starter i toppen og kører hele vejen rundt (circle)
/// Stroke 2: oppefra og ned (tail)
Future<Letter> loadLetterQ() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/Q_Stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/Q_stroke2.svg'),
  ];
  return Letter(
    id: 'q',
    character: 'Q',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Quibly2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Quibly1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Quiblytale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Quiblytale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Quibly.flac',
  );
}
