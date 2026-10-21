import 'package:sello/features/payments/application/order_collection_association.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
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
    num discount = 0,
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
    final cash = amount ?? 0;
    if (cash <= 0.001 && discount > 0.001) {
      if (discount > ceiling + 0.001) {
        return 'Discount is more than the outstanding balance.';
      }
      return null;
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

  /// How much of [available] can be applied to this collection.
  static num walletCap({required num available, required num outstanding}) {
    final wallet = available < 0 ? 0 : available;
    final due = outstanding < 0 ? 0 : outstanding;
    return wallet < due ? wallet : due;
  }

  /// Wallet sits beside the cash, card, bank, or cheque amount.
  /// Either part may be zero. Together they cannot pass [outstanding].
  static String? validateWithWallet({
    required num walletApplied,
    required num walletAvailable,
    required num? received,
    required num outstanding,
    num discount = 0,
  }) {
    if (walletApplied < -0.001) {
      return 'Wallet amount cannot be negative.';
    }
    if (walletApplied > walletAvailable + 0.001) {
      return 'Wallet balance is not enough for that amount.';
    }
    if (walletApplied > outstanding + 0.001) {
      return 'Wallet amount is more than the remaining balance.';
    }
    final cash = received ?? 0;
    if (cash < -0.001) {
      return 'Enter an amount greater than zero.';
    }
    if (discount < -0.001) {
      return 'Discount cannot be negative.';
    }
    if (walletApplied <= 0.001 && cash <= 0.001 && discount <= 0.001) {
      return 'Enter an amount greater than zero.';
    }
    if (walletApplied + cash + discount > outstanding + 0.001) {
      return discount > 0.001
          ? 'Wallet, amount received, and discount are more than the remaining balance.'
          : 'Wallet and the amount received are more than the remaining balance.';
    }
    return null;
  }

  /// Optional write-off on a cash/card/bank/wallet collection.
  static String? validateDiscount({
    required num discount,
    required num moneyReceived,
    required num outstanding,
    required bool allowed,
  }) {
    if (discount <= 0.001) return null;
    if (!allowed) {
      return 'Sales reps cannot add a discount on collections for this company.';
    }
    if (discount > outstanding + 0.001) {
      return 'Discount is more than the outstanding balance.';
    }
    if (moneyReceived + discount > outstanding + 0.001) {
      return 'Amount received and discount are more than the outstanding balance.';
    }
    return null;
  }
}
