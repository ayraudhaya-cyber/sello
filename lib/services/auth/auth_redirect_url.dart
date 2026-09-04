import 'package:flutter/foundation.dart';

/// Builds Supabase Auth `emailRedirectTo` / `redirectTo` URLs.
///
/// Web **release** builds always target the public production origin (or
/// [SELLO_PUBLIC_URL] when set). Debug/profile keeps the current page origin
/// so local `flutter run` can still confirm email against localhost.
///
/// Non-web returns `null` so GoTrue falls back to the Dashboard Site URL.
abstract final class AuthRedirectUrl {
  /// Production Hub / web origin. Must stay in sync with Vercel + Auth URLs.
  static const productionWebOrigin = 'https://sello.cashro.pro';

  static const _envOrigin = String.fromEnvironment('SELLO_PUBLIC_URL');

  /// Full redirect URL for [path] (e.g. `/login`), or `null` on non-web.
  static String? forPath(
    String path, {
    bool? isWeb,
    bool? isRelease,
    Uri? baseUri,
    String? envOrigin,
  }) {
    final web = isWeb ?? kIsWeb;
    if (!web) return null;

    final release = isRelease ?? kReleaseMode;
    final origin = _originFor(
      isRelease: release,
      baseUri: baseUri ?? Uri.base,
      envOrigin: envOrigin ?? _envOrigin,
    );
    if (origin.isEmpty) return null;

    final normalized = path.startsWith('/') ? path : '/$path';
    final parsed = Uri.parse(origin);
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: normalized,
    ).toString();
  }

  static String _originFor({
    required bool isRelease,
    required Uri baseUri,
    required String envOrigin,
  }) {
    if (isRelease) {
      final explicit = envOrigin.trim();
      if (explicit.isNotEmpty) {
        return _stripTrailingSlash(explicit);
      }
      return productionWebOrigin;
    }

    if ((baseUri.scheme == 'http' || baseUri.scheme == 'https') &&
        baseUri.host.isNotEmpty) {
      final port = baseUri.hasPort ? ':${baseUri.port}' : '';
      return '${baseUri.scheme}://${baseUri.host}$port';
    }
    return '';
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
