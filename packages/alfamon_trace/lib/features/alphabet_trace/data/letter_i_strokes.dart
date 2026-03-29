import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter I with one stroke from SVG asset.
/// Stroke: oppefra og ned (vertical).
Future<Letter> loadLetterI() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/I_stroke.svg'),
  ];
  return Letter(
    id: 'i',
    character: 'I',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Iffle2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Iffle1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Iffletale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Iffletale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Iffle.wav',
  );
}
