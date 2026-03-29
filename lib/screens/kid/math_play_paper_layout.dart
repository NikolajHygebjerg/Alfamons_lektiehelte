import 'dart:ui' show Rect, Size;

import 'kid_today_hit_regions.dart';

/// [baggrund_matematik2.png] er 1200×895 – samme som [KidTodayDesign].
/// Papir-zonen (1200×895 design): lidt luft foroven og skubbet til højre.
abstract final class MathPlayPaperDesign {
  static final Rect rect = Rect.fromLTWH(340, 56, 560, 520);
}

/// Mapper papir-rektangel fra design-pixel til skærm ved [BoxFit.cover] som baggrundsbilledet.
Rect mathPlayPaperRectOnScreen(Size screenSize) =>
    kidTodayMapDesignRectToScreen(MathPlayPaperDesign.rect, screenSize);
