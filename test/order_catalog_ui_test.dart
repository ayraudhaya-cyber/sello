import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_product_views.dart';
import 'package:sello/features/orders/presentation/widgets/product_layout_switcher.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/services/catalog/sales_catalog_layout_preferences.dart';
import 'package:sello/shared/models/product_summary.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );
}

ProductSummary _product({String name = 'Premium Stainless Steel Door Lock'}) {
  return ProductSummary(
    id: 'p1',
    companyId: 'co1',
    name: name,
    sku: 'SKU-1',
    sellingPrice: 1200,
    costPrice: 800,
    currentStockQuantity: 50,
    isActive: true,
    categoryId: 'c1',
    brand: 'Brand',
    unitLabel: 'unit',
    attributes: const {},
  );
}

class _QuantityHarness extends StatefulWidget {
  const _QuantityHarness({
    required this.initial,
    this.showRemove = false,
  });

  final num initial;
  final bool showRemove;

  @override
  State<_QuantityHarness> createState() => _QuantityHarnessState();
}

class _QuantityHarnessState extends State<_QuantityHarness> {
  late num value;

  @override
  void initState() {
    super.initState();
    value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return ProductQuantityControl(
      value: value,
      allowZero: true,
      showRemove: widget.showRemove,
      onChanged: (next) => setState(() => value = next),
    );
  }
}

void main() {
  group('ProductQuantityControl', () {
    testWidgets('increments and decrements quantity', (tester) async {
      await tester.pumpWidget(_wrap(const _QuantityHarness(initial: 2)));

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      final state = tester.state<_QuantityHarnessState>(
        find.byType(_QuantityHarness),
      );
      expect(state.value, 3);

      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(state.value, 2);
    });

    testWidgets('remove sets quantity to zero', (tester) async {
      await tester.pumpWidget(
        _wrap(const _QuantityHarness(initial: 5, showRemove: true)),
      );

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      final state = tester.state<_QuantityHarnessState>(
        find.byType(_QuantityHarness),
      );
      expect(state.value, 0);
    });

    testWidgets('direct entry updates quantity', (tester) async {
      await tester.pumpWidget(_wrap(const _QuantityHarness(initial: 3)));

      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();

      expect(find.text('Enter quantity'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '100');
      await tester.tap(find.text('Update quantity'));
      await tester.pumpAndSettle();

      final state = tester.state<_QuantityHarnessState>(
        find.byType(_QuantityHarness),
      );
      expect(state.value, 100);
    });

    testWidgets('direct entry rejects quantity above max', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProductQuantityControl(
            value: 20,
            allowZero: true,
            maxQuantity: 23,
            onIncreaseBlocked: () {},
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '30');
      await tester.tap(find.text('Update quantity'));
      await tester.pumpAndSettle();

      expect(find.text('Only 23 available'), findsOneWidget);
    });

    testWidgets('plus is disabled at max quantity', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProductQuantityControl(
            value: 23,
            allowZero: true,
            maxQuantity: 23,
            onChanged: (_) {},
          ),
        ),
      );

      final addButton = find.byIcon(Icons.add_rounded);
      await tester.tap(addButton);
      await tester.pump();
      // Value unchanged — still shows 23
      expect(find.text('23'), findsOneWidget);
    });

    testWidgets('direct entry allows zero when configured', (tester) async {
      await tester.pumpWidget(_wrap(const _QuantityHarness(initial: 5)));

      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.tap(find.text('Update quantity'));
      await tester.pumpAndSettle();

      final state = tester.state<_QuantityHarnessState>(
        find.byType(_QuantityHarness),
      );
      expect(state.value, 0);
    });
  });

  group('ProductLayoutSwitcher', () {
    testWidgets('switches layout mode', (tester) async {
      ProductCatalogLayoutMode mode = ProductCatalogLayoutMode.gridTwo;
      await tester.pumpWidget(
        _wrap(
          ProductLayoutSwitcher(
            mode: mode,
            onChanged: (next) => mode = next,
          ),
        ),
      );

      await tester.tap(find.byTooltip('List view'));
      await tester.pump();
      expect(mode, ProductCatalogLayoutMode.list);
    });
  });

  group('OrderCatalogGridCard', () {
    testWidgets('truncates long names to two lines with fixed name area',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 180,
            child: OrderCatalogGridCard(
              product: _product(),
              currencySymbol: 'Rs',
              quantity: 0,
              onAdd: () {},
              onQuantityChanged: (_) {},
              onOpenPhotos: () {},
            ),
          ),
        ),
      );

      final nameFinder = find.text('Premium Stainless Steel Door Lock');
      expect(nameFinder, findsOneWidget);
      final text = tester.widget<Text>(nameFinder);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);

      final sizedBoxes = tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(OrderCatalogGridCard),
          matching: find.byType(SizedBox),
        ),
      );
      expect(
        sizedBoxes.any((box) => box.height == kOrderCatalogNameAreaHeight),
        isTrue,
      );
    });
  });

  group('SalesCatalogLayoutPreferencesStore', () {
    test('round-trips layout mode storage keys', () {
      expect(
        ProductCatalogLayoutModeX.fromStorage('gridOne'),
        ProductCatalogLayoutMode.gridOne,
      );
      expect(
        ProductCatalogLayoutModeX.fromStorage('list'),
        ProductCatalogLayoutMode.list,
      );
      expect(
        ProductCatalogLayoutModeX.fromStorage(null),
        ProductCatalogLayoutMode.gridTwo,
      );
    });
  });
}
