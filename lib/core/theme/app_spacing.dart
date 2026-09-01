/// Spacing scale matched to the owner dashboard HTML rhythm.
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

  /// Page gutter on phones (HTML ≤860).
  static const double pageMobile = 18;

  /// Page gutter on tablets (HTML ≤1180).
  static const double pageTablet = 28;

  /// Page gutter on desktop.
  static const double pageDesktop = 40;

  /// Vertical rhythm between major page sections.
  static const double section = 20;

  /// Gap between cards in a row.
  static const double gap = 20;

  /// Comfortable touch target minimum.
  static const double touchTarget = 48;

  /// Default height for buttons, inputs and toolbar controls.
  static const double controlHeight = 40;

  /// Compact control height for dense toolbars and inline actions.
  static const double controlHeightCompact = 36;

  /// Default card inner padding.
  static const double cardPadding = 24;

  /// Denser card padding for list rows and compact panels.
  static const double cardPaddingCompact = 16;

  /// Shell sidebar width (desktop) — HTML 268px.
  static const double sidebarWidth = 268;

  /// Shell sidebar width (tablet).
  static const double sidebarWidthCompact = 228;

  /// Top chrome height — HTML 60px.
  static const double topBarHeight = 60;

  /// Max content width inside the main column.
  static const double contentMax = 1780;
}
