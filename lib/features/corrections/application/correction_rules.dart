import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_record_status.dart';

/// Lifecycle-aware safe-correction rules. Enforcement is server-side.
abstract final class OrderCorrectionRules {
  /// Reporting ownership. Not allowed on cancelled / archived orders.
  static bool canChangeSalesRep(OrderStatus status) {
    return status != OrderStatus.cancelled;
  }

  /// Issued invoices can be corrected in place. Drafts use the draft editor.
  static bool canCorrectInvoice(OrderStatus status) {
    return status == OrderStatus.placed ||
        status == OrderStatus.partiallyDelivered ||
        status == OrderStatus.completed;
  }

  /// Customer change is safe only when nothing has been collected.
  static bool canChangeCustomer({
    required OrderStatus status,
    required bool hasCollections,
  }) {
    if (hasCollections || status == OrderStatus.cancelled) return false;
    return status == OrderStatus.draft || canCorrectInvoice(status);
  }

  static String customerBlockedMessage({
    required OrderStatus status,
    required bool hasCollections,
  }) {
    if (status == OrderStatus.cancelled) {
      return 'Cancelled invoices cannot be corrected.';
    }
    if (hasCollections) {
      return 'This invoice already has a collection. '
          'Correct or cancel that payment before changing the customer.';
    }
    return 'This invoice cannot change customer.';
  }

  /// Commercial lines can be corrected until the invoice is cancelled.
  static bool canEditLines(OrderStatus status) {
    return status == OrderStatus.draft || canCorrectInvoice(status);
  }
}

abstract final class PaymentCorrectionRules {
  static bool canCorrect(PaymentRecordStatus status) {
    return status == PaymentRecordStatus.completed ||
        status == PaymentRecordStatus.pending;
  }

  static String explanation(PaymentRecordStatus status) {
    if (status == PaymentRecordStatus.pending) {
      return 'This collection is still waiting for review, so Sello will '
          'cancel it and record the corrected collection.';
    }
    return 'This payment has already been applied to the customer\'s balance. '
        'To correct it, Sello will reverse the original payment and create '
        'the corrected payment.';
  }
}

abstract final class ChequeCorrectionRules {
  static bool canEditDetails({
    required ChequeStatus status,
    required bool isHubFinancialRole,
    required bool isOwnCheque,
  }) {
    if (status == ChequeStatus.cancelled || status == ChequeStatus.bounced) {
      return false;
    }
    if (isHubFinancialRole) return true;
    return isOwnCheque && status == ChequeStatus.awaitingCollection;
  }
}

abstract final class OpeningBalanceCorrectionRules {
  static bool canCorrect({required num remaining, required num amount}) {
    return remaining + 0.001 >= amount && amount > 0;
  }
}
