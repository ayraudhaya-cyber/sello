import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_option_matrix.dart';
import 'package:sello/services/orders/order_stock_policy.dart';
import 'package:sello/services/orders/visit_order_draft.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_variant.dart';

ProductVariant _variant({
  required String id,
  required String productId,
  required String sku,
  required num sellingPrice,
  String? label,
  bool isDefault = false,
  bool isActive = true,
  num? available,
}) {
  return ProductVariant(
    id: id,
    companyId: 'co1',
    productId: productId,
    sku: sku,
    sellingPrice: sellingPrice,
    label: label,
    isDefault: isDefault,
    isActive: isActive,
    availableStockQuantity: available,
  );
}

ProductSummary _simpleLock() {
  return ProductSummary(
    id: 'p-lock',
    companyId: 'co1',
    name: 'Door Lock',
    sku: 'LOCK',
    sellingPrice: 999,
    costPrice: 400,
    currentStockQuantity: 20,
    availableStockQuantity: 20,
    isActive: true,
    variants: [
      _variant(
        id: 'v-default',
        productId: 'p-lock',
        sku: 'LOCK',
        sellingPrice: 1200,
        isDefault: true,
        available: 20,
      ),
    ],
  );
}

ProductSummary _multiLock() {
  return ProductSummary(
    id: 'p-lock',
    companyId: 'co1',
    name: 'Door Lock',
    sku: 'LOCK',
    sellingPrice: 999,
    costPrice: 400,
    currentStockQuantity: 50,
    availableStockQuantity: 50,
    isActive: true,
    variants: [
      _variant(
        id: 'v-12',
        productId: 'p-lock',
        sku: 'LOCK-12',
        sellingPrice: 1500,
        label: '12"',
        isDefault: true,
        available: 5,
      ),
      _variant(
        id: 'v-20',
        productId: 'p-lock',
        sku: 'LOCK-20',
        sellingPrice: 1800,
        label: '20"',
        available: 3,
      ),
    ],
  );
}

/// Mirrors editor basket identity — keyed by [OrderLineDraft.lineKey].
class _Basket {
  final lines = <OrderLineDraft>[];

  Map<String, OrderLineDraft> get byVariant => {
        for (final line in lines) line.lineKey: line,
      };

  void upsert(OrderLineDraft line) {
    final index = lines.indexWhere((l) => l.lineKey == line.lineKey);
    if (index >= 0) {
      lines[index] = line;
    } else {
      lines.add(line);
    }
  }

  void setQuantity(String variantId, num quantity) {
    final index = lines.indexWhere((l) => l.lineKey == variantId);
    if (index < 0) return;
    if (quantity < 1) {
      lines.removeAt(index);
      return;
    }
    lines[index] = lines[index].copyWith(quantity: quantity);
  }

  void remove(String variantId) {
    lines.removeWhere((l) => l.lineKey == variantId);
  }
}

OrderLineDraft _lineFrom(
  ProductSummary product,
  ProductVariant variant, {
  required num quantity,
}) {
  return OrderLineDraft(
    productId: product.id,
    variantId: variant.id,
    variantLabel: variant.hasLabel &&
            variant.label!.trim().toLowerCase() != 'default'
        ? variant.label
        : null,
    productName: product.name,
    productSku: variant.sku,
    unitPrice: variant.sellingPrice,
    quantity: quantity,
    availableStock: variant.availableStockQuantity,
  );
}

/// Same shape OrderRepository inserts for new order lines.
Map<String, dynamic> _submissionRow(OrderLineDraft line) {
  return {
    'product_id': line.productId,
    if (line.variantId != null) 'variant_id': line.variantId,
    'quantity': line.quantity,
    'unit_price': line.unitPrice,
    'line_total': line.lineTotal,
  };
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

class _MultiOptionHarness extends StatefulWidget {
  const _MultiOptionHarness({required this.product});

  final ProductSummary product;

  @override
  State<_MultiOptionHarness> createState() => _MultiOptionHarnessState();
}

class _MultiOptionHarnessState extends State<_MultiOptionHarness> {
  final qty = <String, num>{};

  @override
  Widget build(BuildContext context) {
    return OrderCatalogMultiOptionCard(
      product: widget.product,
      currencySymbol: 'Rs',
      expanded: true,
      onToggleExpanded: () {},
      quantityForVariant: (v) => qty[v.id] ?? 0,
      maxQuantityForVariant: (_) => null,
      onAddVariant: (v) => setState(() => qty[v.id] = 1),
      onVariantQuantityChanged: (v, q) => setState(() => qty[v.id] = q),
      onOpenPhotos: () {},
    );
  }
}

void main() {
  group('single-option default variant', () {
    test('catalog price resolves from the live default variant', () {
      final product = _simpleLock();
      final variant = product.defaultVariant!;
      expect(product.hasMultipleActiveVariants, isFalse);
      expect(variant.id, 'v-default');
      expect(variant.sellingPrice, 1200);
      expect(variant.sellingPrice, isNot(product.sellingPrice));
    });

    test('adding uses default variant identity and price', () {
      final product = _simpleLock();
      final variant = product.defaultVariant!;
      final basket = _Basket()..upsert(_lineFrom(product, variant, quantity: 1));
      expect(basket.lines, hasLength(1));
      expect(basket.lines.single.lineKey, 'v-default');
      expect(basket.lines.single.unitPrice, 1200);
      expect(basket.lines.single.displayTitle, 'Door Lock');
    });
  });

  group('multi-option selection', () {
    testWidgets('can select each active option', (tester) async {
      final product = _multiLock();
      await tester.pumpWidget(
        _wrap(
          _MultiOptionHarness(product: product),
        ),
      );

      expect(find.text('Hide options'), findsOneWidget);
      expect(find.text('12"'), findsOneWidget);
      expect(find.text('20"'), findsOneWidget);
      expect(find.textContaining('1,500'), findsOneWidget);
      expect(find.textContaining('1,800'), findsOneWidget);

      await tester.tap(find.text('Add').at(0));
      await tester.pump();
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
    });

    test('selected variant price is used, not parent sellingPrice', () {
      final product = _multiLock();
      final twelve = product.resolveSellableVariant('v-12')!;
      final twenty = product.resolveSellableVariant('v-20')!;
      expect(twelve.sellingPrice, 1500);
      expect(twenty.sellingPrice, 1800);
      expect(twelve.sellingPrice, isNot(product.sellingPrice));
    });
  });

  group('basket identity', () {
    test('same parent + two variants coexist as separate lines', () {
      final product = _multiLock();
      final basket = _Basket()
        ..upsert(_lineFrom(product, product.variants[0], quantity: 5))
        ..upsert(_lineFrom(product, product.variants[1], quantity: 3));

      expect(basket.lines, hasLength(2));
      expect(basket.byVariant.keys.toSet(), {'v-12', 'v-20'});
      expect(basket.byVariant['v-12']!.quantity, 5);
      expect(basket.byVariant['v-20']!.quantity, 3);
      expect(basket.byVariant['v-12']!.displayTitle, 'Door Lock · 12"');
      expect(basket.byVariant['v-20']!.displayTitle, 'Door Lock · 20"');
    });

    test('changing variant A quantity does not change variant B', () {
      final product = _multiLock();
      final basket = _Basket()
        ..upsert(_lineFrom(product, product.variants[0], quantity: 5))
        ..upsert(_lineFrom(product, product.variants[1], quantity: 3));

      basket.setQuantity('v-12', 2);
      expect(basket.byVariant['v-12']!.quantity, 2);
      expect(basket.byVariant['v-20']!.quantity, 3);
    });

    test('removing variant A does not remove variant B', () {
      final product = _multiLock();
      final basket = _Basket()
        ..upsert(_lineFrom(product, product.variants[0], quantity: 5))
        ..upsert(_lineFrom(product, product.variants[1], quantity: 3));

      basket.remove('v-12');
      expect(basket.lines, hasLength(1));
      expect(basket.lines.single.lineKey, 'v-20');
      expect(basket.lines.single.quantity, 3);
    });

    test('lineKey prefers variantId over productId', () {
      final line = OrderLineDraft(
        productId: 'p-lock',
        variantId: 'v-12',
        productName: 'Door Lock',
        unitPrice: 1500,
        quantity: 1,
      );
      expect(line.lineKey, 'v-12');
      expect(line.lineKey, isNot(line.productId));
    });

    test('displayTitle never shows Default', () {
      final labeled = OrderLineDraft(
        productId: 'p1',
        variantId: 'v1',
        variantLabel: 'Default',
        productName: 'Widget',
        unitPrice: 10,
        quantity: 1,
      );
      expect(labeled.displayTitle, 'Widget');
      expect(labeled.displayTitle.toLowerCase().contains('default'), isFalse);
    });
  });

  group('variant-specific stock', () {
    test('max quantity is variant-specific in strict mode', () {
      final product = _multiLock();
      final max12 = OrderStockPolicy.maxOrderQuantity(
        allowOrdersAboveAvailableStock: false,
        availableStock: product.variants[0].availableStockQuantity,
      );
      final max20 = OrderStockPolicy.maxOrderQuantity(
        allowOrdersAboveAvailableStock: false,
        availableStock: product.variants[1].availableStockQuantity,
      );
      expect(max12, 5);
      expect(max20, 3);
      expect(OrderStockPolicy.acceptQuantity(requested: 6, max: max12), isNull);
      expect(OrderStockPolicy.acceptQuantity(requested: 5, max: max12), 5);
      expect(OrderStockPolicy.acceptQuantity(requested: 4, max: max20), isNull);
    });

    test('strict mode blocks above available', () {
      expect(
        OrderStockPolicy.acceptQuantity(requested: 6, max: 5),
        isNull,
      );
    });

    test('flexible mode records above available', () {
      final max = OrderStockPolicy.maxOrderQuantity(
        allowOrdersAboveAvailableStock: true,
        availableStock: 3,
      );
      expect(max, isNull);
      expect(OrderStockPolicy.acceptQuantity(requested: 10, max: max), 10);
    });
  });

  group('draft compatibility', () {
    test('new drafts persist variantId', () {
      const line = VisitOrderDraftLine(
        productId: 'p-lock',
        variantId: 'v-12',
        quantity: 5,
      );
      expect(line.toJson()['variantId'], 'v-12');
      expect(VisitOrderDraftLine.fromJson(line.toJson()).variantId, 'v-12');
    });

    test('legacy product-only drafts map to default variant', () {
      final product = _multiLock();
      final draft = VisitOrderDraftLine.fromJson(const {
        'productId': 'p-lock',
        'quantity': 4,
      });
      final resolved = product.resolveSellableVariant(draft.variantId);
      expect(draft.variantId, isNull);
      expect(resolved?.id, 'v-12');
      expect(resolved?.isDefault, isTrue);
    });

    test('mismatched variant/product falls back to default', () {
      final product = _multiLock();
      final resolved = product.resolveSellableVariant('v-other-product');
      expect(resolved?.id, 'v-12');
    });

    test('requested quantities survive restore mapping', () {
      final product = _multiLock();
      final draft = VisitOrderDraft(
        companyId: 'co1',
        employeeId: 'emp1',
        customerId: 'cust1',
        lines: const [
          VisitOrderDraftLine(
            productId: 'p-lock',
            variantId: 'v-20',
            quantity: 7,
          ),
          VisitOrderDraftLine(productId: 'p-lock', quantity: 2),
        ],
        updatedAt: DateTime(2026, 9, 18),
      );
      final restored = VisitOrderDraft.fromJson(draft.toJson());
      expect(restored.lines[0].quantity, 7);
      expect(restored.lines[1].quantity, 2);

      final a = product.resolveSellableVariant(restored.lines[0].variantId)!;
      final b = product.resolveSellableVariant(restored.lines[1].variantId)!;
      expect(a.id, 'v-20');
      expect(b.id, 'v-12');
    });
  });

  group('basket sheet / editor shared identity', () {
    test('quantity and remove APIs are variant-keyed via lineKey', () {
      final product = _multiLock();
      final basket = _Basket()
        ..upsert(_lineFrom(product, product.variants[0], quantity: 2))
        ..upsert(_lineFrom(product, product.variants[1], quantity: 1));

      // Same contract visit_basket_sheet uses: line.lineKey.
      for (final line in List<OrderLineDraft>.from(basket.lines)) {
        basket.setQuantity(line.lineKey, line.quantity + 1);
      }
      expect(basket.byVariant['v-12']!.quantity, 3);
      expect(basket.byVariant['v-20']!.quantity, 2);

      basket.remove(basket.lines.first.lineKey);
      expect(basket.lines, hasLength(1));
    });
  });

  group('order submission', () {
    test('submitted rows include the correct variant_id', () {
      final product = _multiLock();
      final input = OrderUpsertInput(
        customerId: 'cust1',
        lines: [
          _lineFrom(product, product.variants[0], quantity: 5),
          _lineFrom(product, product.variants[1], quantity: 3),
        ],
      );
      final rows = [for (final line in input.lines) _submissionRow(line)];
      expect(rows.map((r) => r['variant_id']), ['v-12', 'v-20']);
      expect(rows.map((r) => r['product_id']).toSet(), {'p-lock'});
      expect(rows[0]['unit_price'], 1500);
      expect(rows[1]['unit_price'], 1800);
    });

    test('simple product submission still carries default variantId', () {
      final product = _simpleLock();
      final line = _lineFrom(product, product.defaultVariant!, quantity: 1);
      expect(_submissionRow(line)['variant_id'], 'v-default');
    });
  });
}
