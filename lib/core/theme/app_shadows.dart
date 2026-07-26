import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';

/// Soft elevation — premium, never harsh.
abstract final class AppShadows {
  static List<BoxShadow> get none => const [];

  /// Hairline lift for quiet cards.
  static List<BoxShadow> get level1 => [
        BoxShadow(
          color: const Color(0xFF12141A).withValues(alpha: 0.035),
          blurRadius: 10,
          offset: const Offset(0, 2),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: AppColors.brandIndigo.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// Default elevated surface (dashboard cards, panels).
  static List<BoxShadow> get level2 => [
        BoxShadow(
          color: const Color(0xFF12141A).withValues(alpha: 0.05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: const Color(0xFF12141A).withValues(alpha: 0.025),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// Modals / floating chrome.
  static List<BoxShadow> get level3 => [
        BoxShadow(
          color: const Color(0xFF12141A).withValues(alpha: 0.07),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: const Color(0xFF12141A).withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get focus => [
        BoxShadow(
          color: AppColors.focusRing,
          blurRadius: 0,
          spreadRadius: 3,
        ),
      ];
}
