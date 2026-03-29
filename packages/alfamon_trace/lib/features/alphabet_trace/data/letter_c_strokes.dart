import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter C with one stroke from SVG asset.
/// Stroke: øverste højre hjørne -> nederste højre hjørne.
Future<Letter> loadLetterC() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/C_stroke.svg'),
  ];
  return Letter(
    id: 'c',
    character: 'C',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Cekimos2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Cekimos1.jpg',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Cekimos.wav',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Cekimostale.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Cekimostale2.m4a',
  );
}
