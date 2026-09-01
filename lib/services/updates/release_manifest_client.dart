import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/services/updates/release_manifest_config.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

class ReleaseManifestFetchException implements Exception {
  const ReleaseManifestFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fetches and validates the public Sello release JSON.
class ReleaseManifestClient {
  ReleaseManifestClient({
    http.Client? httpClient,
    this.urlOverride,
    this.timeout = ReleaseManifestConfig.fetchTimeout,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String? urlOverride;
  final Duration timeout;

  Future<SelloReleaseManifest> fetch({
    String? url,
    ReleaseAppKind? app,
  }) async {
    final resolved = (url ?? urlOverride ?? ReleaseManifestConfig.resolveUrl())
        .trim();
    if (resolved.isEmpty) {
      throw const ReleaseManifestFetchException(
        'Release information is not configured.',
      );
    }

    final uri = Uri.tryParse(resolved);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const ReleaseManifestFetchException(
        'Release information URL is invalid.',
      );
    }

    late final http.Response response;
    try {
      response = await _http.get(uri).timeout(timeout);
    } on Exception {
      throw const ReleaseManifestFetchException(
        'Unable to reach release information.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReleaseManifestFetchException(
        'Release information returned ${response.statusCode}.',
      );
    }

    final body = response.body.trim();
    if (body.isEmpty) {
      throw const ReleaseManifestFetchException(
        'Release information was empty.',
      );
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const ReleaseManifestFetchException(
        'Release information was not valid JSON.',
      );
    }

    try {
      return SelloReleaseManifest.parse(decoded, app: app);
    } on FormatException catch (error) {
      throw ReleaseManifestFetchException(error.message);
    }
  }
}
