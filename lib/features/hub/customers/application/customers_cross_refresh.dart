import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/customers/application/hub_customers_provider.dart';

/// Reloads Hub Customers when that screen is already open.
Future<void> refreshHubCustomersQuietly(Ref ref) async {
  if (!ref.exists(hubCustomersProvider)) return;
  try {
    await ref
        .read(hubCustomersProvider.notifier)
        .loadCustomers(showLoading: false);
  } catch (_) {
    // Customers can still be refreshed manually.
  }
}
