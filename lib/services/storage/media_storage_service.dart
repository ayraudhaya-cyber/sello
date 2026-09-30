import 'dart:typed_data';

import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Domain-agnostic Supabase Storage adapter.
///
/// UI / features must not talk to Storage directly — go through repositories
/// that call this service.
class MediaStorageService {
  MediaStorageService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// Reuse a signed product URL until shortly before it expires so lists
  /// paint from the browser cache instead of downloading again.
  static final Map<String, ({String url, DateTime freshUntil})>
      _productSignedUrls = {};

  static const _signedUrlLifetime = Duration(minutes: 50);

  Future<String> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    bool upsert = true,
  }) async {
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: upsert,
            contentType: contentType,
          ),
        );
    return path;
  }

  Future<void> delete({
    required String bucket,
    required String path,
  }) async {
    await _client.storage.from(bucket).remove([path]);
  }

  Future<void> deleteMany({
    required String bucket,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) return;
    await _client.storage.from(bucket).remove(paths);
  }

  Future<String> createSignedUrl({
    required String bucket,
    required String path,
    int expiresInSeconds = 60 * 60,
  }) {
    return _client.storage.from(bucket).createSignedUrl(path, expiresInSeconds);
  }

  /// Product-images convenience helpers.
  Future<String> uploadProductImage({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) {
    return upload(
      bucket: MediaConstants.productImagesBucket,
      path: path,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<void> deleteProductImage(String path) {
    return delete(bucket: MediaConstants.productImagesBucket, path: path);
  }

  Future<String> signProductImage(String path) async {
    final cached = _freshProductUrl(path);
    if (cached != null) return cached;
    final url = await createSignedUrl(
      bucket: MediaConstants.productImagesBucket,
      path: path,
    );
    _rememberProductUrl(path, url);
    return url;
  }

  /// Signs many product images in one Storage request per 100 paths.
  ///
  /// Paths signed in the last 50 minutes are reused. Missing files are
  /// omitted. A failed chunk returns no URLs for those paths so the list
  /// can still render without thumbnails.
  Future<Map<String, String>> signProductImages(List<String> paths) async {
    final unique = {
      for (final path in paths)
        if (path.trim().isNotEmpty) path.trim(),
    }.toList();
    if (unique.isEmpty) return const {};

    final urls = <String, String>{};
    final missing = <String>[];
    for (final path in unique) {
      final cached = _freshProductUrl(path);
      if (cached != null) {
        urls[path] = cached;
      } else {
        missing.add(path);
      }
    }

    const chunkSize = 100;
    for (var start = 0; start < missing.length; start += chunkSize) {
      final end = start + chunkSize > missing.length
          ? missing.length
          : start + chunkSize;
      final slice = missing.sublist(start, end);
      try {
        final results = await _client.storage
            .from(MediaConstants.productImagesBucket)
            .createSignedUrlsResult(slice, 60 * 60);
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          if (result is! SignedUrlSuccess || result.signedUrl.isEmpty) {
            continue;
          }
          final requested = i < slice.length ? slice[i] : result.path;
          urls[requested] = result.signedUrl;
          _rememberProductUrl(requested, result.signedUrl);
          if (result.path.isNotEmpty && result.path != requested) {
            urls[result.path] = result.signedUrl;
            _rememberProductUrl(result.path, result.signedUrl);
          }
        }
      } catch (_) {
        // Leave this chunk unsigned.
      }
    }
    return urls;
  }

  String? _freshProductUrl(String path) {
    final hit = _productSignedUrls[path];
    if (hit == null || !hit.freshUntil.isAfter(DateTime.now())) return null;
    return hit.url;
  }

  void _rememberProductUrl(String path, String url) {
    if (path.isEmpty || url.isEmpty) return;
    _productSignedUrls[path] = (
      url: url,
      freshUntil: DateTime.now().add(_signedUrlLifetime),
    );
  }

  Future<String> uploadEmployeeAvatar({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) {
    return upload(
      bucket: MediaConstants.employeeAvatarsBucket,
      path: path,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<void> deleteEmployeeAvatar(String path) {
    return delete(bucket: MediaConstants.employeeAvatarsBucket, path: path);
  }

  Future<String> signEmployeeAvatar(String path) {
    return createSignedUrl(
      bucket: MediaConstants.employeeAvatarsBucket,
      path: path,
    );
  }

  String publicUrl({required String bucket, required String path}) {
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  Future<String> uploadCompanyLogo({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) {
    return upload(
      bucket: MediaConstants.companyBrandingBucket,
      path: path,
      bytes: bytes,
      contentType: contentType,
    );
  }
}
