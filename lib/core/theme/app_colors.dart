import 'package:flutter/material.dart';

/// Semantic and brand colors for Sello — matched to the owner dashboard HTML.
abstract final class AppColors {
  // Brand
  static const Color brandViolet = Color(0xFF6C4FF2);
  static const Color brandIndigo = Color(0xFF4B32C3);
  static const Color brandDeep = Color(0xFF2C1D7A);
  static const Color lavender = Color(0xFFB9A6FF);
  static const Color primaryMid = Color(0xFFD9CFFB);

  static const Color primary = Color(0xFF6C4FF2);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFEFE9FE);
  static const Color onPrimaryContainer = Color(0xFF2C1D7A);

  // Surfaces
  static const Color background = Color(0xFFECEDFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFFBFAFE);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  /// Quiet muted fill (chips, subtle panels) — not for interactive list hover.
  static const Color surfaceHover = Color(0xFFFBFAFE);
  /// List-row / table hover veil — dashboard SoT (stronger than surfaceHover).
  static const Color veil = Color(0xFFF3F0FA);
  static const Color surfaceSelected = Color(0xFFF1EDFE);

  static const Color outline = Color(0xFFEBE6F8);
  /// Thin panel border for list/page surfaces (#ECE8FF).
  static const Color outlinePanel = Color(0xFFECE8FF);
  static const Color outlineStrong = Color(0xFFDED6F1);
  static const Color outlineSubtle = Color(0xFFF2EEFB);

  // Ink
  static const Color textPrimary = Color(0xFF191333);
  static const Color textSecondary = Color(0xFF3B3459);
  static const Color textTertiary = Color(0xFF736C90);
  static const Color textFaint = Color(0xFFA9A2C2);
  static const Color textDisabled = Color(0xFFA9A2C2);

  // Semantic solids + soft containers
  static const Color ai = Color(0xFF6C4FF2);
  static const Color aiSoft = Color(0xFFF1EDFE);

  static const Color ops = Color(0xFF4176E8);
  static const Color opsSoft = Color(0xFFEBF1FE);

  static const Color success = Color(0xFF149063);
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFE2F5EC);

  static const Color finance = Color(0xFFC9862A);
  static const Color financeSoft = Color(0xFFFAF1DF);

  static const Color warning = Color(0xFFC9862A);
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color warningContainer = Color(0xFFFAF1DF);

  static const Color attention = Color(0xFFDC4249);
  static const Color attentionSoft = Color(0xFFFCE9EA);

  /// Required-field asterisk — pinkish soft red, quieter than error copy.
  static const Color requiredMark = Color(0xFFE07078);

  static const Color error = Color(0xFFDC4249);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFCE9EA);

  static const Color inventory = Color(0xFF0E9C8C);
  static const Color inventorySoft = Color(0xFFE0F4F1);

  static const Color info = Color(0xFF4176E8);
  static const Color onInfo = Color(0xFFFFFFFF);
  static const Color infoContainer = Color(0xFFEBF1FE);

  // Navigation rail (Hub dark surface)
  static const Color navTop = Color(0xFF33157F);
  static const Color navMid = Color(0xFF280E68);
  static const Color navBottom = Color(0xFF1C0950);
  static const Color navInk = Color(0xB8FFFFFF);
  static const Color navInkStrong = Color(0xFFFFFFFF);
  static const Color navInkFaint = Color(0x66FFFFFF);
  static const Color navHover = Color(0x12FFFFFF);
  static const Color navActive = Color(0x1FFFFFFF);
  static const Color navAccent = Color(0xFFB9A6FF);

  // Scrim / overlays
  static const Color scrim = Color(0x99000000);
  static const Color focusRing = Color(0x246C4FF2);
}
