import 'package:sello/core/router/route_paths.dart';

/// Builds customer-facing document URLs from opaque tokens.
class DocumentLinkFactory {
  const DocumentLinkFactory({this.overrideOrigin});

  /// Test / explicit origin. Production uses [SELLO_PUBLIC_URL] or [Uri.base].
  final String? overrideOrigin;

  static const _envOrigin = String.fromEnvironment('SELLO_PUBLIC_URL');

  String get origin {
    final explicit = (overrideOrigin ?? _envOrigin).trim();
    if (explicit.isNotEmpty) {
      return explicit.endsWith('/')
          ? explicit.substring(0, explicit.length - 1)
          : explicit;
    }
    final base = Uri.base;
    if ((base.scheme == 'http' || base.scheme == 'https') &&
        base.host.isNotEmpty) {
      final port = base.hasPort ? ':${base.port}' : '';
      return '${base.scheme}://${base.host}$port';
    }
    return '';
  }

  /// Public document URL. Empty origin still returns a path for tests.
  String orderDocument(String token) {
    final trimmed = token.trim();
    final path = '${RoutePaths.orderDocument}/$trimmed';
    final root = origin;
    return root.isEmpty ? path : '$root$path';
  }

  bool get hasUsableOrigin => origin.isNotEmpty;
}
