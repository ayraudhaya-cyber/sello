import 'package:flutter/material.dart';

/// Motion tokens — snappy, professional, subtle.
///
/// Tuned for immediate click feedback and short transitions so the app
/// feels responsive without losing polish.
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 60);

  /// Pointer feedback (hover fills, borders, elevation) — must feel immediate.
  static const Duration hover = Duration(milliseconds: 90);

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);
}

abstract final class AppCurves {
  /// Default enter / settle — decelerate into the end state.
  static const Curve standard = Curves.easeOutCubic;

  /// Slightly stronger ease for larger moves (switches, sheet settles).
  static const Curve emphasized = Curves.easeOutCubic;
}
