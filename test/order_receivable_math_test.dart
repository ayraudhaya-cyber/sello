import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/orders/order_receivable_math.dart';

void main() {
  group('OrderReceivableMath delivered value', () {
    test('placed order with nothing delivered has zero AR value', () {
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 200,
          subtotal: 200,
          lines: [(lineTotal: 200, ordered: 20, delivered: 0)],
        ),
        0,
      );
    });

    test('full delivery equals order total', () {
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 200,
          subtotal: 200,
          lines: [(lineTotal: 200, ordered: 20, delivered: 20)],
        ),
        200,
      );
    });

    test('partial delivery recognizes only delivered share, not full order', () {
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 200,
          subtotal: 200,
          lines: [(lineTotal: 200, ordered: 20, delivered: 12)],
        ),
        120,
      );
    });

    test('second fulfillment adds only the newly delivered share', () {
      const total = 200.0;
      const subtotal = 200.0;
      const lines12 = [(lineTotal: 200.0, ordered: 20.0, delivered: 12.0)];
      const lines20 = [(lineTotal: 200.0, ordered: 20.0, delivered: 20.0)];
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: OrderReceivableMath.deliveredOrderValue(
            orderTotal: total,
            subtotal: subtotal,
            lines: lines12,
          ),
          deliveredAfter: OrderReceivableMath.deliveredOrderValue(
            orderTotal: total,
            subtotal: subtotal,
            lines: lines20,
          ),
          allocatedPayments: 0,
        ),
        80,
      );
    });

    test('cancelled remaining does not change delivered value', () {
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 200,
          subtotal: 200,
          lines: [(lineTotal: 200, ordered: 20, delivered: 12)],
        ),
        120,
      );
    });

    test('header discount is allocated to delivered quantity', () {
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 180,
          subtotal: 200,
          lines: [(lineTotal: 200, ordered: 20, delivered: 10)],
        ),
        90,
      );
    });

    test('multi-product uses per-line delivered shares', () {
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 350,
          subtotal: 350,
          lines: [
            (lineTotal: 200, ordered: 20, delivered: 20),
            (lineTotal: 100, ordered: 10, delivered: 4),
            (lineTotal: 50, ordered: 5, delivered: 0),
          ],
        ),
        240,
      );
    });

    test('unequal lines: delivering only A recognizes A value, not 50% of total', () {
      // Product A = 60_000, Product B = 40_000 — deliver A only.
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 100000,
          subtotal: 100000,
          lines: [
            (lineTotal: 60000, ordered: 1, delivered: 1),
            (lineTotal: 40000, ordered: 1, delivered: 0),
          ],
        ),
        60000,
      );
      // Must not be half of order total merely because there are two products.
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 100000,
          subtotal: 100000,
          lines: [
            (lineTotal: 60000, ordered: 1, delivered: 1),
            (lineTotal: 40000, ordered: 1, delivered: 0),
          ],
        ),
        isNot(50000),
      );
    });

    test('partial quantities on unequal lines use delivered financial shares', () {
      // A: 10 ordered / 4 delivered of 60_000 → 24_000
      // B: 20 ordered / 10 delivered of 40_000 → 20_000
      expect(
        OrderReceivableMath.deliveredOrderValue(
          orderTotal: 100000,
          subtotal: 100000,
          lines: [
            (lineTotal: 60000, ordered: 10, delivered: 4),
            (lineTotal: 40000, ordered: 20, delivered: 10),
          ],
        ),
        44000,
      );
    });
  });

  group('OrderReceivableMath AR exposure vs payments', () {
    test('credit delivery with no payment creates full delivered AR', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 120,
          allocatedPayments: 0,
        ),
        120,
      );
    });

    test('partial payment after delivery leaves unpaid remainder', () {
      expect(
        OrderReceivableMath.arExposure(
          deliveredValue: 120,
          allocatedPayments: 50,
        ),
        70,
      );
    });

    test('immediate payment covering delivered value yields zero AR', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 200,
          allocatedPayments: 200,
        ),
        0,
      );
    });

    test('prepayment before delivery does not inflate AR on first fulfill', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 120,
          allocatedPayments: 200,
        ),
        0,
      );
    });

    test('cancellation of remaining has zero AR delta', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 120,
          deliveredAfter: 120,
          allocatedPayments: 0,
        ),
        0,
      );
    });

    test('same-day full credit delivery recognizes full total', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 200,
          allocatedPayments: 0,
        ),
        200,
      );
    });

    test('existing completed recognition is not replayed', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 200,
          deliveredAfter: 200,
          allocatedPayments: 0,
        ),
        0,
      );
    });

    test('full prepayment then partial delivery creates no AR', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 40000,
          allocatedPayments: 100000,
        ),
        0,
      );
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 40000,
          deliveredAfter: 100000,
          allocatedPayments: 100000,
        ),
        0,
      );
    });

    test('partial prepayment then larger delivery recognizes unpaid delivered gap', () {
      // Pay 30_000 before delivery, then deliver 40_000 → outstanding 10_000.
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 40000,
          allocatedPayments: 30000,
        ),
        10000,
      );
    });

    test('credit chain: place zero, partial delivers, cancel remaining is idempotent', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 0,
          deliveredAfter: 40000,
          allocatedPayments: 0,
        ),
        40000,
      );
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 40000,
          deliveredAfter: 70000,
          allocatedPayments: 0,
        ),
        30000,
      );
      // Cancel remaining does not change delivered value → no further AR.
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 70000,
          deliveredAfter: 70000,
          allocatedPayments: 0,
        ),
        0,
      );
    });

    test('re-applying the same delivered value is idempotent', () {
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 40000,
          deliveredAfter: 40000,
          allocatedPayments: 0,
        ),
        0,
      );
      expect(
        OrderReceivableMath.arDelta(
          recognizedValue: 40000,
          deliveredAfter: 40000,
          allocatedPayments: 15000,
        ),
        0,
      );
    });
  });
}
