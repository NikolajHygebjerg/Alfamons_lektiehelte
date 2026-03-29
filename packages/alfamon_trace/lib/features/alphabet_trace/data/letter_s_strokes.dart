import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter S with 1 stroke from SVG assets.
/// Stroke: oppefra og ned (S-form)
Future<Letter> loadLetterS() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/S_stroke.svg'),
  ];
  return Letter(
    id: 's',
    character: 'S',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Snake2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Snake1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Snaketale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Snaketale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Snake.wav',
  );
}
