import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/orders/visit_order_draft.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/product_summary.dart';

void main() {
  group('ProductSummary variants', () {
    test('exposes the default variant as the sellable identity', () {
      final product = ProductSummary.fromQueryRow({
        'id': 'p1',
        'company_id': 'c1',
        'name': 'Widget',
        'sku': 'W-1',
        'selling_price': 100,
        'cost_price': 40,
        'is_active': true,
        'inventory': const [],
        'product_variants': const [
          {
            'id': 'v-blue',
            'company_id': 'c1',
            'product_id': 'p1',
            'label': 'Blue',
            'sku': 'W-1-BLUE',
            'selling_price': 120,
            'sort_order': 2,
            'is_default': false,
            'is_active': true,
          },
          {
            'id': 'v-default',
            'company_id': 'c1',
            'product_id': 'p1',
            'label': null,
            'sku': 'W-1',
            'selling_price': 100,
            'sort_order': 0,
            'is_default': true,
            'is_active': true,
          },
        ],
      });

      expect(product.variants.first.id, 'v-default');
      expect(product.defaultVariantId, 'v-default');
      expect(product.defaultVariant?.hasLabel, isFalse);
      expect(product.activeVariants.length, 2);
    });

    test('attaches branch stock to the variant that owns it', () {
      final product = ProductSummary.fromQueryRow(
        {
          'id': 'p1',
          'company_id': 'c1',
          'name': 'Widget',
          'sku': 'W-1',
          'selling_price': 100,
          'is_active': true,
          'inventory': const [
            {
              'branch_id': 'b1',
              'variant_id': 'v-default',
              'quantity': 10,
              'reserved_quantity': 2,
            },
            {
              'branch_id': 'b1',
              'variant_id': 'v-blue',
              'quantity': 5,
              'reserved_quantity': 0,
            },
            {
              'branch_id': 'b2',
              'variant_id': 'v-default',
              'quantity': 99,
              'reserved_quantity': 0,
            },
          ],
          'product_variants': const [
            {
              'id': 'v-default',
              'company_id': 'c1',
              'product_id': 'p1',
              'sku': 'W-1',
              'selling_price': 100,
              'is_default': true,
              'is_active': true,
            },
            {
              'id': 'v-blue',
              'company_id': 'c1',
              'product_id': 'p1',
              'label': 'Blue',
              'sku': 'W-1-BLUE',
              'selling_price': 120,
              'is_default': false,
              'is_active': true,
            },
          ],
        },
        branchId: 'b1',
      );

      // Parent totals stay the sum across the branch's variants.
      expect(product.currentStockQuantity, 15);
      expect(product.availableStockQuantity, 13);

      final defaultVariant = product.defaultVariant!;
      expect(defaultVariant.stockQuantity, 10);
      expect(defaultVariant.availableStockQuantity, 8);

      final blue = product.variants.firstWhere((v) => v.id == 'v-blue');
      expect(blue.stockQuantity, 5);
      expect(blue.availableStockQuantity, 5);
    });

    test('stays empty when the select did not embed variants', () {
      final product = ProductSummary.fromQueryRow({
        'id': 'p1',
        'company_id': 'c1',
        'name': 'Widget',
        'sku': 'W-1',
        'selling_price': 100,
        'is_active': true,
        'inventory': const [],
      });

      expect(product.variants, isEmpty);
      expect(product.defaultVariantId, isNull);
    });
  });

  group('InventoryItem variant identity', () {
    test('reads variant id and sellable sku alongside the parent sku', () {
      final item = InventoryItem.fromQueryRow({
        'id': 'inv1',
        'company_id': 'c1',
        'branch_id': 'b1',
        'product_id': 'p1',
        'variant_id': 'v-blue',
        'quantity': 7,
        'reserved_quantity': 1,
        'product_variants': const {
          'id': 'v-blue',
          'label': 'Blue',
          'sku': 'W-1-BLUE',
        },
        'products': const {
          'name': 'Widget',
          'sku': 'W-1',
          'is_active': true,
        },
      });

      expect(item.variantId, 'v-blue');
      expect(item.variantLabel, 'Blue');
      expect(item.variantSku, 'W-1-BLUE');
      expect(item.sku, 'W-1');
      expect(item.availableQuantity, 6);
    });

    test('tolerates a legacy row without variant columns', () {
      final item = InventoryItem.fromQueryRow({
        'id': 'inv1',
        'company_id': 'c1',
        'branch_id': 'b1',
        'product_id': 'p1',
        'quantity': 3,
        'products': const {'name': 'Widget', 'sku': 'W-1', 'is_active': true},
      });

      expect(item.variantId, isNull);
      expect(item.variantLabel, isNull);
    });
  });

  test('StockMovement carries the variant it was recorded against', () {
    final movement = StockMovement.fromJson({
      'id': 'm1',
      'product_id': 'p1',
      'variant_id': 'v-blue',
      'branch_id': 'b1',
      'movement_type': 'sale',
      'quantity_delta': -2,
      'quantity_after': 5,
      'created_at': '2026-09-16T10:00:00Z',
      'product_variants': const {'id': 'v-blue', 'label': 'Blue'},
    });

    expect(movement.variantId, 'v-blue');
    expect(movement.variantLabel, 'Blue');
  });

  group('OrderLineItem snapshots', () {
    test('prefers stored snapshots over the live catalog join', () {
      final line = OrderLineItem.fromJson({
        'id': 'oi1',
        'product_id': 'p1',
        'variant_id': 'v-blue',
        'product_name': 'Widget (as sold)',
        'variant_label': 'Blue',
        'sku': 'W-1-BLUE',
        'quantity': 2,
        'unit_price': 120,
        'line_total': 240,
        'products': const {
          'name': 'Widget renamed later',
          'sku': 'W-9',
        },
      });

      expect(line.variantId, 'v-blue');
      expect(line.variantLabel, 'Blue');
      expect(line.productName, 'Widget (as sold)');
      expect(line.productSku, 'W-1-BLUE');
    });

    test('falls back to the catalog join when snapshots are absent', () {
      final line = OrderLineItem.fromJson({
        'id': 'oi1',
        'product_id': 'p1',
        'quantity': 1,
        'unit_price': 100,
        'line_total': 100,
        'products': const {'name': 'Widget', 'sku': 'W-1'},
      });

      expect(line.variantId, isNull);
      expect(line.productName, 'Widget');
      expect(line.productSku, 'W-1');
    });
  });

  group('VisitOrderDraftLine legacy compatibility', () {
    test('restores a pre-variant draft with a null variant', () {
      final line = VisitOrderDraftLine.fromJson(const {
        'productId': 'p1',
        'quantity': 3,
      });

      expect(line.productId, 'p1');
      expect(line.variantId, isNull);
      expect(line.quantity, 3);
    });

    test('round-trips a variant-aware draft', () {
      final draft = VisitOrderDraft(
        companyId: 'co1',
        employeeId: 'emp1',
        lines: const [
          VisitOrderDraftLine(
            productId: 'p1',
            variantId: 'v-blue',
            quantity: 2,
          ),
        ],
        updatedAt: DateTime(2026, 9, 16),
      );

      final restored = VisitOrderDraft.fromJson(draft.toJson());
      expect(restored.lines.single.productId, 'p1');
      expect(restored.lines.single.variantId, 'v-blue');
      expect(restored.lines.single.quantity, 2);
    });

    test('omits the variant key entirely for legacy-shaped lines', () {
      const line = VisitOrderDraftLine(productId: 'p1', quantity: 1);
      expect(line.toJson().containsKey('variantId'), isFalse);
    });

    test('treats a blank stored variant as absent', () {
      final line = VisitOrderDraftLine.fromJson(const {
        'productId': 'p1',
        'variantId': '  ',
        'quantity': 1,
      });

      expect(line.variantId, isNull);
    });
  });
}
