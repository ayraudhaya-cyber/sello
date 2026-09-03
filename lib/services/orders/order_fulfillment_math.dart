/// Pure helpers for order line fulfillment math (ordered / delivered / cancelled).
abstract final class OrderFulfillmentMath {
  static num remaining({
    required num ordered,
    required num delivered,
    required num cancelled,
  }) {
    final value = ordered - delivered - cancelled;
    return value < 0 ? 0 : value;
  }

  static bool isFullyClosed({
    required num ordered,
    required num delivered,
    required num cancelled,
  }) {
    return remaining(
          ordered: ordered,
          delivered: delivered,
          cancelled: cancelled,
        ) <=
        0;
  }

  /// Quantity that can still be delivered or cancelled.
  static num? acceptFulfillmentQuantity({
    required num requested,
    required num remaining,
  }) {
    if (requested <= 0) return null;
    if (requested > remaining) return null;
    return requested;
  }
}
