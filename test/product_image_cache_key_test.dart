import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/utils/product_image_cache_key.dart';

void main() {
  test('cache key follows the storage path and photo timestamp', () {
    final first = DateTime.utc(2026, 1, 1);
    final replaced = DateTime.utc(2026, 2, 1);

    expect(ProductImageCacheKey.of(null, first), isNull);
    expect(ProductImageCacheKey.of('  ', first), isNull);

    final kept = ProductImageCacheKey.of('co/p/primary.webp', first);
    final next = ProductImageCacheKey.of('co/p/primary.webp', replaced);
    expect(kept, 'product:co/p/primary.webp@${first.millisecondsSinceEpoch}');
    expect(kept, isNot(next));
  });
}
