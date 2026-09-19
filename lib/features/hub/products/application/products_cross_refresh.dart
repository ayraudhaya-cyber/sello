import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/products/application/hub_products_provider.dart';

/// Quietly reloads Hub Products after inventory/order stock mutations.
///
/// Products keeps an in-memory catalog snapshot for the shell session; without
/// this, Inventory adjusts and completed sales leave list/details stock stale
/// until the user hits Refresh.
Future<void> refreshHubProductsQuietly(Ref ref) async {
  try {
    await ref
        .read(hubProductsProvider.notifier)
        .loadProducts(showLoading: false);
  } catch (_) {
    // Non-fatal — Products can still be refreshed manually.
  }
}
