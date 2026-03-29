import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter M with one stroke from SVG asset.
/// Stroke: nederste venstre hjørne til enden.
Future<Letter> loadLetterM() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/M_stroke.svg'),
  ];
  return Letter(
    id: 'm',
    character: 'M',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Maxtor2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Maxtor1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/maxtortale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/maxtortale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Maxtor.wav',
  );
}
