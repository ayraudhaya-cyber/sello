import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/payments/application/order_collection_rules.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';

void main() {
  group('OrderCollectionRules', () {
    test(
      'unpaid cheque-received orders can be collected later from the order',
      () {
        expect(
          OrderCollectionRules.canCollect(
            status: OrderStatus.completed,
            paymentStatus: PaymentStatus.unpaid,
            total: 50000,
          ),
          isTrue,
        );
        expect(OrderCollectionRules.methods, contains(PaymentMethod.cheque));
      },
    );

    test('credit and cheque-later orders can be collected once submitted', () {
      expect(
        OrderCollectionRules.canCollect(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.unpaid,
          total: 19716,
        ),
        isTrue,
      );
      expect(
        OrderCollectionRules.canCollect(
          status: OrderStatus.placed,
          paymentStatus: PaymentStatus.partial,
          total: 100000,
        ),
        isTrue,
      );
    });

    test('draft, cancelled, and paid orders are not collected again', () {
      expect(
        OrderCollectionRules.canCollect(
          status: OrderStatus.draft,
          paymentStatus: PaymentStatus.unpaid,
          total: 100,
        ),
        isFalse,
      );
      expect(
        OrderCollectionRules.canCollect(
          status: OrderStatus.cancelled,
          paymentStatus: PaymentStatus.unpaid,
          total: 100,
        ),
        isFalse,
      );
      expect(
        OrderCollectionRules.canCollect(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.paid,
          total: 100,
        ),
        isFalse,
      );
    });

    test('partial collection leaves a remainder on the same order', () {
      const outstanding = 100000;
      expect(
        OrderCollectionRules.validateAmount(
          amount: 40000,
          outstanding: outstanding,
        ),
        isNull,
      );
      expect(
        OrderCollectionRules.validateAmount(amount: 60000, outstanding: 60000),
        isNull,
      );
      expect(
        OrderCollectionRules.validateAmount(amount: 60001, outstanding: 60000),
        isNotNull,
      );
      expect(
        OrderCollectionRules.validateAmount(
          amount: 0,
          outstanding: outstanding,
        ),
        isNotNull,
      );
    });

    test('full collection is the outstanding amount, not a new order', () {
      expect(
        OrderCollectionRules.validateAmount(amount: 19716, outstanding: 19716),
        isNull,
      );
    });

    test('cheque is collected against the order with cheque details', () {
      expect(OrderCollectionRules.methods, contains(PaymentMethod.cheque));
      expect(
        OrderCollectionRules.validateCheque(
          bankName: '',
          chequeNumber: '1',
          holderName: 'ABC',
        ),
        isNotNull,
      );
      expect(
        OrderCollectionRules.validateCheque(
          bankName: 'Commercial',
          chequeNumber: '1001',
          holderName: 'ABC Inc',
        ),
        isNull,
      );
    });

    test('pending allocations hide Record collection even if still unpaid', () {
      expect(
        OrderCollectionRules.canOfferRecordCollection(
          status: OrderStatus.completed,
          paymentStatus: PaymentStatus.unpaid,
          total: 19716,
          outstanding: 0,
        ),
        isFalse,
      );
    });

    test('order method is pre-selected, wallet/credit fall back to cash', () {
      expect(
        OrderCollectionAssociation.suggestedMethodFromOrder(
          PaymentMethod.cheque,
        ),
        PaymentMethod.cheque,
      );
      expect(
        OrderCollectionAssociation.suggestedMethodFromOrder(
          PaymentMethod.bankTransfer,
        ),
        PaymentMethod.bankTransfer,
      );
      expect(
        OrderCollectionAssociation.suggestedMethodFromOrder(
          PaymentMethod.wallet,
        ),
        PaymentMethod.cash,
      );
      expect(
        OrderCollectionAssociation.suggestedMethodFromOrder(null),
        PaymentMethod.cash,
      );
    });

    test('checkout method is never inherited for a new collection', () {
      expect(
        OrderCollectionAssociation.methodForNewCollection(
          orderPaymentMethod: PaymentMethod.cheque,
        ),
        PaymentMethod.cash,
      );
    });
  });
}
