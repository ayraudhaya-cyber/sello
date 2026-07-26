/// 8-point spacing scale (with 4 as the half-step).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double mdPlus = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double xxxl = 48;

  /// Page gutter on phones.
  static const double pageMobile = 20;

  /// Page gutter on tablets.
  static const double pageTablet = 28;

  /// Page gutter on desktop.
  static const double pageDesktop = 32;

  /// Comfortable touch target minimum.
  static const double touchTarget = 48;

  /// Default card inner padding.
  static const double cardPadding = 20;

  /// Shell sidebar width (desktop).
  static const double sidebarWidth = 268;

  /// Shell sidebar width (tablet).
  static const double sidebarWidthCompact = 228;

  /// Top chrome height.
  static const double topBarHeight = 64;
}
