import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';

/// Quietly reloads Hub Inventory after product/order stock mutations.
///
/// Avoids a blocking spinner; Inventory tab picks up valuation without a
/// manual refresh. Safe when the Inventory provider was never opened yet.
Future<void> refreshHubInventoryQuietly(Ref ref) async {
  try {
    await ref
        .read(hubInventoryProvider.notifier)
        .loadStock(resetPage: true, showLoading: false);
  } catch (_) {
    // Non-fatal — Inventory can still be refreshed manually.
  }
}
