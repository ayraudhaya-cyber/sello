import 'package:sello/shared/models/payment_summary.dart';

/// Chronological FIFO for mixed order + opening-balance receivables.
///
/// Existing Sello convention is oldest-first by [ReceivableOrder.orderedAt]
/// (orders are fetched `order('ordered_at')` ascending). Opening-balance
/// adjustments use the same list and the same date field, populated from
/// `recognized_at`.
///
/// Order-only customers keep identical allocation order.
/// When both exist, money hits the older date first — typically the
/// historical opening balance, then Sello invoices. Same-instant ties
/// put opening balance before an order so old debt is not skipped.
List<ReceivableOrder> sortReceivablesFifo(Iterable<ReceivableOrder> items) {
  final copy = [...items];
  copy.sort((a, b) {
    final byDate = a.orderedAt.compareTo(b.orderedAt);
    if (byDate != 0) return byDate;
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    return a.orderNumber.compareTo(b.orderNumber);
  });
  return copy;
}

PaymentAllocationInput allocationInputForReceivable(
  ReceivableOrder receivable,
  num amount,
) {
  return PaymentAllocationInput.fromReceivable(receivable, amount);
}
