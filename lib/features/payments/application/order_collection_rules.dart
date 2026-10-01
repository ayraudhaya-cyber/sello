import 'package:sello/features/payments/application/order_collection_association.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';

export 'package:sello/features/payments/application/order_collection_association.dart';

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

  /// Hides Record collection when remaining is already covered, including
  /// pending-approval allocations reserved against this order.
  static bool canOfferRecordCollection({
    required OrderStatus status,
    required PaymentStatus paymentStatus,
    required num total,
    required num outstanding,
  }) {
    return OrderCollectionAssociation.canOfferRecordCollection(
      status: status,
      paymentStatus: paymentStatus,
      total: total,
      outstanding: outstanding,
    );
  }

  /// Cash, card, and bank settle through [receive_payment].
  /// Cheque is recorded on the same order through the cheque ledger.
  static const methods = OrderCollectionAssociation.supportedMethods;

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

  static String? validateNewCollection({
    required PaymentMethod method,
    required num? amount,
    required num remaining,
    AssociatedChequeMatch? match,
  }) {
    if (OrderCollectionAssociation.shouldUseExistingCheque(
      method: method,
      match: match,
    )) {
      return null;
    }
    final ceiling = OrderCollectionAssociation.newCollectionCeiling(
      remaining: remaining,
      method: method,
      match: match,
    );
    if (ceiling <= 0.001 && match != null && match.usesExisting) {
      return match.action == AssociatedChequeAction.collectExisting
          ? 'Collect the existing cheque instead of recording another collection.'
          : 'Apply the existing cheque instead of recording another collection.';
    }
    return validateAmount(amount: amount, outstanding: ceiling);
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
