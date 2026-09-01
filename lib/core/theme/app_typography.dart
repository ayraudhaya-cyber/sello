import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';

/// Google Sans Flex — matched to the owner dashboard HTML.
abstract final class AppTypography {
  static const String fontFamily = 'Google Sans Flex';

  static TextTheme? _textTheme;

  static TextTheme get textTheme => _textTheme ??= _buildTextTheme();

  static TextTheme _buildTextTheme() {
    TextStyle base(double size, FontWeight weight, double tracking,
        {double height = 1.45}) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking,
        height: height,
        color: AppColors.textPrimary,
      );
    }

    return TextTheme(
      displayLarge: base(40, FontWeight.w700, -0.03 * 40, height: 1.15),
      displayMedium: base(32, FontWeight.w600, -0.03 * 32, height: 1.2),
      displaySmall: base(28, FontWeight.w600, -0.03 * 28, height: 1.2),
      headlineLarge: base(24, FontWeight.w600, -0.02 * 24, height: 1.3),
      headlineMedium: base(20, FontWeight.w600, -0.02 * 20, height: 1.3),
      headlineSmall: base(18, FontWeight.w600, -0.02 * 18, height: 1.35),
      titleLarge: base(18, FontWeight.w600, -0.02 * 18, height: 1.35),
      titleMedium: base(16, FontWeight.w600, -0.01 * 16, height: 1.4),
      titleSmall: base(14, FontWeight.w600, -0.01 * 14, height: 1.35),
      bodyLarge: base(16, FontWeight.w400, 0, height: 1.5),
      bodyMedium: base(14, FontWeight.w400, 0, height: 1.5),
      bodySmall: base(12.5, FontWeight.w400, 0, height: 1.45),
      labelLarge: base(14, FontWeight.w600, 0, height: 1.3),
      labelMedium: base(12.5, FontWeight.w600, 0, height: 1.3),
      labelSmall: base(10.5, FontWeight.w600, 0.05 * 10.5, height: 1.25),
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
        letterSpacing: 0,
      );

  /// KPI / meta uppercase labels — 10.5 / w600 / 0.05em.
  static TextStyle get eyebrow => textTheme.labelSmall!.copyWith(
        color: AppColors.textFaint,
        letterSpacing: 0.05 * 10.5,
        fontWeight: FontWeight.w600,
      );

  /// Chart / hero card label — 10.5 / w700 / 0.14em (Business Performance).
  static TextStyle get heroEyebrow => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.14 * 10.5,
        height: 1.25,
        color: AppColors.textFaint,
      );

  /// Dashboard section card title — 18 / w600.
  static TextStyle get sectionTitle => textTheme.titleLarge!;

  /// Form dialog title — 22 / w600 (Add Product SoT).
  static TextStyle get dialogTitle => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.02 * 22,
        height: 1.15,
        color: AppColors.textPrimary,
      );

  static TextStyle get fieldLabel => textTheme.labelLarge!.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get helper => textTheme.bodySmall!.copyWith(
        color: AppColors.textTertiary,
      );

  /// KPI value — HTML 25px / w500 / −0.02em
  static TextStyle get metric => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 25,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.02 * 25,
        height: 1.15,
        color: AppColors.textPrimary,
        fontFeatures: [FontFeature.tabularFigures()],
      );

  static TextStyle numeric(TextStyle? base) {
    return (base ?? textTheme.bodyMedium!).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
