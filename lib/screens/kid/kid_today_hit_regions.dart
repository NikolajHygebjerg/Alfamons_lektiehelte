import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

/// Samme viewBox som [assets/baggrund.svg]: "0 0 1200 895".
/// Brug et redigeringsværktøy på en PNG eksporteret i 1200×895 (eller mål direkte
/// i Serif/Figma på artboardet) og opdater rektanglerne her — de mappes korrekt ved
/// [SvgPicture.fit] = [BoxFit.cover].
abstract final class KidTodayDesign {
  static const double width = 1200;
  static const double height = 895;
}

/// Mapper et rektangel fra design-rum (1200×895) til skærmkoordinater når baggrunden
/// vises med [BoxFit.cover] og center alignment (standard for [SvgPicture]).
Rect kidTodayMapDesignRectToScreen(Rect designRect, Size screenSize) {
  final sw = screenSize.width;
  final sh = screenSize.height;
  const dw = KidTodayDesign.width;
  const dh = KidTodayDesign.height;
  final scale = math.max(sw / dw, sh / dh);
  final ox = (sw - dw * scale) / 2;
  final oy = (sh - dh * scale) / 2;
  return Rect.fromLTWH(
    designRect.left * scale + ox,
    designRect.top * scale + oy,
    designRect.width * scale,
    designRect.height * scale,
  );
}

/// Trykfelter i **design-pixels** (0…1200, 0…895).
/// Bamse / ugle / fugl: tilpasset de hvide felter på reference-PNG (viewBox 1200×895).
abstract final class KidTodayHitRegions {
  /// Bamse → Alfamon Trace (~160×330)
  static final Rect trace = Rect.fromLTWH(60, 250, 160, 330);

  /// Ugle → bibliotek (~180×260). Overlapper vandret med [math]; [math] ligger øverst i stack.
  static final Rect library = Rect.fromLTWH(265, 280, 180, 260);

  /// Fugl → matematik (~225×290)
  static final Rect math = Rect.fromLTWH(375, 500, 225, 290);

  /// Højre side → spil / kort
  static final Rect spil = Rect.fromLTWH(760, 60, 420, 780);
}
