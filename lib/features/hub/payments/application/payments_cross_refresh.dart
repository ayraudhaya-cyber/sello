import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/hub/payments/application/hub_payments_provider.dart';

/// Reloads Hub Payments when that screen is already open.
Future<void> refreshHubPaymentsQuietly(Ref ref) async {
  if (!ref.exists(hubPaymentsProvider)) return;
  try {
    await ref
        .read(hubPaymentsProvider.notifier)
        .loadPayments(showLoading: false);
  } catch (_) {
    // Payments can still be refreshed manually.
  }
}
