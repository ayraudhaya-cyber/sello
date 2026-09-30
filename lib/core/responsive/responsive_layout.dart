import 'dart:math' as math;

import 'package:sello/core/theme/app_spacing.dart';

/// Content-width layout math for grids, pairs, and charts.
///
/// Window breakpoints ([AppBreakpoints]) still decide chrome (sidebar vs
/// drawer). Card columns, two-up splits, and chart heights should use the
/// **available content width** so Hub pages stay comfortable after the
/// sidebar and page gutters are subtracted.
abstract final class ResponsiveLayout {
  /// Comfortable minimum for a KPI / stat card (currency still readable).
  static const double statCardMinWidth = 180;

  /// Comfortable minimum for a dashboard / report section card.
  static const double sectionCardMinWidth = 300;

  /// Comfortable minimum for a settings / form control in a two-up row.
  static const double formFieldMinWidth = 240;

  /// Content width at which Settings keeps a side rail (vs horizontal tabs).
  static const double settingsSplitMinWidth = 720;

  /// How many columns fit without squeezing items below [minItemWidth].
  static int columnsFor({
    required double width,
    required int itemCount,
    double minItemWidth = statCardMinWidth,
    int maxColumns = 12,
    double gap = AppSpacing.gap,
  }) {
    if (itemCount <= 0) return 1;
    if (!width.isFinite || width <= 0) return 1;
    final cap = math.min(itemCount, math.max(1, maxColumns));
    for (var cols = cap; cols >= 1; cols--) {
      final itemWidth = (width - gap * (cols - 1)) / cols;
      if (itemWidth >= minItemWidth) return cols;
    }
    return 1;
  }

  /// Whether [itemCount] siblings can share [width] without dropping below
  /// [minItemWidth] (honours [flexes] when provided).
  static bool canFitRow({
    required double width,
    required int itemCount,
    required double minItemWidth,
    double gap = AppSpacing.gap,
    List<int>? flexes,
  }) {
    if (itemCount <= 1) return true;
    if (!width.isFinite || width <= 0) return true;
    final available = width - gap * (itemCount - 1);
    if (available < minItemWidth) return false;
    if (flexes == null || flexes.length != itemCount) {
      return available / itemCount >= minItemWidth;
    }
    final totalFlex = flexes.fold<int>(0, (sum, flex) => sum + flex);
    if (totalFlex <= 0) return false;
    for (final flex in flexes) {
      if (available * (flex / totalFlex) < minItemWidth) return false;
    }
    return true;
  }

  /// Chart plot height from available width — readable, not a tall empty box.
  static double chartHeight(
    double width, {
    double min = 140,
    double max = 220,
    double ratio = 0.28,
  }) {
    if (!width.isFinite || width <= 0) return min;
    return (width * ratio).clamp(min, max);
  }
}
