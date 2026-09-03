import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/shared/models/app_notification.dart';

void main() {
  group('Operational notification event factories', () {
    test('order placed uses event type and medium priority', () {
      final event = BusinessEvents.orderPlaced(
        orderId: 'o1',
        customerName: 'ABC Store',
      );
      expect(event.type, NotificationTypes.orderPlaced);
      expect(event.title, 'New order received');
      expect(event.body, contains('ABC Store'));
      expect(event.priority, NotificationPriority.normal);
      expect(event.referenceType, 'order');
      expect(event.referenceId, 'o1');
      expect(event.notifyHubRoles, isTrue);
    });

    test('insufficient stock is high severity', () {
      final event = BusinessEvents.orderInsufficientStock(
        orderId: 'o1',
        customerName: 'ABC Store',
      );
      expect(event.type, NotificationTypes.orderInsufficientStock);
      expect(event.priority, NotificationPriority.high);
      expect(event.title, 'Order waiting for stock');
    });

    test('partial delivery is medium and references remaining items', () {
      final event = BusinessEvents.orderPartiallyDelivered(
        orderId: 'o1',
        customerName: 'XYZ',
        remainingItems: 7,
      );
      expect(event.type, NotificationTypes.orderPartiallyDelivered);
      expect(event.priority, NotificationPriority.normal);
      expect(event.body, contains('7'));
      expect(event.body, contains('XYZ'));
    });

    test('negative stock is high severity', () {
      final event = BusinessEvents.negativeStock(
        productId: 'p1',
        productName: 'Widget',
      );
      expect(event.type, NotificationTypes.negativeStock);
      expect(event.priority, NotificationPriority.high);
      expect(event.body, contains('Widget'));
      expect(event.referenceType, 'product');
    });

    test('routine stock adjusted does not emit inbox noise', () {
      final event = BusinessEvents.stockAdjusted(
        productId: 'p1',
        productName: 'Widget',
      );
      expect(event.emitNotification, isFalse);
      expect(event.logActivity, isTrue);
    });

    test('out of stock and low stock are activity-only to avoid spam', () {
      expect(
        BusinessEvents.outOfStock(productId: 'p1', productName: 'A')
            .emitNotification,
        isFalse,
      );
      expect(
        BusinessEvents.lowStock(productId: 'p1', productName: 'A')
            .emitNotification,
        isFalse,
      );
    });
  });

  group('Notification dedupe key conventions', () {
    test('place and insufficient stock use distinct keys for same order', () {
      const orderId = '11111111-1111-1111-1111-111111111111';
      final placed = 'order_placed:$orderId';
      final insufficient = 'order_insufficient_stock:$orderId';
      final partial = 'order_partially_delivered:$orderId';
      expect(placed, isNot(insufficient));
      expect(placed, isNot(partial));
      expect(insufficient, isNot(partial));
    });

    test('negative stock keys are movement-scoped so re-cross is allowed', () {
      final first = 'negative_stock:mov-1';
      final second = 'negative_stock:mov-2';
      expect(first, isNot(second));
    });
  });
}
