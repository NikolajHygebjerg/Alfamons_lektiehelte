import '../models/letter.dart';
import 'svg_path_loader.dart';

/// Loads letter L with one stroke from SVG asset.
/// Stroke: oppefra og ned.
Future<Letter> loadLetterL() async {
  final strokes = [
    await loadPathFromSvg('packages/alfamon_trace/Assets/L_Stroke.svg'),
  ];
  return Letter(
    id: 'l',
    character: 'L',
    strokes: const [],
    pathStrokes: strokes,
    alfamonAssetPath: 'packages/alfamon_trace/Assets/Lmi2.jpg',
    alfamonBackgroundPath: 'packages/alfamon_trace/Assets/Lmi1.jpg',
    alfamonTalePath: 'packages/alfamon_trace/Assets/lmitale1.m4a',
    alfamonTale2Path: 'packages/alfamon_trace/Assets/Lmitale2.m4a',
    alfamonSuccessSoundPath: 'packages/alfamon_trace/Assets/lmi.m4a',
  );
}
