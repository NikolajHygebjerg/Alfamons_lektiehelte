import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Hylder som brøk af skærmhøjde (0–1 fra top). Bøger placeres i båndet
/// [top]–[bottom] med bund mod [bottom] (hyldelinjen).
class LibraryCabinetShelfLayout {
  LibraryCabinetShelfLayout._();

  static const int shelfCount = 4;

  /// Fire hylder – højere bånd så større bogforsider kan stå på planken.
  static const List<({double top, double bottom})> shelfBands = [
    (top: 0.10, bottom: 0.29),
    (top: 0.315, bottom: 0.505),
    (top: 0.53, bottom: 0.72),
    (top: 0.745, bottom: 0.91),
  ];

  static void assertBands() {
    assert(shelfBands.length == shelfCount);
  }
}

/// Varmt, “charmerende” bogskab tegnet i kode (træ, skygger, mange hylder).
class LibraryCabinetBackground extends StatelessWidget {
  const LibraryCabinetBackground({
    super.key,
    this.showWallBackdrop = true,
  });

  /// Når [false], tegnes kun skabet (fx når [SvgPicture] allerede er bagved).
  final bool showWallBackdrop;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LibraryCabinetPainter(
        bands: LibraryCabinetShelfLayout.shelfBands,
        showWallBackdrop: showWallBackdrop,
      ),
      size: Size.infinite,
    );
  }
}

class _LibraryCabinetPainter extends CustomPainter {
  _LibraryCabinetPainter({
    required this.bands,
    required this.showWallBackdrop,
  });

  final List<({double top, double bottom})> bands;
  final bool showWallBackdrop;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final w = size.width;
    final h = size.height;

    if (showWallBackdrop) {
      final wall = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(w, h),
          const [
            Color(0xFFFFF3E0),
            Color(0xFFFFE0B2),
            Color(0xFFD7CCC8),
          ],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), wall);

      final dot = Paint()..color = const Color(0x1A5D4037);
      const step = 28.0;
      for (var x = 0.0; x < w; x += step) {
        for (var y = 0.0; y < h; y += step) {
          canvas.drawCircle(Offset(x + 8, y + 8), 1.1, dot);
        }
      }
    }

    final frameInset = (w * 0.055).clamp(12.0, 48.0);
    final inner = Rect.fromLTRB(frameInset, h * 0.06, w - frameInset, h * 0.965);

    // Ydre ramme / skabskrop
    final outerFrame = RRect.fromRectAndRadius(
      Rect.fromLTRB(inner.left - 6, inner.top - 8, inner.right + 6, inner.bottom + 10),
      const Radius.circular(6),
    );
    final framePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(inner.left, 0),
        Offset(inner.right, 0),
        const [Color(0xFF4E342E), Color(0xFF3E2723), Color(0xFF4E342E)],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRRect(outerFrame, framePaint);

    // Krone / gesims
    final crown = Path()
      ..moveTo(inner.left - 4, inner.top - 8)
      ..lineTo(inner.left + w * 0.08, inner.top - 22)
      ..lineTo(inner.right - w * 0.08, inner.top - 22)
      ..lineTo(inner.right + 4, inner.top - 8)
      ..close();
    canvas.drawPath(
      crown,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, inner.top - 24),
          Offset(0, inner.top - 6),
          const [Color(0xFF6D4C41), Color(0xFF4E342E)],
        ),
    );

    // Indvendig bagvæg i skabet
    final cavity = RRect.fromRectAndRadius(
      Rect.fromLTRB(inner.left + 8, inner.top + 6, inner.right - 8, inner.bottom - 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      cavity,
      Paint()..color = const Color(0xFFFBE9E7).withValues(alpha: 0.92),
    );

    // Vertikale stolper (opdeler hylder)
    final postW = (w * 0.034).clamp(6.0, 14.0);
    final postPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, inner.top),
        Offset(0, inner.bottom),
        const [Color(0xFF5D4037), Color(0xFF3E2723), Color(0xFF6D4C41)],
        const [0.0, 0.55, 1.0],
      );
    final posts = [
      inner.left + frameInset * 0.35,
      inner.right - frameInset * 0.35 - postW,
    ];
    for (final px in posts) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(px, inner.top + 10, px + postW, inner.bottom - 20),
          const Radius.circular(2),
        ),
        postPaint,
      );
    }

    // Hylder (planke + skygge under)
    for (final band in bands) {
      final yBottom = h * band.bottom;
      final plankH = (h * 0.022).clamp(7.0, 14.0);
      final left = inner.left + 12;
      final right = inner.right - 12;
      final plank = RRect.fromRectAndCorners(
        Rect.fromLTRB(left, yBottom - plankH, right, yBottom),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );

      canvas.drawRRect(
        plank,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, yBottom - plankH),
            Offset(0, yBottom),
            const [Color(0xFFA1887F), Color(0xFF6D4C41), Color(0xFF4E342E)],
            const [0.0, 0.45, 1.0],
          ),
      );

      // Lys kant foran
      canvas.drawLine(
        Offset(left + 2, yBottom - plankH + 2),
        Offset(right - 2, yBottom - plankH + 2),
        Paint()
          ..color = const Color(0xFFD7CCC8).withValues(alpha: 0.85)
          ..strokeWidth = 1.2,
      );

      // Skygge under hylde
      final shadowY = yBottom + 2;
      canvas.drawRect(
        Rect.fromLTRB(left + 4, shadowY, right - 4, shadowY + (h * 0.012).clamp(4.0, 10.0)),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, shadowY),
            Offset(0, shadowY + 8),
            [Colors.black.withValues(alpha: 0.22), Colors.transparent],
          ),
      );
    }

    // Sokkel
    final baseY = inner.bottom - 6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(inner.left - 2, baseY, inner.right + 2, h),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF3E2723),
    );
  }

  @override
  bool shouldRepaint(covariant _LibraryCabinetPainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.showWallBackdrop != showWallBackdrop;
}
