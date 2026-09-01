import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:sello/core/theme/app_colors.dart';
import 'package:sello/core/theme/app_gradients.dart';
import 'package:sello/shared/models/company_settings.dart';

/// Resolved tenant branding for splash, chrome, and accent colour.
///
/// Missing or invalid values fall back to Sello defaults. The launcher icon
/// is never replaced — this only affects in-app surfaces.
class ClientBranding extends Equatable {
  const ClientBranding({
    this.logoUrl,
    this.logoLightUrl,
    required this.accent,
    required this.onAccent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.surfaceSelected,
    required this.navAccent,
    required this.navTop,
    required this.navMid,
    required this.navBottom,
    this.hasCustomAccent = false,
    this.hasCustomNavBackground = false,
  });

  /// HTTPS URL to the reverse wordmark (dark chrome), or null for Sello.
  final String? logoUrl;

  /// HTTPS URL to the dark-ink wordmark (light canvases), or null for Sello.
  final String? logoLightUrl;

  /// Accessible accent used for buttons, selected nav, and highlights.
  final Color accent;
  final Color onAccent;
  final Color accentHover;
  final Color accentPressed;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color surfaceSelected;

  /// Light tint of [accent] for selected icons on the dark Hub rail.
  final Color navAccent;

  /// Dark chrome stops for sidebar / branded splash (Sello rail by default).
  final Color navTop;
  final Color navMid;
  final Color navBottom;

  final bool hasCustomAccent;
  final bool hasCustomNavBackground;

  bool get hasCustomLogo => logoUrl != null;
  bool get hasCustomLightLogo => logoLightUrl != null;

  LinearGradient get navGradient => hasCustomNavBackground
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [navTop, navMid, navBottom],
          stops: const [0.0, 0.55, 1.0],
        )
      : AppGradients.navRail;

  static const sello = ClientBranding(
    accent: AppColors.primary,
    onAccent: AppColors.onPrimary,
    accentHover: Color(0xFF7B5CF5),
    accentPressed: AppColors.brandIndigo,
    accentContainer: AppColors.primaryContainer,
    onAccentContainer: AppColors.onPrimaryContainer,
    surfaceSelected: AppColors.surfaceSelected,
    navAccent: AppColors.navAccent,
    navTop: AppColors.navTop,
    navMid: AppColors.navMid,
    navBottom: AppColors.navBottom,
  );

  factory ClientBranding.fromSettings(CompanySettings settings) {
    if (!settings.customBrandingEnabled) {
      return ClientBranding.sello;
    }
    return ClientBranding.resolve(
      logoUrl: settings.logoUrl,
      logoLightUrl: settings.logoLightUrl,
      primaryColor: settings.primaryColor,
      navBackgroundColor: settings.navBackgroundColor,
    );
  }

  factory ClientBranding.resolve({
    String? logoUrl,
    String? logoLightUrl,
    String? primaryColor,
    String? navBackgroundColor,
  }) {
    final logo = _usableLogoUrl(logoUrl);
    final lightLogo = _usableLogoUrl(logoLightUrl);
    final accentParsed = _parseHexColor(primaryColor);
    final navParsed = _parseHexColor(navBackgroundColor);

    var branding = accentParsed == null
        ? ClientBranding(
            logoUrl: logo,
            logoLightUrl: lightLogo,
            accent: sello.accent,
            onAccent: sello.onAccent,
            accentHover: sello.accentHover,
            accentPressed: sello.accentPressed,
            accentContainer: sello.accentContainer,
            onAccentContainer: sello.onAccentContainer,
            surfaceSelected: sello.surfaceSelected,
            navAccent: sello.navAccent,
            navTop: sello.navTop,
            navMid: sello.navMid,
            navBottom: sello.navBottom,
          )
        : _fromAccent(
            accentParsed,
            logoUrl: logo,
            logoLightUrl: lightLogo,
          );

    if (navParsed != null) {
      final chrome = _navChromeFrom(navParsed);
      branding = branding.copyWith(
        navTop: chrome.$1,
        navMid: chrome.$2,
        navBottom: chrome.$3,
        hasCustomNavBackground: true,
      );
    }
    return branding;
  }

  ClientBranding copyWith({
    String? logoUrl,
    String? logoLightUrl,
    Color? accent,
    Color? onAccent,
    Color? accentHover,
    Color? accentPressed,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? surfaceSelected,
    Color? navAccent,
    Color? navTop,
    Color? navMid,
    Color? navBottom,
    bool? hasCustomAccent,
    bool? hasCustomNavBackground,
    bool clearLogoUrl = false,
    bool clearLogoLightUrl = false,
  }) {
    return ClientBranding(
      logoUrl: clearLogoUrl ? null : (logoUrl ?? this.logoUrl),
      logoLightUrl:
          clearLogoLightUrl ? null : (logoLightUrl ?? this.logoLightUrl),
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      navAccent: navAccent ?? this.navAccent,
      navTop: navTop ?? this.navTop,
      navMid: navMid ?? this.navMid,
      navBottom: navBottom ?? this.navBottom,
      hasCustomAccent: hasCustomAccent ?? this.hasCustomAccent,
      hasCustomNavBackground:
          hasCustomNavBackground ?? this.hasCustomNavBackground,
    );
  }

  static ClientBranding _fromAccent(
    Color raw, {
    String? logoUrl,
    String? logoLightUrl,
  }) {
    var accent = raw;
    var lightness = HSLColor.fromColor(accent).lightness;
    while (_contrastRatio(Colors.white, accent) < 4.5 && lightness > 0.18) {
      lightness -= 0.06;
      accent = HSLColor.fromColor(accent).withLightness(lightness).toColor();
    }

    final whiteContrast = _contrastRatio(Colors.white, accent);
    final onAccent =
        whiteContrast >= 4.5 ? Colors.white : AppColors.textPrimary;

    final hover = _shiftLightness(accent, 0.06);
    final pressed = _shiftLightness(accent, -0.10);
    final container = Color.lerp(accent, Colors.white, 0.90)!;
    final selected = Color.lerp(accent, Colors.white, 0.92)!;
    final navAccent = Color.lerp(accent, Colors.white, 0.42)!;
    final onContainer = _contrastRatio(AppColors.textPrimary, container) >= 4.5
        ? AppColors.textPrimary
        : AppColors.onPrimaryContainer;

    return ClientBranding(
      logoUrl: logoUrl,
      logoLightUrl: logoLightUrl,
      accent: accent,
      onAccent: onAccent,
      accentHover: hover,
      accentPressed: pressed,
      accentContainer: container,
      onAccentContainer: onContainer,
      surfaceSelected: selected,
      navAccent: navAccent,
      navTop: sello.navTop,
      navMid: sello.navMid,
      navBottom: sello.navBottom,
      hasCustomAccent: true,
    );
  }

  /// Dark enough for a light wordmark; stepped like the Sello rail.
  static (Color, Color, Color) _navChromeFrom(Color raw) {
    var color = raw;
    var lightness = HSLColor.fromColor(color).lightness;
    while ((lightness > 0.28 || _contrastRatio(Colors.white, color) < 4.5) &&
        lightness > 0.08) {
      lightness -= 0.05;
      color = HSLColor.fromColor(raw).withLightness(lightness).toColor();
    }
    return (
      color,
      _shiftLightness(color, -0.06),
      _shiftLightness(color, -0.12),
    );
  }

  static String? _usableLogoUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.host.contains('.')) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return value;
  }

  static final _hexPattern = RegExp(r'^#?([0-9A-Fa-f]{6})$');

  /// Canonical `#RRGGBB`, or null when empty / invalid.
  static String? normalizeHex(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final match = _hexPattern.firstMatch(value);
    if (match == null) return null;
    return '#${match.group(1)!.toUpperCase()}';
  }

  static Color? _parseHexColor(String? raw) {
    final normalized = normalizeHex(raw);
    if (normalized == null) return null;
    final hex = int.tryParse(normalized.substring(1), radix: 16);
    if (hex == null) return null;
    return Color(0xFF000000 | hex);
  }

  static Color _shiftLightness(Color color, double delta) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.08, 0.92))
        .toColor();
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  List<Object?> get props => [
        logoUrl,
        logoLightUrl,
        accent,
        onAccent,
        accentHover,
        accentPressed,
        accentContainer,
        onAccentContainer,
        surfaceSelected,
        navAccent,
        navTop,
        navMid,
        navBottom,
        hasCustomAccent,
        hasCustomNavBackground,
      ];
}
