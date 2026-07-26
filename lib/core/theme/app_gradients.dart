import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';

/// Brand gradients — use sparingly (CTAs, login accents, highlights, charts).
abstract final class AppGradients {
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.brandViolet, AppColors.brandIndigo],
  );

  static const LinearGradient primaryHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.brandViolet, AppColors.brandIndigo],
  );

  static const LinearGradient primarySoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x149619F1), Color(0x104237E7)],
  );

  static const LinearGradient heroWash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x1A9619F1), Color(0x00FFFFFF)],
  );
}
