import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/client_branding.dart';

/// Tenant branding for splash, chrome, and accent colour.
///
/// Starts as Sello, hydrates last-known values from local cache (so splash /
/// login can white-label before session), then refreshes from
/// `company_settings` once a session exists.
class BrandingNotifier extends Notifier<ClientBranding> {
  static const _logoKey = 'sello.branding.logo_url';
  static const _logoLightKey = 'sello.branding.logo_light_url';
  static const _colorKey = 'sello.branding.primary_color';
  static const _navKey = 'sello.branding.nav_background_color';

  @override
  ClientBranding build() {
    ref.listen(currentSessionProvider, (previous, next) {
      if (next?.company.id != previous?.company.id) {
        Future<void>.microtask(_refreshFromSession);
      }
    });
    Future<void>.microtask(_hydrate);
    return ClientBranding.sello;
  }

  Future<void> _hydrate() async {
    await _loadCache();
    await _refreshFromSession();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = ClientBranding.resolve(
        logoUrl: prefs.getString(_logoKey),
        logoLightUrl: prefs.getString(_logoLightKey),
        primaryColor: prefs.getString(_colorKey),
        navBackgroundColor: prefs.getString(_navKey),
      );
      if (cached.hasCustomLogo ||
          cached.hasCustomLightLogo ||
          cached.hasCustomAccent ||
          cached.hasCustomNavBackground) {
        state = cached;
      }
    } catch (_) {
      // Tests / missing plugin — keep Sello defaults.
    }
  }

  Future<void> _refreshFromSession() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    try {
      final settings =
          await ref.read(companySettingsRepositoryProvider).fetchForCompany(
                session.company.id,
                employeeId: session.employee.id,
              );
      final entitled = settings.customBrandingEnabled;
      state = ClientBranding.fromSettings(settings);
      await _persist(
        logoUrl: entitled ? settings.logoUrl : null,
        logoLightUrl: entitled ? settings.logoLightUrl : null,
        primaryColor: entitled ? settings.primaryColor : null,
        navBackgroundColor: entitled ? settings.navBackgroundColor : null,
      );
    } catch (_) {
      // Keep cache or Sello fallback already in [state].
    }
  }

  /// Re-read tenant branding after settings save.
  Future<void> refresh() => _refreshFromSession();

  Future<void> _persist({
    String? logoUrl,
    String? logoLightUrl,
    String? primaryColor,
    String? navBackgroundColor,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logo = logoUrl?.trim() ?? '';
      final light = logoLightUrl?.trim() ?? '';
      final color = primaryColor?.trim() ?? '';
      final nav = navBackgroundColor?.trim() ?? '';
      if (logo.isNotEmpty) {
        await prefs.setString(_logoKey, logo);
      } else {
        await prefs.remove(_logoKey);
      }
      if (light.isNotEmpty) {
        await prefs.setString(_logoLightKey, light);
      } else {
        await prefs.remove(_logoLightKey);
      }
      if (color.isNotEmpty) {
        await prefs.setString(_colorKey, color);
      } else {
        await prefs.remove(_colorKey);
      }
      if (nav.isNotEmpty) {
        await prefs.setString(_navKey, nav);
      } else {
        await prefs.remove(_navKey);
      }
    } catch (_) {}
  }
}

final brandingProvider =
    NotifierProvider<BrandingNotifier, ClientBranding>(BrandingNotifier.new);
