import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/orders/order_fulfillment_math.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';

void main() {
  group('OrderFulfillmentMath', () {
    test('remaining is ordered minus delivered minus cancelled', () {
      expect(
        OrderFulfillmentMath.remaining(
          ordered: 20,
          delivered: 12,
          cancelled: 0,
        ),
        8,
      );
      expect(
        OrderFulfillmentMath.remaining(
          ordered: 20,
          delivered: 12,
          cancelled: 8,
        ),
        0,
      );
    });

    test('floors remaining at zero', () {
      expect(
        OrderFulfillmentMath.remaining(
          ordered: 10,
          delivered: 8,
          cancelled: 5,
        ),
        0,
      );
    });

    test('accepts fulfillment only within remaining', () {
      expect(
        OrderFulfillmentMath.acceptFulfillmentQuantity(
          requested: 5,
          remaining: 8,
        ),
        5,
      );
      expect(
        OrderFulfillmentMath.acceptFulfillmentQuantity(
          requested: 9,
          remaining: 8,
        ),
        isNull,
      );
      expect(
        OrderFulfillmentMath.acceptFulfillmentQuantity(
          requested: 0,
          remaining: 8,
        ),
        isNull,
      );
    });

    test('partial then final fulfillment closes remaining', () {
      const ordered = 20;
      var delivered = 0;
      delivered += 12;
      expect(
        OrderFulfillmentMath.remaining(
          ordered: ordered,
          delivered: delivered,
          cancelled: 0,
        ),
        8,
      );
      delivered += 8;
      expect(
        OrderFulfillmentMath.isFullyClosed(
          ordered: ordered,
          delivered: delivered,
          cancelled: 0,
        ),
        isTrue,
      );
    });

    test('cancel remaining closes without counting as delivered', () {
      expect(
        OrderFulfillmentMath.isFullyClosed(
          ordered: 20,
          delivered: 12,
          cancelled: 8,
        ),
        isTrue,
      );
      expect(
        OrderFulfillmentMath.remaining(
          ordered: 20,
          delivered: 12,
          cancelled: 8,
        ),
        0,
      );
    });
  });

  group('OrderStatus fulfillment', () {
    test('maps legacy submitted to placed', () {
      expect(OrderStatus.fromDb('submitted'), OrderStatus.placed);
      expect(OrderStatus.fromDb('placed'), OrderStatus.placed);
      expect(
        OrderStatus.fromDb('partially_delivered'),
        OrderStatus.partiallyDelivered,
      );
      expect(OrderStatus.partiallyDelivered.dbValue, 'partially_delivered');
    });

    test('canFulfill only for open placed orders', () {
      expect(OrderStatus.placed.canFulfill, isTrue);
      expect(OrderStatus.partiallyDelivered.canFulfill, isTrue);
      expect(OrderStatus.draft.canFulfill, isFalse);
      expect(OrderStatus.completed.canFulfill, isFalse);
      expect(OrderStatus.cancelled.canFulfill, isFalse);
    });

    test('placed is open and not completed', () {
      expect(OrderStatus.placed.isOpen, isTrue);
      expect(OrderStatus.placed.canFulfill, isTrue);
      expect(OrderStatus.completed.isOpen, isFalse);
    });
  });

  group('OrderLineItem fulfillment fields', () {
    test('parses delivered and cancelled quantities', () {
      final line = OrderLineItem.fromJson({
        'id': 'li1',
        'product_id': 'p1',
        'quantity': 20,
        'delivered_quantity': 12,
        'cancelled_quantity': 3,
        'unit_price': 10,
        'line_total': 200,
      });
      expect(line.quantity, 20);
      expect(line.deliveredQuantity, 12);
      expect(line.cancelledQuantity, 3);
      expect(line.remainingQuantity, 5);
    });

    test('defaults missing fulfillment columns to zero', () {
      final line = OrderLineItem.fromJson({
        'id': 'li1',
        'product_id': 'p1',
        'quantity': 7,
        'unit_price': 10,
        'line_total': 70,
      });
      expect(line.deliveredQuantity, 0);
      expect(line.cancelledQuantity, 0);
      expect(line.remainingQuantity, 7);
    });

    test('multi-product remaining aggregates independently', () {
      final a = OrderLineItem.fromJson({
        'id': 'a',
        'product_id': 'p1',
        'quantity': 20,
        'delivered_quantity': 20,
        'cancelled_quantity': 0,
        'unit_price': 1,
        'line_total': 20,
      });
      final b = OrderLineItem.fromJson({
        'id': 'b',
        'product_id': 'p2',
        'quantity': 10,
        'delivered_quantity': 4,
        'cancelled_quantity': 0,
        'unit_price': 1,
        'line_total': 10,
      });
      final c = OrderLineItem.fromJson({
        'id': 'c',
        'product_id': 'p3',
        'quantity': 5,
        'delivered_quantity': 0,
        'cancelled_quantity': 0,
        'unit_price': 1,
        'line_total': 5,
      });
      expect(a.remainingQuantity, 0);
      expect(b.remainingQuantity, 6);
      expect(c.remainingQuantity, 5);
      expect(
        OrderFulfillmentMath.isFullyClosed(
          ordered: a.quantity,
          delivered: a.deliveredQuantity,
          cancelled: a.cancelledQuantity,
        ),
        isTrue,
      );
      expect(
        [a, b, c].any((l) => l.remainingQuantity > 0),
        isTrue,
      );
    });

    test('cannot accept delivery above remaining', () {
      expect(
        OrderFulfillmentMath.acceptFulfillmentQuantity(
          requested: 9,
          remaining: 8,
        ),
        isNull,
      );
    });

    test('deliver then cancel remaining resolves order math', () {
      const ordered = 20;
      const delivered = 12;
      const cancelled = 8;
      expect(
        OrderFulfillmentMath.remaining(
          ordered: ordered,
          delivered: delivered,
          cancelled: cancelled,
        ),
        0,
      );
      // Inventory impact is delivered only — cancelled is not delivered.
      expect(delivered, 12);
      expect(cancelled, 8);
    });
  });
}
