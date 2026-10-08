/// Disk-cache identity for a product photo.
///
/// Signed image links change about every hour. The storage path stays put,
/// and [updatedAt] moves only when that photo is replaced, so the phone can
/// reuse the file across app launches without keeping a stale picture.
abstract final class ProductImageCacheKey {
  static String? of(String? storagePath, DateTime? updatedAt) {
    final path = storagePath?.trim();
    if (path == null || path.isEmpty) return null;
    final version = updatedAt?.toUtc().millisecondsSinceEpoch;
    if (version == null) return 'product:$path';
    return 'product:$path@$version';
  }
}
