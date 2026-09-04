import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/auth/auth_redirect_url.dart';

/// Builds customer-facing document URLs from opaque tokens.
///
/// Links are opened on the customer's phone (WhatsApp/SMS), so the origin must
/// be a public HTTPS host — never localhost from a local `flutter run`.
///
/// Path stays `/d/<opaque-token>` (not invoice number) so links are unguessable.
class DocumentLinkFactory {
  const DocumentLinkFactory({this.overrideOrigin});

  /// Test / explicit origin. Production uses [SELLO_PUBLIC_URL] or
  /// [AuthRedirectUrl.productionWebOrigin].
  final String? overrideOrigin;

  static const _envOrigin = String.fromEnvironment('SELLO_PUBLIC_URL');

  String get origin {
    final explicit = _normalizeOrigin(overrideOrigin ?? _envOrigin);
    if (explicit != null) return explicit;

    final fromBase = _originFromBase(Uri.base);
    if (fromBase != null && !_isLoopbackHost(Uri.base.host)) {
      return fromBase;
    }

    // Customer-facing links must work off-device; never emit localhost.
    return AuthRedirectUrl.productionWebOrigin;
  }

  /// Public document URL for WhatsApp / SMS / copy-link.
  String orderDocument(String token) {
    final trimmed = token.trim();
    final path = '${RoutePaths.orderDocument}/$trimmed';
    final root = origin;
    return root.isEmpty ? path : '$root$path';
  }

  bool get hasUsableOrigin => origin.isNotEmpty;

  static String? _normalizeOrigin(String? raw) {
    final explicit = (raw ?? '').trim();
    if (explicit.isEmpty) return null;
    return explicit.endsWith('/')
        ? explicit.substring(0, explicit.length - 1)
        : explicit;
  }

  static String? _originFromBase(Uri base) {
    if ((base.scheme == 'http' || base.scheme == 'https') &&
        base.host.isNotEmpty) {
      final port = base.hasPort ? ':${base.port}' : '';
      return '${base.scheme}://${base.host}$port';
    }
    return null;
  }

  static bool _isLoopbackHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '0.0.0.0' ||
        h == '::1' ||
        h.endsWith('.localhost');
  }
}
