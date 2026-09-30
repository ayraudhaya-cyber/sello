import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';

/// Rules for collecting against an existing order. No new sale is created.
abstract final class OrderCollectionRules {
  static bool canCollect({
    required OrderStatus status,
    required PaymentStatus paymentStatus,
    required num total,
  }) {
    if (total <= 0) return false;
    if (status == OrderStatus.draft || status == OrderStatus.cancelled) {
      return false;
    }
    return paymentStatus == PaymentStatus.unpaid ||
        paymentStatus == PaymentStatus.partial;
  }

  /// Cash, card, and bank settle through [receive_payment].
  /// Cheque is recorded on the same order through the cheque ledger.
  static const methods = <PaymentMethod>[
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.bankTransfer,
    PaymentMethod.cheque,
  ];

  static String? validateAmount({
    required num? amount,
    required num outstanding,
  }) {
    if (amount == null || amount <= 0) {
      return 'Enter an amount greater than zero.';
    }
    if (amount > outstanding + 0.001) {
      return 'Amount is more than the outstanding balance.';
    }
    return null;
  }

  static String? validateCheque({
    required String bankName,
    required String chequeNumber,
    required String holderName,
  }) {
    if (bankName.trim().isEmpty) return 'Bank name is required.';
    if (chequeNumber.trim().isEmpty) return 'Cheque number is required.';
    if (holderName.trim().isEmpty) return 'Name on the cheque is required.';
    return null;
  }
}
