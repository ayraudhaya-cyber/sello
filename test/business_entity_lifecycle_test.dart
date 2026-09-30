import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/lifecycle/business_entity_lifecycle.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';

void main() {
  group('BusinessEntityLifecycle', () {
    test('inactive records stay out of new transaction selectors', () {
      final people = [
        (name: 'John Silva', active: false),
        (name: 'Asha Perera', active: true),
      ];

      final choices = BusinessEntityLifecycle.forNewTransactions(
        people,
        (person) => person.active,
      );

      expect(choices.map((person) => person.name), ['Asha Perera']);
    });

    test('deactivation is the path when history exists', () {
      final decision = BusinessEntityLifecycle.permanentDelete(
        isActive: false,
        hasHistoricalUse: true,
        noun: 'product',
      );

      expect(decision.allowed, isFalse);
      expect(decision.message, contains('cannot be deleted'));
      expect(decision.message, contains('Deactivate'));
    });

    test('reactivation is allowed for an inactive record with history', () {
      final blockedDelete = BusinessEntityLifecycle.permanentDelete(
        isActive: false,
        hasHistoricalUse: true,
        noun: 'customer',
      );
      final stillListed = BusinessEntityLifecycle.forNewTransactions(
        [(name: 'Rocky', active: true)],
        (person) => person.active,
      );

      expect(blockedDelete.allowed, isFalse);
      expect(stillListed.single.name, 'Rocky');
    });

    test('permanent deletion is allowed only after deactivation and no history', () {
      expect(
        BusinessEntityLifecycle.permanentDelete(
          isActive: false,
          hasHistoricalUse: false,
          noun: 'supplier',
        ).allowed,
        isTrue,
      );
    });

    test('active unused records must be deactivated before deletion', () {
      final decision = BusinessEntityLifecycle.permanentDelete(
        isActive: true,
        hasHistoricalUse: false,
        noun: 'supplier',
      );
      expect(decision.allowed, isFalse);
      expect(decision.message, contains('Deactivate'));
    });

    test('history blocks deletion even while the record is still active', () {
      final decision = BusinessEntityLifecycle.permanentDelete(
        isActive: true,
        hasHistoricalUse: true,
        noun: 'team member',
      );
      expect(decision.allowed, isFalse);
      expect(decision.message, contains('business history'));
    });
  });

  group('historical display', () {
    test('order lines keep the snapshotted product after it becomes inactive', () {
      final line = OrderLineItem.fromJson({
        'id': 'line-1',
        'product_id': 'prod-1',
        'variant_label': 'Red',
        'quantity': 2,
        'unit_price': 160,
        'line_total': 320,
        'product_name': 'Item 2 test',
        'sku': '3633543',
        'products': {
          'name': 'Renamed later',
          'sku': 'NEW',
          'is_active': false,
        },
      });

      expect(line.productName, 'Item 2 test');
      expect(line.productSku, '3633543');
      expect(line.displayTitle, 'Item 2 test · Red');
      expect(line.unitPrice, 160);
    });

    test('orders still show an inactive sales rep and customer', () {
      final order = OrderSummary.fromJson({
        'id': 'order-1',
        'company_id': 'co',
        'branch_id': 'br',
        'order_number': 'SO-1',
        'status': 'completed',
        'payment_status': 'unpaid',
        'payment_method': 'cash',
        'subtotal': 100,
        'discount_amount': 0,
        'tax_amount': 0,
        'total': 100,
        'ordered_at': '2026-09-14T00:00:00Z',
        'updated_at': '2026-09-14T00:00:00Z',
        'customers': {'id': 'c1', 'name': 'Rocky', 'is_active': false},
        'employees': {
          'id': 'e1',
          'full_name': 'John Silva',
          'is_active': false,
        },
      });

      expect(order.customerName, 'Rocky');
      expect(order.employeeName, 'John Silva');
      expect(order.status, OrderStatus.completed);
      expect(order.paymentMethod, PaymentMethod.cash);
      expect(order.paymentStatus, PaymentStatus.unpaid);
    });
  });
}
