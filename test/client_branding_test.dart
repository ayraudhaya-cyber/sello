import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_colors.dart';
import 'package:sello/core/theme/app_gradients.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/core/theme/theme_extensions.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/widgets/branding/branded_logo.dart';

void main() {
  test('missing branding falls back to Sello', () {
    final branding = ClientBranding.fromSettings(CompanySettings.defaults);
    expect(branding.hasCustomLogo, isFalse);
    expect(branding.hasCustomLightLogo, isFalse);
    expect(branding.hasCustomAccent, isFalse);
    expect(branding.hasCustomNavBackground, isFalse);
    expect(branding.accent, AppColors.primary);
    expect(branding.navGradient, AppGradients.navRail);
    expect(branding.logoUrl, isNull);
    expect(branding.logoLightUrl, isNull);
  });

  test('invalid colour and logo fall back to Sello', () {
    final branding = ClientBranding.resolve(
      logoUrl: 'not-a-url',
      primaryColor: 'purple',
    );
    expect(branding.hasCustomLogo, isFalse);
    expect(branding.hasCustomAccent, isFalse);
    expect(branding.accent, AppColors.primary);
  });

  test('valid client colour is applied as accent', () {
    final branding = ClientBranding.resolve(primaryColor: '#0B6E4F');
    expect(branding.hasCustomAccent, isTrue);
    expect(branding.hasCustomLogo, isFalse);
    expect(branding.accent, isNot(AppColors.primary));
    expect(
      _contrast(branding.onAccent, branding.accent),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('very light client colour is darkened for contrast', () {
    final branding = ClientBranding.resolve(primaryColor: '#F4F0FF');
    expect(branding.hasCustomAccent, isTrue);
    expect(
      _contrast(branding.onAccent, branding.accent),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('https logo url is accepted', () {
    final branding = ClientBranding.resolve(
      logoUrl: 'https://cdn.example.com/client-logo.png',
    );
    expect(branding.hasCustomLogo, isTrue);
    expect(branding.logoUrl, 'https://cdn.example.com/client-logo.png');
    expect(branding.accent, AppColors.primary);
  });

  test('light-surface logo does not replace the reverse wordmark', () {
    final branding = ClientBranding.resolve(
      logoLightUrl: 'https://cdn.example.com/logo-light.png',
    );
    expect(branding.hasCustomLightLogo, isTrue);
    expect(branding.hasCustomLogo, isFalse);
    expect(branding.logoLightUrl, 'https://cdn.example.com/logo-light.png');
  });

  test('missing logo and colour keep Sello branding', () {
    final branding = ClientBranding.resolve(logoUrl: null, primaryColor: null);
    expect(branding.hasCustomLogo, isFalse);
    expect(branding.hasCustomAccent, isFalse);
    expect(branding.accent, AppColors.primary);
    expect(ClientBranding.fromSettings(CompanySettings.defaults).accent,
        AppColors.primary);
  });

  test('themed Sello branding matches default primary', () {
    final theme = AppTheme.themed(ClientBranding.sello);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.onPrimary, AppColors.onPrimary);
    expect(theme.colorScheme.primaryContainer, AppColors.primaryContainer);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.colorScheme.error, AppColors.error);
    expect(theme.hoverColor, AppColors.primary.withValues(alpha: 0.06));
    expect(theme.extension<SelloColors>()!.brandViolet, AppColors.brandViolet);
    expect(
      theme.extension<SelloColors>()!.surfaceSelected,
      AppColors.surfaceSelected,
    );
    expect(theme.extension<SelloColors>()!.navRail, AppGradients.navRail);
  });

  test('themed client branding keeps Sello canvas', () {
    final branding = ClientBranding.resolve(primaryColor: '#C2410C');
    final theme = AppTheme.themed(branding);
    expect(theme.colorScheme.primary, branding.accent);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
  });

  test('custom accent replaces Sello purple on accent tokens only', () {
    final branding = ClientBranding.resolve(primaryColor: '#0B6E4F');
    final theme = AppTheme.themed(branding);
    final sello = theme.extension<SelloColors>()!;

    expect(theme.colorScheme.primary, branding.accent);
    expect(theme.colorScheme.onPrimary, branding.onAccent);
    expect(theme.colorScheme.primaryContainer, branding.accentContainer);
    expect(theme.colorScheme.onPrimaryContainer, branding.onAccentContainer);

    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.colorScheme.onSurface, AppColors.textPrimary);
    expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondary);
    expect(theme.colorScheme.outline, AppColors.outline);
    expect(theme.colorScheme.error, AppColors.error);
    expect(theme.colorScheme.secondary, AppColors.brandIndigo);
    expect(theme.colorScheme.secondaryContainer, AppColors.primaryContainer);

    expect(sello.brandViolet, branding.accent);
    expect(sello.surfaceSelected, branding.surfaceSelected);
    expect(sello.brandIndigo, AppColors.brandIndigo);
    expect(sello.primaryGradient, AppGradients.primary);
    expect(sello.navRail, AppGradients.navRail);
    expect(sello.success, AppColors.success);
    expect(sello.warning, AppColors.warning);
    expect(sello.textSecondary, AppColors.textSecondary);
  });

  test('disabled custom colour keeps the default Sello theme accent', () {
    final fromFlagOff = ClientBranding.fromSettings(CompanySettings.defaults);
    final theme = AppTheme.themed(fromFlagOff);
    expect(fromFlagOff.hasCustomAccent, isFalse);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.primaryContainer, AppColors.primaryContainer);
    expect(theme.hoverColor, AppColors.primary.withValues(alpha: 0.06));
    expect(theme.extension<SelloColors>()!.brandViolet, AppColors.brandViolet);
    expect(
      theme.extension<SelloColors>()!.surfaceSelected,
      AppColors.surfaceSelected,
    );
  });

  test('stored logo and colour are ignored when branding is not entitled', () {
    final settings = CompanySettings.fromJson({
      'id': 'settings-1',
      'company_id': 'company-1',
      'currency': 'USD',
      'custom_branding_enabled': false,
      'logo_url': 'https://cdn.example.com/logo.png',
      'logo_light_url': 'https://cdn.example.com/logo-light.png',
      'primary_color': '#0B6E4F',
      'nav_background_color': '#1B3A4B',
    });
    final branding = ClientBranding.fromSettings(settings);
    expect(branding.hasCustomLogo, isFalse);
    expect(branding.hasCustomLightLogo, isFalse);
    expect(branding.hasCustomAccent, isFalse);
    expect(branding.hasCustomNavBackground, isFalse);
    expect(branding.accent, AppColors.primary);
    expect(branding.navGradient, AppGradients.navRail);
    expect(AppTheme.themed(branding).colorScheme.primary, AppColors.primary);
    expect(
      AppTheme.themed(branding).extension<SelloColors>()!.navRail,
      AppGradients.navRail,
    );
  });

  test('entitled settings apply stored logo, colour, and chrome', () {
    final settings = CompanySettings.fromJson({
      'id': 'settings-1',
      'company_id': 'company-1',
      'currency': 'USD',
      'custom_branding_enabled': true,
      'logo_url': 'https://cdn.example.com/logo.png',
      'logo_light_url': 'https://cdn.example.com/logo-light.png',
      'primary_color': '#0B6E4F',
      'nav_background_color': '#1B3A4B',
    });
    final branding = ClientBranding.fromSettings(settings);
    expect(branding.hasCustomLogo, isTrue);
    expect(branding.hasCustomLightLogo, isTrue);
    expect(branding.hasCustomAccent, isTrue);
    expect(branding.hasCustomNavBackground, isTrue);
  });

  test('custom nav chrome is darkened for a light wordmark', () {
    final branding = ClientBranding.resolve(navBackgroundColor: '#F4F0FF');
    expect(branding.hasCustomNavBackground, isTrue);
    expect(branding.hasCustomAccent, isFalse);
    expect(HSLColor.fromColor(branding.navTop).lightness, lessThanOrEqualTo(0.28));
    expect(
      _contrast(Colors.white, branding.navTop),
      greaterThanOrEqualTo(4.5),
    );
    expect(branding.navGradient, isNot(AppGradients.navRail));
    expect(branding.accent, AppColors.primary);
  });

  test('custom nav replaces only the rail on the theme', () {
    final branding = ClientBranding.resolve(navBackgroundColor: '#1B3A4B');
    final theme = AppTheme.themed(branding);
    final sello = theme.extension<SelloColors>()!;
    expect(sello.navRail, branding.navGradient);
    expect(sello.navRail, isNot(AppGradients.navRail));
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(sello.brandViolet, AppColors.brandViolet);
    expect(sello.primaryGradient, AppGradients.primary);
  });

  testWidgets('Sello mark stays a square icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrandedLogo(size: 32),
        ),
      ),
    );
    final box = tester.getSize(find.byType(BrandedLogo));
    expect(box.width, 32);
    expect(box.height, 32);
  });

  testWidgets('custom wordmark uses a wide max constraint, not a square',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandedLogo(
            size: 32,
            maxWidth: 180,
            branding: ClientBranding.resolve(
              logoUrl: 'https://cdn.example.com/namson-wordmark.png',
            ),
          ),
        ),
      ),
    );
    final constraints = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .map((w) => w.constraints)
        .firstWhere(
          (c) => c.maxWidth == 180 && c.maxHeight == 32,
          orElse: () => const BoxConstraints(),
        );
    expect(constraints.maxWidth, 180);
    expect(constraints.maxHeight, 32);
    expect(constraints.maxWidth, greaterThan(constraints.maxHeight));
    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.width, isNull);
    expect(image.height, isNull);
    expect(image.fit, BoxFit.contain);
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
