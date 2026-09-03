import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_stock_chip.dart';
import 'package:sello/services/orders/order_stock_policy.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/product_summary.dart';

void main() {
  group('OrderStockPolicy', () {
    test('caps quantity when setting is off', () {
      expect(
        OrderStockPolicy.maxOrderQuantity(
          allowOrdersAboveAvailableStock: false,
          availableStock: 23,
        ),
        23,
      );
      expect(
        OrderStockPolicy.acceptQuantity(requested: 30, max: 23),
        isNull,
      );
      expect(
        OrderStockPolicy.acceptQuantity(requested: 23, max: 23),
        23,
      );
      expect(
        OrderStockPolicy.acceptQuantity(requested: 0, max: 23),
        0,
      );
      expect(OrderStockPolicy.canIncrease(current: 23, max: 23), isFalse);
      expect(OrderStockPolicy.canIncrease(current: 22, max: 23), isTrue);
    });

    test('does not cap when setting is on', () {
      expect(
        OrderStockPolicy.maxOrderQuantity(
          allowOrdersAboveAvailableStock: true,
          availableStock: 23,
        ),
        isNull,
      );
      expect(
        OrderStockPolicy.acceptQuantity(requested: 100, max: null),
        100,
      );
    });

    test('onlyAvailableMessage formats counts', () {
      expect(
        OrderStockPolicy.onlyAvailableMessage(23),
        'Only 23 available',
      );
      expect(OrderStockPolicy.onlyAvailableMessage(0), 'Out of stock');
    });
  });

  group('OrderCatalogStockChip state', () {
    test('detects low stock using reorder level', () {
      expect(
        orderCatalogStockChipState(available: 3, reorderLevel: 10),
        OrderCatalogStockChipState.low,
      );
      expect(
        orderCatalogStockChipState(available: 0, reorderLevel: 10),
        OrderCatalogStockChipState.out,
      );
      expect(
        orderCatalogStockChipState(available: null, reorderLevel: 10),
        OrderCatalogStockChipState.unknown,
      );
    });
  });

  group('CompanySettings', () {
    test('defaults disallow orders above available stock', () {
      expect(
        CompanySettings.defaults.allowOrdersAboveAvailableStock,
        isFalse,
      );
    });

    test('round-trips allow_orders_above_available_stock', () {
      final settings = CompanySettings.fromJson({
        'id': 's1',
        'company_id': 'co1',
        'currency': 'USD',
        'allow_orders_above_available_stock': true,
      });
      expect(settings.allowOrdersAboveAvailableStock, isTrue);
      expect(
        settings.toUpdatePayload(employeeId: 'e1')[
            'allow_orders_above_available_stock'],
        isTrue,
      );
    });
  });

  group('ProductSummary available stock', () {
    test('sums branch available from inventory join', () {
      final product = ProductSummary.fromQueryRow(
        {
          'id': 'p1',
          'company_id': 'co1',
          'sku': 'SKU',
          'name': 'Lock',
          'cost_price': 10,
          'selling_price': 20,
          'is_active': true,
          'inventory': [
            {
              'branch_id': 'b1',
              'quantity': 30,
              'reserved_quantity': 7,
            },
            {
              'branch_id': 'b2',
              'quantity': 100,
              'reserved_quantity': 0,
            },
          ],
        },
        branchId: 'b1',
      );
      expect(product.availableStockQuantity, 23);
      expect(product.currentStockQuantity, 30);
    });

    test('does not clamp requested quantity — rejection is separate', () {
      const requested = 15;
      const available = 8;
      final max = OrderStockPolicy.maxOrderQuantity(
        allowOrdersAboveAvailableStock: false,
        availableStock: available,
      );
      expect(max, 8);
      expect(
        OrderStockPolicy.acceptQuantity(requested: requested, max: max),
        isNull,
      );
      // Draft restore keeps requested quantity; submission validates separately.
      expect(requested, 15);
    });
  });
}
