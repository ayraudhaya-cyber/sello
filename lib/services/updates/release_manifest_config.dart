import 'package:flutter/foundation.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

/// Compile-time + runtime location of the public release manifest.
///
/// Latest version is never baked into the app. The installed version comes
/// from the binary; this URL only tells the app where to read remote metadata.
abstract final class ReleaseManifestConfig {
  static const _explicitUrl = String.fromEnvironment(
    'SELLO_RELEASE_MANIFEST_URL',
  );
  static const _publicOrigin = String.fromEnvironment('SELLO_PUBLIC_URL');
  static const _releaseApp = String.fromEnvironment('SELLO_RELEASE_APP');

  static const checkInterval = Duration(hours: 12);
  static const fetchTimeout = Duration(seconds: 8);

  /// Compile-time binary identity. Null when the define is omitted.
  static ReleaseAppKind? get compiledReleaseApp =>
      ReleaseAppKind.tryParse(_releaseApp);

  /// Public JSON URL, or empty when no remote source can be resolved.
  static String resolveUrl({String? overrideUrl, String? overrideOrigin}) {
    final explicit = (overrideUrl ?? _explicitUrl).trim();
    if (explicit.isNotEmpty) return _withoutTrailingSlash(explicit);

    final origin = _origin(overrideOrigin: overrideOrigin);
    if (origin.isEmpty) return '';
    return '$origin/sello-release.json';
  }

  static bool get isConfigured => resolveUrl().isNotEmpty;

  static String _origin({String? overrideOrigin}) {
    final configured = (overrideOrigin ?? _publicOrigin).trim();
    if (configured.isNotEmpty) return _withoutTrailingSlash(configured);

    if (kIsWeb) {
      final base = Uri.base;
      if ((base.scheme == 'http' || base.scheme == 'https') &&
          base.host.isNotEmpty) {
        final port = base.hasPort ? ':${base.port}' : '';
        return '${base.scheme}://${base.host}$port';
      }
    }
    return '';
  }

  static String _withoutTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static AppReleasePlatform get currentPlatform {
    if (kIsWeb) return AppReleasePlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppReleasePlatform.android,
      TargetPlatform.iOS => AppReleasePlatform.ios,
      _ => AppReleasePlatform.other,
    };
  }
}
