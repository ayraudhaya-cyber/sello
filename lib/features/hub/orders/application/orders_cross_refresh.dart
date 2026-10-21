import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/orders/application/hub_orders_provider.dart';

/// Reloads Hub Orders when that screen is already open.
Future<void> refreshHubOrdersQuietly(Ref ref) async {
  if (!ref.exists(hubOrdersProvider)) return;
  try {
    await ref.read(hubOrdersProvider.notifier).loadOrders(showLoading: false);
  } catch (_) {
    // Orders can still be refreshed manually.
  }
}
