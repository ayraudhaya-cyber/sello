import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/payments/application/order_collection_rules.dart';
import 'package:sello/shared/models/cheque_source.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

ChequeSummary _cheque({
  String id = 'ch-1',
  num amount = 100000,
  ChequeStatus status = ChequeStatus.collected,
  ChequeSource source = ChequeSource.sello,
  String? visitId,
  String? notes,
  String? paymentId,
}) {
  return ChequeSummary(
    id: id,
    companyId: 'co',
    customerId: 'cu',
    employeeId: 'em',
    chequeNumberLabel: 'CH-1',
    amount: amount,
    bankName: 'Commercial',
    chequeNumber: '1001',
    holderName: 'ABC',
    chequeDate: DateTime(2026, 1, 1),
    status: status,
    createdAt: DateTime(2026, 1, 1),
    visitId: visitId,
    notes: notes,
    paymentId: paymentId,
    source: source,
  );
}

OrderCollectionEntry _entry({
  required num amount,
  required PaymentMethod method,
  PaymentRecordStatus status = PaymentRecordStatus.completed,
  String paymentId = 'pay-1',
}) {
  return OrderCollectionEntry(
    paymentId: paymentId,
    paymentNumber: 'PAY-1',
    amount: amount,
    method: method,
    status: status,
    receivedAt: DateTime(2026, 1, 2),
  );
}

void main() {
  const orderId = 'ord-today';
  const orderNumber = 'SO-1001';
  const visitId = 'visit-1';

  group('Record collection availability', () {
    test('1. fully paid order cannot record another collection', () {
      const balance = OrderCollectionBalance(entries: [], amountPaid: 100000);
      expect(balance.outstandingFor(100000), 0);
      expect(
        OrderCollectionRules.canOfferRecordCollection(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.paid,
          total: 100000,
          outstanding: 0,
        ),
        isFalse,
      );
    });

    test('2. partial order offers Record collection for the remainder', () {
      const balance = OrderCollectionBalance(entries: [], amountPaid: 40000);
      expect(balance.outstandingFor(100000), 60000);
      expect(
        OrderCollectionRules.canOfferRecordCollection(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.partial,
          total: 100000,
          outstanding: 60000,
        ),
        isTrue,
      );
      expect(
        OrderCollectionRules.validateAmount(amount: 60000, outstanding: 60000),
        isNull,
      );
    });
  });

  group('Mixed methods on later collections', () {
    test('3. previous collection was Cheque — next collection can be Cash', () {
      expect(
        OrderCollectionAssociation.allowsDifferentMethodFromPrior(
          PaymentMethod.cash,
        ),
        isTrue,
      );
      expect(
        OrderCollectionAssociation.methodForNewCollection(
          priorCollectionMethod: PaymentMethod.cheque,
        ),
        PaymentMethod.cash,
      );
      expect(
        OrderCollectionAssociation.shouldCreateNewCheque(
          method: PaymentMethod.cash,
          match: null,
        ),
        isFalse,
      );
    });

    test('4. previous collection was Cash — next collection can be Cheque', () {
      expect(
        OrderCollectionAssociation.allowsDifferentMethodFromPrior(
          PaymentMethod.cheque,
        ),
        isTrue,
      );
      expect(
        OrderCollectionAssociation.methodForNewCollection(
          priorCollectionMethod: PaymentMethod.cash,
        ),
        isNot(PaymentMethod.cheque),
      );
      expect(
        OrderCollectionAssociation.shouldCreateNewCheque(
          method: PaymentMethod.cheque,
          match: null,
        ),
        isTrue,
      );
    });
  });

  group('Existing cheque covering this order', () {
    test('5. cheque fully allocated to the order — no second collection', () {
      const balance = OrderCollectionBalance(entries: [], amountPaid: 100000);
      final remaining = balance.outstandingFor(100000);
      final match = OrderCollectionAssociation.findAssociatedCheque(
        cheques: [
          _cheque(visitId: visitId, paymentId: 'pay-ch', amount: 100000),
        ],
        orderId: orderId,
        orderNumber: orderNumber,
        orderVisitId: visitId,
        orderRemaining: remaining,
        allocationsByPaymentId: {
          'pay-ch': [
            const PaymentAllocation(id: 'a1', amount: 100000, orderId: orderId),
          ],
        },
      );
      expect(remaining, 0);
      expect(match, isNull);
      expect(
        OrderCollectionRules.canOfferRecordCollection(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.paid,
          total: 100000,
          outstanding: remaining,
        ),
        isFalse,
      );
    });

    test(
      '6. associated cheque not allocated — apply existing, do not create another',
      () {
        final cheque = _cheque(
          visitId: visitId,
          paymentId: 'pay-ch',
          amount: 100000,
        );
        final match = OrderCollectionAssociation.findAssociatedCheque(
          cheques: [cheque],
          orderId: orderId,
          orderNumber: orderNumber,
          orderVisitId: visitId,
          orderRemaining: 100000,
          allocationsByPaymentId: const {'pay-ch': []},
        );
        expect(match, isNotNull);
        expect(match!.action, AssociatedChequeAction.applyExisting);
        expect(
          OrderCollectionAssociation.shouldCreateNewCheque(
            method: PaymentMethod.cheque,
            match: match,
          ),
          isFalse,
        );
        expect(
          OrderCollectionAssociation.existingChequeActionLabel(match.action),
          'Apply existing cheque',
        );
      },
    );

    test('7. awaiting cheque associated with the order — collect existing', () {
      final cheque = _cheque(
        visitId: visitId,
        status: ChequeStatus.awaitingCollection,
        amount: 31640,
      );
      final match = OrderCollectionAssociation.findAssociatedCheque(
        cheques: [cheque],
        orderId: orderId,
        orderNumber: orderNumber,
        orderVisitId: visitId,
        orderRemaining: 31640,
      );
      expect(match, isNotNull);
      expect(match!.action, AssociatedChequeAction.collectExisting);
      expect(
        OrderCollectionAssociation.shouldCreateNewCheque(
          method: PaymentMethod.cheque,
          match: match,
        ),
        isFalse,
      );
      expect(
        OrderCollectionAssociation.existingChequeActionLabel(match.action),
        'Mark cheque as received',
      );
    });
  });

  group('Checkout arrangement is not money', () {
    test(
      '8. Cheque received skipped Record cheque — Record collection stays available',
      () {
        expect(
          OrderCollectionRules.canOfferRecordCollection(
            status: OrderStatus.completed,
            paymentStatus: PaymentStatus.unpaid,
            total: 31640,
            outstanding: 31640,
          ),
          isTrue,
        );
        final match = OrderCollectionAssociation.findAssociatedCheque(
          cheques: const [],
          orderId: orderId,
          orderNumber: orderNumber,
          orderVisitId: visitId,
          orderRemaining: 31640,
        );
        expect(match, isNull);
        expect(
          OrderCollectionAssociation.shouldCreateNewCheque(
            method: PaymentMethod.cheque,
            match: null,
          ),
          isTrue,
        );
      },
    );

    test(
      '9. Cash/Card/Bank checkout with no payment — Record collection stays available',
      () {
        expect(
          OrderCollectionRules.canOfferRecordCollection(
            status: OrderStatus.completed,
            paymentStatus: PaymentStatus.unpaid,
            total: 50000,
            outstanding: 50000,
          ),
          isTrue,
        );
        expect(
          OrderCollectionAssociation.methodForNewCollection(
            orderPaymentMethod: PaymentMethod.cash,
          ),
          PaymentMethod.cash,
        );
        expect(
          OrderCollectionAssociation.methodForNewCollection(
            orderPaymentMethod: PaymentMethod.card,
          ),
          isNot(PaymentMethod.card),
        );
        expect(
          OrderCollectionAssociation.methodForNewCollection(
            orderPaymentMethod: PaymentMethod.bankTransfer,
          ),
          isNot(PaymentMethod.bankTransfer),
        );
        expect(
          OrderCollectionAssociation.methodForNewCollection(
            orderPaymentMethod: PaymentMethod.cheque,
          ),
          isNot(PaymentMethod.cheque),
        );
      },
    );
  });

  group('Do not guess unrelated instruments', () {
    test(
      '10. customer cheque with no visit/notes/allocation is not auto-applied',
      () {
        final match = OrderCollectionAssociation.findAssociatedCheque(
          cheques: [_cheque(paymentId: 'pay-other', amount: 80000)],
          orderId: orderId,
          orderNumber: orderNumber,
          orderVisitId: visitId,
          orderRemaining: 100000,
          allocationsByPaymentId: const {'pay-other': []},
        );
        expect(match, isNull);
        expect(
          OrderCollectionAssociation.shouldCreateNewCheque(
            method: PaymentMethod.cheque,
            match: null,
          ),
          isTrue,
        );
      },
    );

    test('11. opening-balance collection is not treated as this order', () {
      final openingCheque = _cheque(
        notes: 'Opening balance OB-12',
        paymentId: 'pay-ob',
        amount: 25000,
      );
      final match = OrderCollectionAssociation.findAssociatedCheque(
        cheques: [openingCheque],
        orderId: orderId,
        orderNumber: orderNumber,
        orderVisitId: visitId,
        orderRemaining: 100000,
        allocationsByPaymentId: {
          'pay-ob': [
            const PaymentAllocation(
              id: 'a-ob',
              amount: 25000,
              receivableAdjustmentId: 'adj-1',
            ),
          ],
        },
      );
      expect(match, isNull);
      expect(
        OrderCollectionRules.canOfferRecordCollection(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.unpaid,
          total: 100000,
          outstanding: 100000,
        ),
        isTrue,
      );
    });

    test(
      '12. pending approval covering the order blocks a duplicate collection',
      () {
        final balance = OrderCollectionBalance(
          entries: [
            _entry(
              amount: 31640,
              method: PaymentMethod.cheque,
              status: PaymentRecordStatus.pending,
            ),
          ],
          amountPaid: 0,
          amountPending: 31640,
        );
        expect(balance.outstandingFor(31640), 0);
        expect(
          OrderCollectionRules.canOfferRecordCollection(
            status: OrderStatus.completed,
            paymentStatus: PaymentStatus.unpaid,
            total: 31640,
            outstanding: balance.outstandingFor(31640),
          ),
          isFalse,
        );
      },
    );
  });

  group('Association details', () {
    test('notes mentioning the order number are a reliable link', () {
      final match = OrderCollectionAssociation.findAssociatedCheque(
        cheques: [
          _cheque(
            notes: 'Collected against SO-1001',
            paymentId: 'pay-ch',
            amount: 40000,
          ),
        ],
        orderId: orderId,
        orderNumber: orderNumber,
        orderRemaining: 100000,
        allocationsByPaymentId: const {'pay-ch': []},
      );
      expect(match?.action, AssociatedChequeAction.applyExisting);
    });

    test('tracking-only existing cheque is never treated as money', () {
      final match = OrderCollectionAssociation.findAssociatedCheque(
        cheques: [
          _cheque(
            visitId: visitId,
            source: ChequeSource.existing,
            status: ChequeStatus.awaitingCollection,
          ),
        ],
        orderId: orderId,
        orderNumber: orderNumber,
        orderVisitId: visitId,
        orderRemaining: 100000,
      );
      expect(match, isNull);
    });

    test('associated leftover is reserved from a new cash collection', () {
      final match = AssociatedChequeMatch(
        cheque: _cheque(visitId: visitId, paymentId: 'pay-ch', amount: 40000),
        action: AssociatedChequeAction.applyExisting,
        applicableAmount: 40000,
      );
      expect(
        OrderCollectionAssociation.newCollectionCeiling(
          remaining: 100000,
          method: PaymentMethod.cash,
          match: match,
        ),
        60000,
      );
      expect(
        OrderCollectionRules.validateNewCollection(
          method: PaymentMethod.cash,
          amount: 100000,
          remaining: 100000,
          match: match,
        ),
        isNotNull,
      );
      expect(
        OrderCollectionRules.validateNewCollection(
          method: PaymentMethod.cash,
          amount: 60000,
          remaining: 100000,
          match: match,
        ),
        isNull,
      );
    });

    test(
      'fully covering associated cheque blocks a second cash collection',
      () {
        final match = AssociatedChequeMatch(
          cheque: _cheque(visitId: visitId, paymentId: 'pay-ch'),
          action: AssociatedChequeAction.applyExisting,
          applicableAmount: 100000,
        );
        expect(
          OrderCollectionRules.validateNewCollection(
            method: PaymentMethod.cash,
            amount: 100000,
            remaining: 100000,
            match: match,
          ),
          contains('Apply the existing cheque'),
        );
      },
    );
  });
}
