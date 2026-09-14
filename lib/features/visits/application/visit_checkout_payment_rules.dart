import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';

/// Pure visit-checkout rules for payment arrangements (testable).
abstract final class VisitCheckoutPaymentRules {
  /// Whether submit should open Record cheque before finishing the visit.
  static bool shouldOpenRecordCheque(VisitPaymentArrangement arrangement) =>
      arrangement.opensRecordCheque;

  /// Whether submit may create a cheque / payment ledger entry for this choice.
  static bool shouldCreateChequeRecord(VisitPaymentArrangement arrangement) =>
      arrangement.opensRecordCheque;

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
