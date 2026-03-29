import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter Æ with 4 strokes from SVG assets.
/// Stroke 1: nede fra venstre hjørne og op og ned igen
/// Stroke 2: fra venstre mod højre
/// Stroke 3: fra venstre mod højre
/// Stroke 4: fra venstre mod højre
Future<Letter> loadLetterAe() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/AE_Stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/AE_Stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/AE_Stroke3.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/AE_Stroke4.svg'),
  ];
  return Letter(
    id: 'ae',
    character: 'Æ',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Aelgor2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Aelgor1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Aelgortale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Aelgortale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Aelgor.wav',
  );
}
