import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';

/// Pure visit-checkout rules for payment arrangements (testable).
abstract final class VisitCheckoutPaymentRules {
  /// Whether submit should offer Record cheque after the order is saved.
  /// The dialog is skippable; dismissing it does not undo the order.
  static bool shouldOpenRecordCheque(VisitPaymentArrangement arrangement) =>
      arrangement.opensRecordCheque;

  /// Order just created on this visit — prefer it when recording a cheque.
  static String? preferredOrderIdForCheque({
    required VisitPaymentArrangement arrangement,
    required String? createdOrderId,
  }) {
    if (!arrangement.opensRecordCheque) return null;
    final id = createdOrderId?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// A cheque ledger row is created only after Record cheque is saved.
  /// Selecting “Cheque received” never inserts an empty or incomplete cheque.
  static bool shouldCreateChequeRecord({
    required VisitPaymentArrangement arrangement,
    required bool recordChequeSubmitted,
  }) =>
      arrangement.opensRecordCheque && recordChequeSubmitted;

  /// Cheque later never requires an expected date.
  static bool requiresExpectedCollectionDate(
    VisitPaymentArrangement arrangement,
  ) =>
      false;

  /// Outcome when there is no order line list to save.
  static VisitOutcome resolveOutcomeWithoutOrder(
    VisitPaymentArrangement arrangement,
  ) {
    if (arrangement == VisitPaymentArrangement.paidToday ||
        arrangement == VisitPaymentArrangement.chequeReceived) {
      return VisitOutcome.paymentCollected;
    }
    return VisitOutcome.noOrderToday;
  }

  /// Visit note lines for the chosen arrangement (no fake deadlines).
  static List<String> arrangementNoteLines({
    required VisitPaymentArrangement arrangement,
    DateTime? expectedChequeDate,
    String Function(DateTime date)? formatDate,
  }) {
    if (arrangement == VisitPaymentArrangement.noneYet) return const [];
    final lines = <String>['Payment: ${arrangement.label}'];
    if (arrangement.allowsOptionalExpectedDate && expectedChequeDate != null) {
      final formatted = formatDate?.call(expectedChequeDate) ??
          expectedChequeDate.toIso8601String().split('T').first;
      lines.add('Expected cheque around $formatted');
    }
    return lines;
  }
}
