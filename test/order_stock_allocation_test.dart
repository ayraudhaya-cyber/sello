import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/orders/order_stock_allocation.dart';

void main() {
  final older = DateTime.utc(2026, 11, 1);
  final newer = DateTime.utc(2026, 11, 2);

  OpenOrderStockDemand order({
    required String id,
    required DateTime at,
    required String key,
    required num remaining,
  }) {
    return OpenOrderStockDemand(
      orderId: id,
      orderedAt: at,
      lines: [OpenOrderStockLine(stockKey: key, remaining: remaining)],
    );
  }

  test('oldest order claims the only units', () {
    final short = OrderStockAllocation.ordersShortOfStock(
      orders: [
        order(id: 'new', at: newer, key: 'b|v', remaining: 10),
        order(id: 'old', at: older, key: 'b|v', remaining: 10),
      ],
      onHandByKey: {'b|v': 10},
    );

    expect(short, {'new'});
  });

  test('an order larger than on-hand is short even when it is first', () {
    final short = OrderStockAllocation.ordersShortOfStock(
      orders: [
        order(id: 'old', at: older, key: 'b|v', remaining: 12),
        order(id: 'new', at: newer, key: 'b|v', remaining: 1),
      ],
      onHandByKey: {'b|v': 10},
    );

    expect(short, {'old', 'new'});
  });

  test('branches do not share stock', () {
    final short = OrderStockAllocation.ordersShortOfStock(
      orders: [
        order(id: 'a', at: older, key: 'branch-a|v', remaining: 4),
        order(id: 'b', at: older, key: 'branch-b|v', remaining: 4),
      ],
      onHandByKey: {'branch-a|v': 4, 'branch-b|v': 1},
    );

    expect(short, {'b'});
  });

  test('a newer order can take only what older orders do not still need', () {
    expect(
      OrderStockAllocation.deliverableQuantity(
        onHand: 10,
        olderOpenDemand: 10,
      ),
      0,
    );
    expect(
      OrderStockAllocation.deliverableQuantity(
        onHand: 10,
        olderOpenDemand: 6,
      ),
      4,
    );
    expect(
      OrderStockAllocation.deliverableQuantity(
        onHand: 10,
        olderOpenDemand: 0,
      ),
      10,
    );
    expect(
      OrderStockAllocation.deliverableQuantity(
        onHand: 4,
        olderOpenDemand: 0,
      ),
      4,
    );
  });

  test('partial delivery leaves the undelivered remainder reserved', () {
    expect(
      OrderStockAllocation.reservedAfterDelivery(
        openUndelivered: 20,
        delivering: 4,
      ),
      16,
    );
    expect(
      OrderStockAllocation.reservedAfterRelease(reserved: 16, releasing: 3),
      13,
    );
  });

  test('a partial remainder that fits is not short', () {
    final short = OrderStockAllocation.ordersShortOfStock(
      orders: [
        order(id: 'partial', at: older, key: 'b|v', remaining: 3),
      ],
      onHandByKey: {'b|v': 3},
    );

    expect(short, isEmpty);
  });
}
