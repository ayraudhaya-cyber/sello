import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_record_status.dart';

/// Lifecycle-aware safe-correction rules. Enforcement is server-side.
abstract final class OrderCorrectionRules {
  /// Reporting ownership. Not allowed on cancelled / archived orders.
  static bool canChangeSalesRep(OrderStatus status) {
    return status != OrderStatus.cancelled;
  }

  /// Customer change is only safe on a draft with no collections.
  static bool canChangeCustomer({
    required OrderStatus status,
    required bool hasCollections,
  }) {
    return status == OrderStatus.draft && !hasCollections;
  }

  static String customerBlockedMessage(OrderStatus status) {
    if (status == OrderStatus.draft) {
      return 'This draft already has a collection against it. '
          'Correct or cancel that payment first, then change the customer.';
    }
    return 'The customer can only be changed while this order is still a draft. '
        'After it is placed or delivered, changing customer would mix up '
        'outstanding balances. Cancel this order and create a new one for the '
        'correct customer.';
  }

  /// Line quantity / product / price stay on the draft editor.
  static bool canEditLines(OrderStatus status) {
    return status == OrderStatus.draft;
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
