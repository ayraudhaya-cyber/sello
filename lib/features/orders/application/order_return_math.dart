import 'package:sello/shared/models/order_summary.dart';

/// Preview of a return before the server records it.
///
/// The database applies the same split. Unpaid value comes off what the
/// customer owes. The rest was already paid.
class OrderReturnQuote {
  const OrderReturnQuote({
    required this.returnValue,
    required this.owedReduction,
    required this.paidPortion,
    this.itemDiscount = 0,
    this.invoiceDiscount = 0,
  });

  final num returnValue;
  final num owedReduction;
  final num paidPortion;

  /// Item discounts already inside the returned line totals.
  final num itemDiscount;

  /// Share of the invoice discount that follows these units.
  final num invoiceDiscount;

  bool get hasPaidPortion => paidPortion > 0.001;

  static num money(num value) => (value * 100).round() / 100;

  static num lineShare(OrderLineItem line, num quantity) {
    if (quantity <= 0 || line.quantity <= 0) return 0;
    return line.lineTotal * quantity / line.quantity;
  }

  /// Price minus the line total, for the units being returned.
  static num itemDiscountFor(OrderLineItem line, num quantity) {
    if (quantity <= 0 || line.quantity <= 0) return 0;
    final saved = line.unitPrice * quantity - lineShare(line, quantity);
    return saved > 0.001 ? money(saved) : 0;
  }

  /// Invoice discount allocated in the same proportion as the return value.
  static num invoiceShare({
    required num orderSubtotal,
    required num orderDiscount,
    required num lineShareSum,
  }) {
    if (orderSubtotal <= 0 || orderDiscount <= 0 || lineShareSum <= 0) {
      return 0;
    }
    return money(orderDiscount * lineShareSum / orderSubtotal);
  }

  static OrderReturnQuote quote({
    required num orderSubtotal,
    required num orderTotal,
    required num lineShareSum,
    required num stillOwed,
    num itemDiscount = 0,
    num invoiceDiscount = 0,
  }) {
    if (orderSubtotal <= 0 || orderTotal <= 0 || lineShareSum <= 0) {
      return OrderReturnQuote(
        returnValue: 0,
        owedReduction: 0,
        paidPortion: 0,
        itemDiscount: itemDiscount,
        invoiceDiscount: invoiceDiscount,
      );
    }
    final value = money(orderTotal * lineShareSum / orderSubtotal);
    final owed = value < stillOwed ? value : stillOwed;
    final paid = money(value - owed);
    return OrderReturnQuote(
      returnValue: value,
      owedReduction: money(value - paid),
      paidPortion: paid,
      itemDiscount: itemDiscount,
      invoiceDiscount: invoiceDiscount,
    );
  }
}
