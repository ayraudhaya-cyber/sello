import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/orders/application/repeat_last_order.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_option_matrix.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_product_views.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_stock_chip.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/widgets/products/product_options_readonly_list.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 180, child: child),
      ),
    ),
  );
}

OrderSummary _order({
  required String id,
  required String customerId,
  required String status,
  required String orderedAt,
}) {
  return OrderSummary.fromJson({
    'id': id,
    'company_id': 'co',
    'branch_id': 'br',
    'customer_id': customerId,
    'order_number': id,
    'status': status,
    'payment_status': 'paid',
    'payment_method': 'cash',
    'subtotal': 10,
    'discount_amount': 0,
    'tax_amount': 0,
    'total': 10,
    'ordered_at': orderedAt,
    'updated_at': orderedAt,
  });
}

void main() {
  group('quantity control', () {
    Future<void> pumpQty(WidgetTester tester, num value, double width) {
      return tester.pumpWidget(
        _wrap(
          SizedBox(
            width: width,
            child: ProductQuantityControl(
              value: value,
              allowZero: true,
              showRemove: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('keeps a stable slot from 1 through 999', (tester) async {
      const samples = <num>[1, 9, 19, 99, 100, 999];
      double? width;
      for (final value in samples) {
        await pumpQty(tester, value, 360);
        expect(tester.takeException(), isNull);
        expect(find.text(value.toString()), findsOneWidget);
        final slot = tester.getSize(
          find
              .ancestor(
                of: find.text(value.toString()),
                matching: find.byType(SizedBox),
              )
              .first,
        );
        width ??= slot.width;
        expect(slot.width, width);
        final minus = tester.getCenter(find.byIcon(Icons.remove_rounded));
        final plus = tester.getCenter(find.byIcon(Icons.add_rounded));
        expect(plus.dx - minus.dx, lessThan(120));
        expect(plus.dx, greaterThan(minus.dx));
      }
    });

    testWidgets('does not overflow a narrow grid card at 999', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 170,
                child: OrderCatalogGridCard(
                  product: ProductSummary(
                    id: 'p1',
                    companyId: 'co',
                    name: 'Premium Dog Kibble (2 kg)',
                    sku: 'KIB',
                    sellingPrice: 10600,
                    costPrice: 1,
                    currentStockQuantity: 24,
                    availableStockQuantity: 24,
                    isActive: true,
                  ),
                  currencySymbol: 'Rs',
                  quantity: 999,
                  onAdd: () {},
                  onQuantityChanged: (_) {},
                  onOpenPhotos: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('999'), findsOneWidget);
    });
  });

  group('availability badge', () {
    testWidgets('shows the quantity without the word available', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OrderCatalogStockChip(available: 24),
        ),
      );
      expect(find.text('24'), findsOneWidget);
      expect(find.text('24 available'), findsNothing);
    });

    testWidgets('shows 0 when out of stock', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OrderCatalogStockChip(available: 0),
        ),
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Out of stock'), findsNothing);
    });
  });

  group('multi-option card', () {
    testWidgets('places the option name above the Add control', (tester) async {
      await tester.pumpWidget(
        _wrap(
          OrderCatalogMultiOptionCard(
            product: ProductSummary(
              id: 'p1',
              companyId: 'co',
              name: 'Handle Bar',
              sku: 'HB',
              sellingPrice: 100,
              costPrice: 40,
              currentStockQuantity: 10,
              availableStockQuantity: 10,
              isActive: true,
              variants: [
                ProductVariant(
                  id: 'v20',
                  companyId: 'co',
                  productId: 'p1',
                  sku: 'HB-20',
                  sellingPrice: 200,
                  label: '20"',
                  isDefault: false,
                  isActive: true,
                  availableStockQuantity: 50,
                ),
              ],
            ),
            currencySymbol: 'Rs',
            expanded: true,
            onToggleExpanded: () {},
            quantityForVariant: (_) => 0,
            maxQuantityForVariant: (_) => null,
            onAddVariant: (_) {},
            onVariantQuantityChanged: (_, _) {},
            onOpenPhotos: () {},
          ),
        ),
      );

      expect(find.text('20"'), findsOneWidget);
      expect(find.byTooltip('Add to order'), findsOneWidget);
      final nameTop = tester.getTopLeft(find.text('20"')).dy;
      final addTop = tester.getTopLeft(find.byTooltip('Add to order')).dy;
      expect(nameTop, lessThan(addTop));
    });
  });

  group('present sheet', () {
    testWidgets('lists sellable options instead of a single parent price', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ProductOptionsReadonlyList(
            options: [
              ProductVariant(
                id: 'v-red',
                companyId: 'co',
                productId: 'p1',
                sku: 'TESTP3RED',
                sellingPrice: 200,
                label: 'red',
                isDefault: true,
                isActive: true,
                availableStockQuantity: 0,
              ),
              ProductVariant(
                id: 'v-green',
                companyId: 'co',
                productId: 'p1',
                sku: 'TESTP3GRE',
                sellingPrice: 450,
                label: 'green',
                isDefault: false,
                isActive: true,
                availableStockQuantity: 80,
              ),
            ],
            currencySymbol: 'Rs',
            unitLabel: 'piece',
          ),
        ),
      );

      expect(find.text('Options'), findsOneWidget);
      expect(find.text('red'), findsOneWidget);
      expect(find.text('green'), findsOneWidget);
      expect(find.text('TESTP3RED'), findsOneWidget);
      expect(find.text('TESTP3GRE'), findsOneWidget);
      expect(find.text('0 piece'), findsOneWidget);
      expect(find.text('80 piece'), findsOneWidget);
    });
  });

  group('RepeatLastOrder', () {
    test('hides when the customer has no eligible previous order', () {
      final picked = RepeatLastOrder.mostRecent(
        customerId: 'rocky',
        orders: [
          _order(
            id: 'draft',
            customerId: 'rocky',
            status: 'draft',
            orderedAt: '2026-09-20T00:00:00Z',
          ),
          _order(
            id: 'cancelled',
            customerId: 'rocky',
            status: 'cancelled',
            orderedAt: '2026-09-21T00:00:00Z',
          ),
          _order(
            id: 'other',
            customerId: 'someone-else',
            status: 'completed',
            orderedAt: '2026-09-22T00:00:00Z',
          ),
        ],
      );
      expect(picked, isNull);
    });

    test('selects this customer most recent eligible order', () {
      final picked = RepeatLastOrder.mostRecent(
        customerId: 'rocky',
        excludeOrderId: 'editing',
        orders: [
          _order(
            id: 'older',
            customerId: 'rocky',
            status: 'completed',
            orderedAt: '2026-09-01T00:00:00Z',
          ),
          _order(
            id: 'latest',
            customerId: 'rocky',
            status: 'placed',
            orderedAt: '2026-09-18T00:00:00Z',
          ),
          _order(
            id: 'editing',
            customerId: 'rocky',
            status: 'completed',
            orderedAt: '2026-09-26T00:00:00Z',
          ),
        ],
      );
      expect(picked?.id, 'latest');
      expect(picked?.status, OrderStatus.placed);
    });

    test('does not show a repeat source when no customer is selected', () {
      expect(
        RepeatLastOrder.mostRecent(
          customerId: null,
          orders: [
            _order(
              id: 'any',
              customerId: 'rocky',
              status: 'completed',
              orderedAt: '2026-09-18T00:00:00Z',
            ),
          ],
        ),
        isNull,
      );
    });
  });
}
