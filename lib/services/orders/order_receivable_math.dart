/// AR recognition math: outstanding receivable follows delivered unpaid value.
///
/// Matches `order_delivered_financial_value` / `apply_order_fulfillment_receivable`.
abstract final class OrderReceivableMath {
  static num roundMoney(num value) => (value * 100).round() / 100;

  /// Line share of [lineTotal] for units actually delivered. Cancelled qty is ignored.
  static num deliveredLineValue({
    required num lineTotal,
    required num ordered,
    required num delivered,
  }) {
    if (ordered <= 0 || delivered <= 0 || lineTotal <= 0) return 0;
    final qty = delivered > ordered ? ordered : delivered;
    return lineTotal * qty / ordered;
  }

  /// Order [total] (after header discount / tax) allocated to delivered quantity.
  static num deliveredOrderValue({
    required num orderTotal,
    required num subtotal,
    required Iterable<({num lineTotal, num ordered, num delivered})> lines,
  }) {
    if (orderTotal <= 0 || subtotal <= 0) return 0;
    final deliveredLines = lines.fold<num>(
      0,
      (sum, line) =>
          sum +
          deliveredLineValue(
            lineTotal: line.lineTotal,
            ordered: line.ordered,
            delivered: line.delivered,
          ),
    );
    if (deliveredLines <= 0) return 0;
    return roundMoney(orderTotal * deliveredLines / subtotal);
  }

  /// Unpaid delivered value. Prepayments above delivered value do not create negative AR.
  static num arExposure({
    required num deliveredValue,
    required num allocatedPayments,
  }) {
    final unpaid = deliveredValue - allocatedPayments;
    return unpaid < 0 ? 0 : roundMoney(unpaid);
  }

  /// Incremental AR to post when delivered value moves from [recognizedValue] to [deliveredAfter].
  static num arDelta({
    required num recognizedValue,
    required num deliveredAfter,
    required num allocatedPayments,
  }) {
    return roundMoney(
      arExposure(
            deliveredValue: deliveredAfter,
            allocatedPayments: allocatedPayments,
          ) -
          arExposure(
            deliveredValue: recognizedValue,
            allocatedPayments: allocatedPayments,
          ),
    );
  }
}
