/// Product gallery UI limit — prefer this over hardcoding `3`.
const int kMaxProductImages = MediaConstants.kMaxProductImages;

/// Product / entity media limits and processing targets.
abstract final class MediaConstants {
  /// UI limit for product gallery slots (architecture remains gallery-based).
  static const int kMaxProductImages = 3;

  /// Preferred display / crop ratio — portrait 4:5 (bottles, groceries, retail).
  static const double aspectRatio = 4 / 5;

  /// Longest edge after automatic resize (px).
  /// 1200 keeps catalog quality without expensive encode times.
  static const int maxDimension = 1200;

  /// JPEG encode quality (~80–85%).
  static const int jpegQuality = 82;

  /// Soft target size after compression (bytes).
  static const int targetMaxBytes = 400 * 1024;

  /// Absolute reject threshold before processing (matches storage bucket).
  static const int maxSourceBytes = 5 * 1024 * 1024;

  static const String productImagesBucket = 'product-images';
  static const String employeeAvatarsBucket = 'employee-avatars';
  static const String companyBrandingBucket = 'company-branding';
  static const String jpegContentType = 'image/jpeg';
  static const String jpegExtension = 'jpg';

  /// @Deprecated Prefer [jpegContentType] — pipeline uses JPEG for speed.
  static const String webpContentType = 'image/webp';
  static const String webpExtension = 'webp';
  static const int webpQuality = jpegQuality;
  static const int targetMinBytes = 250 * 1024;
}
