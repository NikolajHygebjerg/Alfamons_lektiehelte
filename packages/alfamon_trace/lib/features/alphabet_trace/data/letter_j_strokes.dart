import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter J with one stroke from SVG asset.
/// Stroke: oppefra og til enden.
Future<Letter> loadLetterJ() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/J_stroke.svg'),
  ];
  return Letter(
    id: 'j',
    character: 'J',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Jaadrik2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Jaadrik1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Jaadriktale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Jaadriktale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Jaadrik.wav',
  );
}
