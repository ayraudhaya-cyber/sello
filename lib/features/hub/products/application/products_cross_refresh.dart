import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/products/application/hub_products_provider.dart';

/// Quietly reloads Hub Products after inventory/order stock mutations.
///
/// Skips the reload when Products has not been opened this session. Once it
/// has, stock changes stay in sync without a manual refresh.
Future<void> refreshHubProductsQuietly(Ref ref) async {
  if (!ref.exists(hubProductsProvider)) return;
  try {
    await ref
        .read(hubProductsProvider.notifier)
        .loadProducts(showLoading: false);
  } catch (_) {
    // Non-fatal — Products can still be refreshed manually.
  }
}
