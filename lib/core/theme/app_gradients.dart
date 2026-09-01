import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';

/// Brand gradients — Hub nav rail + CTA accents.
abstract final class AppGradients {
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.brandIndigo],
  );

  static const LinearGradient primaryHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.brandIndigo],
  );

  static const LinearGradient primarySoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x146C4FF2), Color(0x104B32C3)],
  );

  /// Sello Intelligence promo / insight cards.
  static const LinearGradient intelligence = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B83D5), Color(0xFFAA98DF)],
  );

  static const LinearGradient heroWash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x1A6C4FF2), Color(0x00FFFFFF)],
  );

  /// Sales Home — full-viewport wash. Soft purple at the top, canvas from 40%.
  static const LinearGradient selloHome = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.20, 0.40, 1.0],
    colors: [
      Color(0xFFE4C8F9),
      Color(0xFFDAD7FE),
      AppColors.background,
      AppColors.background,
    ],
  );

  /// Hub sidebar — the one dark surface + radial highlight (HTML).
  static const LinearGradient navRail = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.navTop, AppColors.navMid, AppColors.navBottom],
    stops: [0.0, 0.55, 1.0],
  );

  static RadialGradient get navRailGlow => const RadialGradient(
        center: Alignment(-0.7, -1.05),
        radius: 1.1,
        colors: [
          Color(0x579E7EFF),
          Color(0x00000000),
        ],
        stops: [0.0, 0.64],
      );

  /// Flat page canvas (HTML `#ECEDFB`).
  static const LinearGradient canvas = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.background,
      AppColors.background,
    ],
  );

  static RadialGradient get canvasGlow => RadialGradient(
        center: const Alignment(-0.75, -1.1),
        radius: 1.35,
        colors: [
          AppColors.primary.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      );

  static RadialGradient get canvasAccent => RadialGradient(
        center: const Alignment(1.15, 1.2),
        radius: 1.25,
        colors: [
          AppColors.ops.withValues(alpha: 0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      );

  static const LinearGradient gauge = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [AppColors.inventory, AppColors.primary, AppColors.lavender],
  );
}
