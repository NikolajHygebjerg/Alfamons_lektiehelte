import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter O with one stroke from SVG asset.
/// Stroke: starter øverst midt og tegnes mod venstre, ender i samme punkt.
Future<Letter> loadLetterO() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/O_Stroke.svg'),
  ];
  return Letter(
    id: 'o',
    character: 'O',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Oodlob2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Oodlob1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Oodlobtale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Oodlobtale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Oodlob.mov',
  );
}
