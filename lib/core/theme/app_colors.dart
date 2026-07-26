import 'package:flutter/material.dart';

/// Semantic and brand colors for Sello.
/// Prefer [Theme.of] / [SelloColors] over using these directly in widgets.
abstract final class AppColors {
  // Brand gradient stops
  static const Color brandViolet = Color(0xFF9619F1);
  static const Color brandIndigo = Color(0xFF4237E7);

  // Primary (midpoint of brand for solid fills)
  static const Color primary = Color(0xFF6C28EC);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFF0E7FF);
  static const Color onPrimaryContainer = Color(0xFF2A0A5E);

  // Neutrals — predominantly light UI
  static const Color background = Color(0xFFF7F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F3F9);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFE8EBF3);
  static const Color outlineStrong = Color(0xFFD5DAE6);

  static const Color textPrimary = Color(0xFF12141A);
  static const Color textSecondary = Color(0xFF5C6478);
  static const Color textTertiary = Color(0xFF8B93A7);
  static const Color textDisabled = Color(0xFFB0B7C8);

  // Semantic
  static const Color success = Color(0xFF0F9F6E);
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFE6F7F0);

  static const Color warning = Color(0xFFD97706);
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color warningContainer = Color(0xFFFFF4E5);

  static const Color error = Color(0xFFDC2626);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFEECEC);

  static const Color info = Color(0xFF2563EB);
  static const Color onInfo = Color(0xFFFFFFFF);
  static const Color infoContainer = Color(0xFFE8F0FE);

  // Scrim / overlays
  static const Color scrim = Color(0x99000000);
  static const Color focusRing = Color(0x336C28EC);
}
