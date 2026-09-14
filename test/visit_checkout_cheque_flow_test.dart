import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/visits/application/visit_checkout_payment_rules.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';

void main() {
  group('VisitPaymentArrangement cheque flows', () {
    test('Cheque received opens Record cheque and creates a cheque record', () {
      const arrangement = VisitPaymentArrangement.chequeReceived;
      expect(VisitCheckoutPaymentRules.shouldOpenRecordCheque(arrangement), isTrue);
      expect(
        VisitCheckoutPaymentRules.shouldCreateChequeRecord(arrangement),
        isTrue,
      );
      expect(arrangement.allowsOptionalExpectedDate, isFalse);
    });

    test('Cheque later does not open Record cheque or create a cheque', () {
      const arrangement = VisitPaymentArrangement.chequeCollectionScheduled;
      expect(
        VisitCheckoutPaymentRules.shouldOpenRecordCheque(arrangement),
        isFalse,
      );
      expect(
        VisitCheckoutPaymentRules.shouldCreateChequeRecord(arrangement),
        isFalse,
      );
      expect(arrangement.allowsOptionalExpectedDate, isTrue);
    });

    test('Cheque later never requires an expected collection date', () {
      expect(
        VisitCheckoutPaymentRules.requiresExpectedCollectionDate(
          VisitPaymentArrangement.chequeCollectionScheduled,
        ),
        isFalse,
      );
    });

    test('Paid today / credit / arrange later do not open Record cheque', () {
      for (final arrangement in [
        VisitPaymentArrangement.paidToday,
        VisitPaymentArrangement.creditSale,
        VisitPaymentArrangement.noneYet,
      ]) {
        expect(
          VisitCheckoutPaymentRules.shouldOpenRecordCheque(arrangement),
          isFalse,
          reason: arrangement.label,
        );
        expect(
          VisitCheckoutPaymentRules.shouldCreateChequeRecord(arrangement),
          isFalse,
          reason: arrangement.label,
        );
      }
    });
  });

  group('VisitCheckoutPaymentRules notes and outcomes', () {
    test('Cheque later without date stores arrangement only', () {
      final lines = VisitCheckoutPaymentRules.arrangementNoteLines(
        arrangement: VisitPaymentArrangement.chequeCollectionScheduled,
      );
      expect(lines, ['Payment: Cheque later']);
    });

    test('Cheque later with optional date keeps it informational', () {
      final lines = VisitCheckoutPaymentRules.arrangementNoteLines(
        arrangement: VisitPaymentArrangement.chequeCollectionScheduled,
        expectedChequeDate: DateTime(2026, 9, 20),
        formatDate: (_) => '20 Sep 2026',
      );
      expect(lines, [
        'Payment: Cheque later',
        'Expected cheque around 20 Sep 2026',
      ]);
    });

    test('Cheque later without order is not follow-up-required', () {
      expect(
        VisitCheckoutPaymentRules.resolveOutcomeWithoutOrder(
          VisitPaymentArrangement.chequeCollectionScheduled,
        ),
        VisitOutcome.noOrderToday,
      );
    });

    test('Cheque received without order counts as payment collected', () {
      expect(
        VisitCheckoutPaymentRules.resolveOutcomeWithoutOrder(
          VisitPaymentArrangement.chequeReceived,
        ),
        VisitOutcome.paymentCollected,
      );
    });
  });
}
