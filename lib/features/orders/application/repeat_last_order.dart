import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';

/// Picks the customer's most recent real sale to repeat.
///
/// Drafts are still open and cancelled orders are not a sale to copy.
/// Placed, partially delivered, and completed orders are the existing
/// sales history.
abstract final class RepeatLastOrder {
  static const repeatableStatuses = <OrderStatus>[
    OrderStatus.placed,
    OrderStatus.partiallyDelivered,
    OrderStatus.completed,
  ];

  static bool isRepeatable(OrderStatus status) =>
      repeatableStatuses.contains(status);

  /// Most recently ordered eligible sale for [customerId], ignoring other
  /// customers and an order currently being edited.
  static OrderSummary? mostRecent({
    required String? customerId,
    required Iterable<OrderSummary> orders,
    String? excludeOrderId,
  }) {
    final id = customerId?.trim() ?? '';
    if (id.isEmpty) return null;

    OrderSummary? best;
    for (final order in orders) {
      if (order.customerId != id) continue;
      if (excludeOrderId != null && order.id == excludeOrderId) continue;
      if (!isRepeatable(order.status)) continue;
      if (best == null || order.orderedAt.isAfter(best.orderedAt)) {
        best = order;
      }
    }
    return best;
  }
}
