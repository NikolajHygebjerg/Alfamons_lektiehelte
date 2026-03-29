import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter V with 1 stroke from SVG assets.
/// Stroke: oppe fra venstre hjørne, ned og op igen (V-form)
Future<Letter> loadLetterV() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/V_stroke.svg'),
  ];
  return Letter(
    id: 'v',
    character: 'V',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Vindleek2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Vindleek1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Vindleektale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Vindleektale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Vindleek.aiff',
  );
}
