import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sello/core/theme/app_colors.dart';

/// Plus Jakarta Sans typography system (loaded via google_fonts).
abstract final class AppTypography {
  static String get fontFamily => GoogleFonts.plusJakartaSans().fontFamily!;

  static TextTheme get textTheme {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    return TextTheme(
      displayLarge: _display(base.displayLarge, 40, FontWeight.w600, -0.5),
      displayMedium: _display(base.displayMedium, 32, FontWeight.w600, -0.4),
      displaySmall: _display(base.displaySmall, 28, FontWeight.w600, -0.3),
      headlineLarge: _style(base.headlineLarge, 24, FontWeight.w600, -0.2),
      headlineMedium: _style(base.headlineMedium, 20, FontWeight.w600, -0.15),
      headlineSmall: _style(base.headlineSmall, 18, FontWeight.w600, -0.1),
      titleLarge: _style(base.titleLarge, 18, FontWeight.w600, -0.1),
      titleMedium: _style(base.titleMedium, 16, FontWeight.w600, -0.05),
      titleSmall: _style(base.titleSmall, 14, FontWeight.w600, 0),
      bodyLarge: _style(base.bodyLarge, 16, FontWeight.w400, 0.1),
      bodyMedium: _style(base.bodyMedium, 14, FontWeight.w400, 0.1),
      bodySmall: _style(base.bodySmall, 12, FontWeight.w400, 0.15),
      labelLarge: _style(base.labelLarge, 14, FontWeight.w600, 0.1),
      labelMedium: _style(base.labelMedium, 12, FontWeight.w600, 0.2),
      labelSmall: _style(base.labelSmall, 11, FontWeight.w500, 0.3),
    ).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
  }

  static TextStyle get display => textTheme.displayMedium!;
  static TextStyle get headline => textTheme.headlineMedium!;
  static TextStyle get title => textTheme.titleMedium!;
  static TextStyle get body => textTheme.bodyMedium!;
  static TextStyle get label => textTheme.labelMedium!;
  static TextStyle get caption => textTheme.bodySmall!.copyWith(
        color: AppColors.textSecondary,
      );
  static TextStyle get button => textTheme.labelLarge!.copyWith(
        letterSpacing: 0.2,
      );

  static TextStyle _display(
    TextStyle? base,
    double size,
    FontWeight weight,
    double spacing,
  ) {
    return (base ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: 1.2,
      letterSpacing: spacing,
      color: AppColors.textPrimary,
    );
  }

  static TextStyle _style(
    TextStyle? base,
    double size,
    FontWeight weight,
    double spacing,
  ) {
    return (base ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight,
      height: 1.45,
      letterSpacing: spacing,
      color: AppColors.textPrimary,
    );
  }
}
