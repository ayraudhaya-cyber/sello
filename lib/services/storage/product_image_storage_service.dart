import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/shared/models/product_media_paths.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Backward-compatible facade — prefer [MediaStorageService] + [MediaService].
@Deprecated('Use MediaStorageService / MediaService instead')
class ProductImageStorageService {
  ProductImageStorageService({SupabaseClient? client})
      : _storage = MediaStorageService(client: client);

  final MediaStorageService _storage;

  static const bucket = 'product-images';

  String buildPrimaryPath({
    required String companyId,
    required String productId,
  }) {
    return ProductMediaPaths.buildPath(
      companyId: companyId,
      productId: productId,
      slotIndex: 0,
    );
  }

  Future<void> deleteImage(String storagePath) {
    return _storage.deleteProductImage(storagePath);
  }

  Future<String> createSignedUrl(String storagePath) {
    return _storage.signProductImage(storagePath);
  }
}
