import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter Å with 3 strokes from SVG assets.
/// Stroke 1: nede fra venstre hjørne op og ned igen
/// Stroke 2: fra venstre mod højre
/// Stroke 3: fra toppen midt og hele vejen rundt (circle)
Future<Letter> loadLetterAa() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/AA_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/AA_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/AA_stroke3.svg'),
  ];
  return Letter(
    id: 'aa',
    character: 'Å',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/AA2.png',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/AA1.png',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Aarmoktale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Aarmoktale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/AArmok.wav',
  );
}
