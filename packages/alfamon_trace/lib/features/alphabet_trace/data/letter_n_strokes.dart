import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter N with one stroke from SVG asset.
/// Stroke: nedefra venstre hjørne og til enden.
Future<Letter> loadLetterN() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/N_stroke.svg'),
  ];
  return Letter(
    id: 'n',
    character: 'N',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Nimbroo2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Nimbroo1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Nimbrootale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Nimbrootale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Nimbroo.wav',
  );
}
