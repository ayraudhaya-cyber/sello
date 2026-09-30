import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/mobile/orders/application/sello_orders_provider.dart';
import 'package:sello/shared/models/order_status.dart';

void main() {
  group('Sales order list filters', () {
    test('In progress still includes submitted orders that are not completed', () {
      expect(
        salesOrderListStatuses(
          showAllStatuses: false,
          statusFilter: OrderStatus.draft,
        ),
        [
          OrderStatus.draft,
          OrderStatus.placed,
          OrderStatus.partiallyDelivered,
        ],
      );
    });

    test('Completed stays completed only', () {
      expect(
        salesOrderListStatuses(
          showAllStatuses: false,
          statusFilter: OrderStatus.completed,
        ),
        [OrderStatus.completed],
      );
    });

    test('All does not filter by status', () {
      expect(
        salesOrderListStatuses(
          showAllStatuses: true,
          statusFilter: OrderStatus.draft,
        ),
        isNull,
      );
    });
  });

  group('Order status meaning', () {
    test('Completed is fulfillment finished, not merely submitted', () {
      expect(OrderStatus.placed.canFulfill, isTrue);
      expect(OrderStatus.placed.canShareInvoice, isTrue);
      expect(OrderStatus.placed.isSubmitted, isTrue);
      expect(OrderStatus.completed.canFulfill, isFalse);
      expect(OrderStatus.completed.canShareInvoice, isTrue);
      expect(OrderStatus.draft.canShareInvoice, isFalse);
    });
  });
}
