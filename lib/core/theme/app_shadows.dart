import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';

/// Elevation — cards are flat by default; hover uses purple-tinted lift.
abstract final class AppShadows {
  static const Color _purple = Color(0xFF3A2496);

  static List<BoxShadow> get none => const [];

  static List<BoxShadow> get level1 => [
        BoxShadow(
          color: _purple.withValues(alpha: 0.045),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get level2 => [
        BoxShadow(
          color: _purple.withValues(alpha: 0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: _purple.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  /// Soft lavender card shadow — list pages / metric panels.
  static List<BoxShadow> get panel => [
        BoxShadow(
          color: const Color(0xFF6C4FF2).withValues(alpha: 0.045),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  /// HTML `--shadow-hover`: 0 30px 60px rgba(103,16,170,0.08)
  static List<BoxShadow> get hover => [
        BoxShadow(
          color: const Color(0xFF6710AA).withValues(alpha: 0.08),
          blurRadius: 60,
          offset: const Offset(0, 30),
        ),
      ];

  static List<BoxShadow> get level3 => [
        BoxShadow(
          color: _purple.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: _purple.withValues(alpha: 0.10),
          blurRadius: 70,
          offset: const Offset(0, 30),
        ),
      ];

  static List<BoxShadow> get glow => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.24),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get focus => [
        BoxShadow(
          color: AppColors.focusRing,
          blurRadius: 0,
          spreadRadius: 4,
        ),
      ];
}
