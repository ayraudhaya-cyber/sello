/// Centralized layout breakpoints for adaptive UI.
abstract final class AppBreakpoints {
  /// Phones — bottom navigation, single column.
  static const double mobile = 600;

  /// Tablets — navigation rail, optional two-column.
  static const double tablet = 1024;

  /// Desktops / large windows — permanent sidebar, tables, multi-column.
  static const double desktop = 1440;

  static bool isMobile(double width) => width < mobile;

  static bool isTablet(double width) => width >= mobile && width < tablet;

  static bool isDesktop(double width) => width >= tablet;

  static bool isWideDesktop(double width) => width >= desktop;
}

enum AppWindowSize { mobile, tablet, desktop }

extension AppWindowSizeX on AppWindowSize {
  bool get isMobile => this == AppWindowSize.mobile;
  bool get isTablet => this == AppWindowSize.tablet;
  bool get isDesktop => this == AppWindowSize.desktop;
}

AppWindowSize windowSizeFor(double width) {
  if (AppBreakpoints.isMobile(width)) return AppWindowSize.mobile;
  if (AppBreakpoints.isTablet(width)) return AppWindowSize.tablet;
  return AppWindowSize.desktop;
}
