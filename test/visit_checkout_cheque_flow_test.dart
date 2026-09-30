import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/visits/application/visit_checkout_payment_rules.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';

void main() {
  group('VisitPaymentArrangement cheque flows', () {
    test('Cheque received offers Record cheque but does not create one until saved', () {
      const arrangement = VisitPaymentArrangement.chequeReceived;
      expect(VisitCheckoutPaymentRules.shouldOpenRecordCheque(arrangement), isTrue);
      expect(
        VisitCheckoutPaymentRules.shouldCreateChequeRecord(
          arrangement: arrangement,
          recordChequeSubmitted: false,
        ),
        isFalse,
      );
      expect(
        VisitCheckoutPaymentRules.shouldCreateChequeRecord(
          arrangement: arrangement,
          recordChequeSubmitted: true,
        ),
        isTrue,
      );
      expect(arrangement.allowsOptionalExpectedDate, isFalse);
    });

    test('Skipping Record cheque does not create a ledger row', () {
      expect(
        VisitCheckoutPaymentRules.shouldCreateChequeRecord(
          arrangement: VisitPaymentArrangement.chequeReceived,
          recordChequeSubmitted: false,
        ),
        isFalse,
      );
    });

    test('Cheque later does not open Record cheque or create a cheque', () {
      const arrangement = VisitPaymentArrangement.chequeCollectionScheduled;
      expect(
        VisitCheckoutPaymentRules.shouldOpenRecordCheque(arrangement),
        isFalse,
      );
      expect(
        VisitCheckoutPaymentRules.shouldCreateChequeRecord(
          arrangement: arrangement,
          recordChequeSubmitted: true,
        ),
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
          VisitCheckoutPaymentRules.shouldCreateChequeRecord(
            arrangement: arrangement,
            recordChequeSubmitted: true,
          ),
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

  group('Visit cheque preferred order', () {
    test('cheque received passes the newly created order into the cheque flow', () {
      expect(
        VisitCheckoutPaymentRules.preferredOrderIdForCheque(
          arrangement: VisitPaymentArrangement.chequeReceived,
          createdOrderId: 'ord-today',
        ),
        'ord-today',
      );
    });

    test('cheque later does not pin an order', () {
      expect(
        VisitCheckoutPaymentRules.preferredOrderIdForCheque(
          arrangement: VisitPaymentArrangement.chequeCollectionScheduled,
          createdOrderId: 'ord-today',
        ),
        isNull,
      );
    });

    test('cheque received without a created order has no preferred id', () {
      expect(
        VisitCheckoutPaymentRules.preferredOrderIdForCheque(
          arrangement: VisitPaymentArrangement.chequeReceived,
          createdOrderId: null,
        ),
        isNull,
      );
    });
  });
}
