import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/payments/application/receive_payment_allocation.dart';
import 'package:sello/shared/models/payment_summary.dart';

void main() {
  ReceivableOrder order({
    required String id,
    required num remaining,
    ReceivableKind kind = ReceivableKind.order,
  }) {
    return ReceivableOrder(
      id: id,
      orderNumber: id,
      total: remaining,
      amountPaid: 0,
      orderedAt: DateTime(2026, 9, 1),
      kind: kind,
    );
  }

  final opening = order(
    id: 'ob-1',
    remaining: 95480,
    kind: ReceivableKind.openingBalance,
  );
  final small = order(id: 'so-1', remaining: 640);
  final mid = order(id: 'so-2', remaining: 480);

  group('ReceivePaymentAllocation', () {
    test('checking a row covers the full remaining amount', () {
      expect(ReceivePaymentAllocation.fullAmount(small), 640);
      expect(ReceivePaymentAllocation.fullAmount(opening), 95480);
    });

    test('select all covers every order and opening balance', () {
      final allocations = ReceivePaymentAllocation.selectAll([
        opening,
        small,
        mid,
      ]);
      expect(allocations, {'ob-1': 95480, 'so-1': 640, 'so-2': 480});
      expect(ReceivePaymentAllocation.totalOf(allocations), 96600);
      expect(
        ReceivePaymentAllocation.selectAllValue(
          receivables: [opening, small, mid],
          selectedIds: allocations.keys.toSet(),
        ),
        isTrue,
      );
    });

    test('opening balance can be selected on its own', () {
      final allocations = {
        'ob-1': ReceivePaymentAllocation.fullAmount(opening),
      };
      expect(allocations.containsKey('so-1'), isFalse);
      expect(
        ReceivePaymentAllocation.selectAllValue(
          receivables: [opening, small, mid],
          selectedIds: {'ob-1'},
        ),
        isNull,
      );
    });

    test('manual amount is clamped to remaining', () {
      expect(
        ReceivePaymentAllocation.clampAmount(amount: 200, remaining: 640),
        200,
      );
      expect(
        ReceivePaymentAllocation.clampAmount(amount: 900, remaining: 640),
        640,
      );
      expect(
        ReceivePaymentAllocation.clampAmount(amount: 0, remaining: 640),
        0,
      );
    });

    test('selected outstanding cannot exceed the payment amount', () {
      expect(
        ReceivePaymentAllocation.validate(
          paymentAmount: 640,
          allocations: {'so-1': 640, 'so-2': 480},
          receivables: [small, mid],
        ),
        isNotNull,
      );
      expect(
        ReceivePaymentAllocation.validate(
          paymentAmount: 1120,
          allocations: {'so-1': 640, 'so-2': 480},
          receivables: [small, mid],
        ),
        isNull,
      );
    });
  });
}
