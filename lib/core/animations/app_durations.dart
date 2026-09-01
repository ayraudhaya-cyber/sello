import 'package:flutter/material.dart';

/// Motion tokens — fast, professional, subtle.
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 100);

  /// Pointer feedback (hover fills, borders, elevation) — must feel immediate.
  static const Duration hover = Duration(milliseconds: 140);

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 400);
}

abstract final class AppCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
}
