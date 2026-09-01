import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';
import 'package:sello/core/theme/app_gradients.dart';
import 'package:sello/core/theme/app_radius.dart';
import 'package:sello/core/theme/app_shadows.dart';
import 'package:sello/core/theme/app_spacing.dart';

/// Semantic colors and brand tokens attached to [ThemeData].
@immutable
class SelloColors extends ThemeExtension<SelloColors> {
  const SelloColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.textSecondary,
    required this.textTertiary,
    required this.textFaint,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.veil,
    required this.surfaceSelected,
    required this.outlineSubtle,
    required this.brandViolet,
    required this.brandIndigo,
    required this.primaryGradient,
    required this.navRail,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color textSecondary;
  final Color textTertiary;
  final Color textFaint;
  final Color surfaceMuted;
  final Color surfaceHover;
  final Color veil;
  final Color surfaceSelected;
  final Color outlineSubtle;
  final Color brandViolet;
  final Color brandIndigo;
  final LinearGradient primaryGradient;
  final LinearGradient navRail;

  static const SelloColors light = SelloColors(
    success: AppColors.success,
    onSuccess: AppColors.onSuccess,
    successContainer: AppColors.successContainer,
    warning: AppColors.warning,
    onWarning: AppColors.onWarning,
    warningContainer: AppColors.warningContainer,
    info: AppColors.info,
    onInfo: AppColors.onInfo,
    infoContainer: AppColors.infoContainer,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    textFaint: AppColors.textFaint,
    surfaceMuted: AppColors.surfaceMuted,
    surfaceHover: AppColors.surfaceHover,
    veil: AppColors.veil,
    surfaceSelected: AppColors.surfaceSelected,
    outlineSubtle: AppColors.outlineSubtle,
    brandViolet: AppColors.brandViolet,
    brandIndigo: AppColors.brandIndigo,
    primaryGradient: AppGradients.primary,
    navRail: AppGradients.navRail,
  );

  /// Architectural placeholder — dark palette not implemented yet.
  static const SelloColors dark = light;

  @override
  SelloColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? textSecondary,
    Color? textTertiary,
    Color? textFaint,
    Color? surfaceMuted,
    Color? surfaceHover,
    Color? veil,
    Color? surfaceSelected,
    Color? outlineSubtle,
    Color? brandViolet,
    Color? brandIndigo,
    LinearGradient? primaryGradient,
    LinearGradient? navRail,
  }) {
    return SelloColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textFaint: textFaint ?? this.textFaint,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      veil: veil ?? this.veil,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      outlineSubtle: outlineSubtle ?? this.outlineSubtle,
      brandViolet: brandViolet ?? this.brandViolet,
      brandIndigo: brandIndigo ?? this.brandIndigo,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      navRail: navRail ?? this.navRail,
    );
  }

  @override
  SelloColors lerp(ThemeExtension<SelloColors>? other, double t) {
    if (other is! SelloColors) return this;
    return SelloColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      veil: Color.lerp(veil, other.veil, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      outlineSubtle: Color.lerp(outlineSubtle, other.outlineSubtle, t)!,
      brandViolet: Color.lerp(brandViolet, other.brandViolet, t)!,
      brandIndigo: Color.lerp(brandIndigo, other.brandIndigo, t)!,
      primaryGradient:
          LinearGradient.lerp(primaryGradient, other.primaryGradient, t)!,
      navRail: LinearGradient.lerp(navRail, other.navRail, t)!,
    );
  }
}

/// Spacing / radius tokens on the theme.
@immutable
class SelloMetrics extends ThemeExtension<SelloMetrics> {
  const SelloMetrics({
    required this.spacing,
    required this.radiusButton,
    required this.radiusCard,
    required this.radiusDialog,
    required this.radiusInput,
    required this.radiusBottomSheet,
  });

  final double spacing;
  final double radiusButton;
  final double radiusCard;
  final double radiusDialog;
  final double radiusInput;
  final double radiusBottomSheet;

  static const SelloMetrics standard = SelloMetrics(
    spacing: AppSpacing.md,
    radiusButton: AppRadius.button,
    radiusCard: AppRadius.card,
    radiusDialog: AppRadius.dialog,
    radiusInput: AppRadius.input,
    radiusBottomSheet: AppRadius.bottomSheet,
  );

  @override
  SelloMetrics copyWith({
    double? spacing,
    double? radiusButton,
    double? radiusCard,
    double? radiusDialog,
    double? radiusInput,
    double? radiusBottomSheet,
  }) {
    return SelloMetrics(
      spacing: spacing ?? this.spacing,
      radiusButton: radiusButton ?? this.radiusButton,
      radiusCard: radiusCard ?? this.radiusCard,
      radiusDialog: radiusDialog ?? this.radiusDialog,
      radiusInput: radiusInput ?? this.radiusInput,
      radiusBottomSheet: radiusBottomSheet ?? this.radiusBottomSheet,
    );
  }

  @override
  SelloMetrics lerp(ThemeExtension<SelloMetrics>? other, double t) {
    if (other is! SelloMetrics) return this;
    return SelloMetrics(
      spacing: _lerp(spacing, other.spacing, t),
      radiusButton: _lerp(radiusButton, other.radiusButton, t),
      radiusCard: _lerp(radiusCard, other.radiusCard, t),
      radiusDialog: _lerp(radiusDialog, other.radiusDialog, t),
      radiusInput: _lerp(radiusInput, other.radiusInput, t),
      radiusBottomSheet: _lerp(radiusBottomSheet, other.radiusBottomSheet, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

extension SelloThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get texts => theme.textTheme;
  SelloColors get selloColors => theme.extension<SelloColors>()!;
  SelloMetrics get selloMetrics => theme.extension<SelloMetrics>()!;
  List<BoxShadow> get elevation1 => AppShadows.level1;
  List<BoxShadow> get elevation2 => AppShadows.level2;

  /// Primary interactive accent — Sello purple, or the client brand colour.
  Color get brandAccent => colors.primary;
  Color get onBrandAccent => colors.onPrimary;
  Color get brandAccentContainer => colors.primaryContainer;
  Color get onBrandAccentContainer => colors.onPrimaryContainer;

  /// Soft mid tint of [brandAccent] (selected chip borders, quiet fills).
  Color get brandMid => selloColors.brandViolet == AppColors.brandViolet
      ? AppColors.primaryMid
      : Color.lerp(colors.primary, Colors.white, 0.62)!;
}
