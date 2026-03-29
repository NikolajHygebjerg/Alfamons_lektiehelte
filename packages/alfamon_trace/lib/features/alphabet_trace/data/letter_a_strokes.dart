import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter A with strokes from SVG assets.
/// Stroke 1: triangle, Stroke 2: horizontal bar. (Original paths, no offset.)
Future<Letter> loadLetterA() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/A_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/A_strok2.svg'),
  ];
  return Letter(
    id: 'a',
    character: 'A',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Atiach2.png',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Atiach1.png',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Atiach.wav',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Atiachtale.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Atiachtale2.m4a',
  );
}
