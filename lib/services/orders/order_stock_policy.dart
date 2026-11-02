import 'package:sello/shared/utils/formatters.dart';

/// Client-side order quantity limits against known available stock.
abstract final class OrderStockPolicy {
  /// Correction cap. [heldQuantity] is the undelivered amount already reserved
  /// for this saved line. [availableStock] is free stock after that hold.
  static num? maxCorrectedOrderQuantity({
    required bool allowOrdersAboveAvailableStock,
    required num? availableStock,
    required num deliveredQuantity,
    required num heldQuantity,
  }) {
    final extra = maxOrderQuantity(
      allowOrdersAboveAvailableStock: allowOrdersAboveAvailableStock,
      availableStock: availableStock,
    );
    if (extra == null) return null;
    final delivered = deliveredQuantity < 0 ? 0 : deliveredQuantity;
    final held = heldQuantity < 0 ? 0 : heldQuantity;
    return delivered + held + extra;
  }

  /// Returns null when no client-side cap applies.
  static num? maxOrderQuantity({
    required bool allowOrdersAboveAvailableStock,
    required num? availableStock,
  }) {
    if (allowOrdersAboveAvailableStock) return null;
    if (availableStock == null) return null;
    return availableStock < 0 ? 0 : availableStock;
  }

  /// Rejects quantities above [max]; returns null when [requested] is not allowed.
  static num? acceptQuantity({
    required num requested,
    required num? max,
  }) {
    if (requested < 0) return null;
    if (max != null && requested > max) return null;
    return requested;
  }

  static bool canIncrease({
    required num current,
    required num? max,
  }) {
    if (max == null) return true;
    return current < max;
  }

  static String onlyAvailableMessage(num available) {
    if (available <= 0) return 'Out of stock';
    return 'Only ${SelloFormatters.quantity(available)} available';
  }
}
