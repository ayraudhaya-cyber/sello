import 'package:sello/core/constants/media_constants.dart';

/// Storage object names for a product gallery slot.
abstract final class ProductMediaPaths {
  static String objectName(int slotIndex, {String extension = 'webp'}) {
    assert(slotIndex >= 0 && slotIndex < MediaConstants.kMaxProductImages);
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    if (slotIndex == 0) return 'primary.$ext';
    return 'image-${slotIndex + 1}.$ext';
  }

  static String buildPath({
    required String companyId,
    required String productId,
    required int slotIndex,
    String extension = 'webp',
  }) {
    return '$companyId/$productId/${objectName(slotIndex, extension: extension)}';
  }
}
