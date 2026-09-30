import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';

/// Quietly reloads Hub Inventory after product/order stock mutations.
///
/// Skips the reload when Inventory has not been opened this session, so a
/// product or order save does not start that query in the background.
Future<void> refreshHubInventoryQuietly(Ref ref) async {
  if (!ref.exists(hubInventoryProvider)) return;
  try {
    await ref
        .read(hubInventoryProvider.notifier)
        .loadStock(resetPage: true, showLoading: false);
  } catch (_) {
    // Non-fatal — Inventory can still be refreshed manually.
  }
}
