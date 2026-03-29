import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter B with strokes from SVG assets.
/// Stroke 1: lodret streg (nederste venstre -> øverste venstre)
/// Stroke 2: bue 1 (øverste venstre -> midt venstre)
/// Stroke 3: bue 2 (midt venstre -> nederste venstre)
Future<Letter> loadLetterB() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/B_stroke1.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/B_stroke2.svg'),
    await loadPathFromSvg('packages/alfamon_trace/Assets/B_stroke3.svg'),
  ];
  return Letter(
    id: 'b',
    character: 'B',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Bezzle2.png',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Bezzle1.png',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/Bezzle.aiff',
    alfamonTalePath: 'packages/alfamon_trace/Assets/Bezzletale.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Bezzletale2.m4a',
  );
}
