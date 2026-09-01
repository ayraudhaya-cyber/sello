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

  Future<String> signProductImage(String path) {
    return createSignedUrl(
      bucket: MediaConstants.productImagesBucket,
      path: path,
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
