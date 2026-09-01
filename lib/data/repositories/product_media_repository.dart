import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_media_paths.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Product gallery persistence — UI never talks to Storage directly.
class ProductMediaRepository {
  ProductMediaRepository({
    SupabaseClient? client,
    MediaStorageService? storage,
    MediaService? media,
  })  : _client = client ?? SupabaseService.client,
        _storage = storage ?? MediaStorageService(),
        _media = media ?? MediaService();

  final SupabaseClient _client;
  final MediaStorageService _storage;
  final MediaService _media;

  Future<List<ProductImage>> fetchForProduct(String productId) async {
    try {
      final rows = await _client
          .from('product_images')
          .select('id, product_id, storage_path, sort_order, is_primary')
          .eq('product_id', productId)
          .order('sort_order');

      final images = <ProductImage>[];
      for (final row in rows as List) {
        final image = ProductImage.fromJson(Map<String, dynamic>.from(row));
        try {
          final url = await _storage.signProductImage(image.storagePath);
          images.add(image.copyWith(networkUrl: url));
        } catch (_) {
          images.add(image);
        }
      }
      return images;
    } on PostgrestException catch (error) {
      throw ValidationFailure(error.message);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Deletes every gallery file + `product_images` row for a product.
  Future<void> purgeProductImages(String productId) async {
    try {
      final rows = await _client
          .from('product_images')
          .select('id, storage_path')
          .eq('product_id', productId);

      final paths = <String>[];
      for (final row in rows as List) {
        final path = row['storage_path'] as String?;
        if (path != null && path.isNotEmpty) paths.add(path);
      }

      if (paths.isNotEmpty) {
        await _storage.deleteMany(
          bucket: MediaConstants.productImagesBucket,
          paths: paths,
        );
      }

      await _client.from('product_images').delete().eq('product_id', productId);
    } on PostgrestException catch (error) {
      throw ValidationFailure(error.message);
    } on StorageException catch (error) {
      throw ValidationFailure(
        error.message.isEmpty
            ? 'Unable to remove product photos.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<String?> signPath(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    try {
      return await _storage.signProductImage(storagePath);
    } catch (_) {
      return null;
    }
  }

  /// Sync a gallery draft to storage + `product_images`.
  ///
  /// First active image is always primary. New / replaced images upload to
  /// predictable slot paths; untouched remotes only update order flags.
  Future<void> syncGallery({
    required String companyId,
    required String employeeId,
    required String productId,
    required List<MediaGalleryDraft> drafts,
    void Function(MediaUploadProgress progress)? onProgress,
  }) async {
    final active = drafts.where((d) => !d.removed && d.hasPreview).toList()
      ..sort((a, b) {
        if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });

    if (active.length > MediaConstants.kMaxProductImages) {
      throw ValidationFailure(
        'Maximum of ${MediaConstants.kMaxProductImages} product photos.',
      );
    }

    final normalized = <MediaGalleryDraft>[
      for (var i = 0; i < active.length; i++)
        active[i].copyWith(sortOrder: i, isPrimary: i == 0),
    ];

    try {
      final existing = await _client
          .from('product_images')
          .select('id, storage_path')
          .eq('product_id', productId);

      final existingRows = (existing as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final keepRemoteIds = normalized
          .map((d) => d.remoteId)
          .whereType<String>()
          .toSet();

      for (final row in existingRows) {
        final id = row['id'] as String;
        if (keepRemoteIds.contains(id)) continue;
        final path = row['storage_path'] as String?;
        await _client.from('product_images').delete().eq('id', id);
        if (path != null && path.isNotEmpty) {
          try {
            await _storage.deleteProductImage(path);
          } catch (_) {}
        }
      }

      for (var i = 0; i < normalized.length; i++) {
        final draft = normalized[i];
        onProgress?.call(
          MediaUploadProgress(
            phase: MediaUploadPhase.uploading,
            message: 'Uploading photo ${i + 1} of ${normalized.length}...',
            fraction: (i + 0.15) / (normalized.length + 0.15),
          ),
        );

        late final String storagePath;

        if (draft.dirty && draft.localBytes != null) {
          late final ProcessedMedia processed;
          if (draft.optimized) {
            processed = ProcessedMedia(
              bytes: draft.localBytes!,
              contentType: MediaConstants.jpegContentType,
              extension: MediaConstants.jpegExtension,
              width: 0,
              height: 0,
            );
          } else {
            onProgress?.call(
              const MediaUploadProgress(
                phase: MediaUploadPhase.optimizing,
                message: 'Optimizing...',
              ),
            );
            processed = await _media.processor.optimize(draft.localBytes!);
          }
          storagePath = ProductMediaPaths.buildPath(
            companyId: companyId,
            productId: productId,
            slotIndex: i,
            extension: processed.extension,
          );
          await _deleteSlotAliases(
            companyId: companyId,
            productId: productId,
            slotIndex: i,
            keepPath: storagePath,
          );
          await _media.upload(
            bucket: MediaConstants.productImagesBucket,
            path: storagePath,
            media: processed,
            onProgress: onProgress,
          );
          // Replacing an existing row that pointed at a different path.
          if (draft.storagePath != null &&
              draft.storagePath!.isNotEmpty &&
              draft.storagePath != storagePath) {
            try {
              await _storage.deleteProductImage(draft.storagePath!);
            } catch (_) {}
          }
        } else if (draft.storagePath != null) {
          storagePath = draft.storagePath!;
        } else {
          continue;
        }

        if (draft.remoteId != null) {
          await _client.from('product_images').update({
            'storage_path': storagePath,
            'sort_order': i,
            'is_primary': i == 0,
            'updated_by': employeeId,
          }).eq('id', draft.remoteId!);
        } else {
          await _client.from('product_images').insert({
            'company_id': companyId,
            'product_id': productId,
            'storage_path': storagePath,
            'sort_order': i,
            'is_primary': i == 0,
            'created_by': employeeId,
            'updated_by': employeeId,
          });
        }
      }

      onProgress?.call(
        const MediaUploadProgress(
          phase: MediaUploadPhase.success,
          message: 'Photos saved',
          fraction: 1,
        ),
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.isEmpty
            ? 'Unable to update product photos.'
            : error.message,
      );
    } on StorageException catch (error) {
      throw ValidationFailure(
        error.message.isEmpty
            ? 'Unable to upload product photos.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> _deleteSlotAliases({
    required String companyId,
    required String productId,
    required int slotIndex,
    required String keepPath,
  }) async {
    for (final ext in ['webp', 'jpg', 'jpeg', 'png']) {
      final path = ProductMediaPaths.buildPath(
        companyId: companyId,
        productId: productId,
        slotIndex: slotIndex,
        extension: ext,
      );
      if (path == keepPath) continue;
      try {
        await _storage.deleteProductImage(path);
      } catch (_) {}
    }
  }
}
