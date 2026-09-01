import 'package:flutter/widgets.dart';
import 'package:sello/core/responsive/app_breakpoints.dart';
import 'package:sello/core/theme/app_spacing.dart';

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;

  AppWindowSize get windowSize => windowSizeFor(screenWidth);

  bool get isMobile => windowSize.isMobile;
  bool get isTablet => windowSize.isTablet;
  bool get isDesktop => windowSize.isDesktop;

  /// Horizontal page padding that scales with breakpoint.
  double get pagePadding => switch (windowSize) {
        AppWindowSize.mobile => AppSpacing.pageMobile,
        AppWindowSize.tablet => AppSpacing.pageTablet,
        AppWindowSize.desktop => AppSpacing.pageDesktop,
      };

  /// Max content width for readable desktop layouts.
  ///
  /// Wide monitors get a larger canvas so dashboards stop feeling stranded
  /// in the middle of the screen, while page gutters keep content centered
  /// and away from the window edges.
  double get contentMaxWidth => switch (windowSize) {
        AppWindowSize.mobile => double.infinity,
        AppWindowSize.tablet => 1040,
        AppWindowSize.desktop =>
          AppBreakpoints.isWideDesktop(screenWidth) ? 1520 : 1360,
      };

  T responsiveValue<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    return switch (windowSize) {
      AppWindowSize.mobile => mobile,
      AppWindowSize.tablet => tablet ?? mobile,
      AppWindowSize.desktop => desktop ?? tablet ?? mobile,
    };
  }
}
