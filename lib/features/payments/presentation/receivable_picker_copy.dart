import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Copy for the shared receive-payment / cheque allocation picker.
abstract final class ReceivablePickerCopy {
  static List<String> subtitleLines(
    ReceivableOrder order, {
    required String currencySymbol,
  }) {
    final due =
        'Due ${SelloFormatters.currency(order.remaining, symbol: currencySymbol)}';
    if (!order.isOpeningBalance) {
      return ['$due · ${SelloFormatters.date(order.orderedAt)}'];
    }
    final reference = order.referenceNumber?.trim();
    return [
      order.orderNumber,
      due,
      if (reference != null && reference.isNotEmpty)
        'Old invoice / reference: $reference',
    ];
  }
}
