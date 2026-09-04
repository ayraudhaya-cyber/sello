import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

void main() {
  group('custom_branding_enabled', () {
    test('defaults to false so unentitled tenants see no branding settings', () {
      expect(CompanySettings.defaults.customBrandingEnabled, isFalse);
    });

    test('fromJson treats a missing flag as false', () {
      final settings = CompanySettings.fromJson(_row());
      expect(settings.customBrandingEnabled, isFalse);
    });

    test('fromJson reads an entitled tenant', () {
      final settings = CompanySettings.fromJson(
        _row({'custom_branding_enabled': true}),
      );
      expect(settings.customBrandingEnabled, isTrue);
    });

    test('missing owner_setup_completed is complete for existing tenants', () {
      expect(CompanySettings.fromJson(_row()).ownerSetupCompleted, isTrue);
    });

    test('fromJson reads an optional document logo separately from brand assets', () {
      final settings = CompanySettings.fromJson(
        _row({
          'document_logo_url': 'https://cdn.example.com/document-logo.png',
          'logo_url': 'https://cdn.example.com/brand-dark.png',
        }),
      );
      expect(settings.documentLogoUrl, 'https://cdn.example.com/document-logo.png');
      expect(settings.logoUrl, 'https://cdn.example.com/brand-dark.png');
    });

    test('fromJson reads an optional light-surface logo', () {
      final settings = CompanySettings.fromJson(
        _row({'logo_light_url': 'https://cdn.example.com/logo-light.png'}),
      );
      expect(
        settings.logoLightUrl,
        'https://cdn.example.com/logo-light.png',
      );
    });

    test('fromJson reads an optional nav chrome colour', () {
      final settings = CompanySettings.fromJson(
        _row({'nav_background_color': '#1B3A4B'}),
      );
      expect(settings.navBackgroundColor, '#1B3A4B');
    });

    test('copyWith cannot drop the entitlement flag', () {
      final settings = CompanySettings.fromJson(
        _row({'custom_branding_enabled': true}),
      );
      expect(settings.copyWith(currency: 'LKR').customBrandingEnabled, isTrue);
    });

    test('settings payload never sends branding or the entitlement flag', () {
      final settings = CompanySettings.fromJson(
        _row({
          'custom_branding_enabled': true,
          'logo_url': 'https://cdn.example.com/logo.png',
          'logo_light_url': 'https://cdn.example.com/logo-light.png',
          'primary_color': '#0B6E4F',
          'nav_background_color': '#1B3A4B',
        }),
      );
      final payload = settings.toUpdatePayload(employeeId: 'emp-1');
      expect(payload.containsKey('custom_branding_enabled'), isFalse);
      expect(payload.containsKey('logo_url'), isFalse);
      expect(payload.containsKey('logo_light_url'), isFalse);
      expect(payload.containsKey('primary_color'), isFalse);
      expect(payload.containsKey('nav_background_color'), isFalse);
    });
  });

  group('branding access', () {
    PermissionService service(String role) => PermissionService(
          profile: RolePermissionProfile.forRoleCode(role),
        );

    test('Owner + entitlement can open branding settings', () {
      expect(service('owner').canManageCompanyBranding, isTrue);
      expect(service('owner').canAccessBrandingSettings(true), isTrue);
    });

    test('Owner without entitlement cannot open branding settings', () {
      expect(service('owner').canAccessBrandingSettings(false), isFalse);
    });

    test('Administrator follows the same settings-edit rule as Owner', () {
      expect(service('administrator').canManageCompanyBranding, isTrue);
      expect(service('administrator').canAccessBrandingSettings(true), isTrue);
    });

    test('Manager cannot manage branding even when the tenant is entitled', () {
      expect(service('manager').canEdit(AppModule.settings), isFalse);
      expect(service('manager').canView(AppModule.settings), isTrue);
      expect(service('manager').canManageCompanyBranding, isFalse);
      expect(service('manager').canAccessBrandingSettings(true), isFalse);
    });

    test('Sales Rep cannot manage branding even when the tenant is entitled', () {
      expect(service('sales_representative').canManageCompanyBranding, isFalse);
      expect(
        service('sales_representative').canAccessBrandingSettings(true),
        isFalse,
      );
    });
  });

  group('primary colour validation', () {
    test('normalizes hex to #RRGGBB', () {
      expect(ClientBranding.normalizeHex('0b6e4f'), '#0B6E4F');
      expect(ClientBranding.normalizeHex('#0b6e4f'), '#0B6E4F');
    });

    test('rejects invalid colours', () {
      expect(ClientBranding.normalizeHex('purple'), isNull);
      expect(ClientBranding.normalizeHex('#FFF'), isNull);
      expect(ClientBranding.normalizeHex(''), isNull);
    });
  });
}

Map<String, dynamic> _row([Map<String, dynamic> extras = const {}]) {
  return {
    'id': 'settings-1',
    'company_id': 'company-1',
    'currency': 'USD',
    ...extras,
  };
}
