import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/features/hub/products/application/hub_products_provider.dart';
import 'package:sello/features/hub/products/presentation/hub_products_page.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_upsert_input.dart';

class _FakeRepository implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHubProducts extends HubProductsNotifier {
  final List<ProductUpsertInput> saved = [];

  @override
  HubProductsState build() => const HubProductsState();

  @override
  Future<String?> saveProduct({
    required ProductUpsertInput input,
    List<MediaGalleryDraft> gallery = const [],
    void Function(MediaUploadProgress progress)? onMediaProgress,
  }) async {
    saved.add(input);
    return null;
  }
}

class _FakeFieldConfig extends ProductFieldConfigNotifier {
  _FakeFieldConfig(this.config);

  final ProductFieldConfig config;

  @override
  Future<ProductFieldConfig> build() async => config;
}

ProductFieldConfig _sizeRequiredConfig({bool required = true}) {
  return ProductFieldConfig(
    fields: [
      CompanyProductField(
        id: 'f-size',
        companyId: 'c1',
        fieldKey: 'size',
        enabled: true,
        required: required,
        showInList: false,
        showInCatalog: true,
        sortOrder: 10,
        definition: const ProductFieldDefinition(
          key: 'size',
          label: 'Size',
          fieldType: ProductFieldType.text,
          storage: ProductFieldStorage.attribute,
        ),
      ),
    ],
  );
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _text(WidgetTester tester, Finder finder) =>
    tester.widget<TextFormField>(finder).controller!.text;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder finder, String value) async {
  await tester.enterText(finder, value);
  await _settle(tester);
}

Future<_FakeHubProducts> _openEditor(
  WidgetTester tester, {
  Set<String> existingCodes = const {},
  ProductFieldConfig? config,
  List<String> optionNames = const [],
}) async {
  tester.view.physicalSize = const Size(1500, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final hub = _FakeHubProducts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(null),
        hubProductsProvider.overrideWith(() => hub),
        productFieldConfigProvider.overrideWith(
          () => _FakeFieldConfig(config ?? _sizeRequiredConfig()),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ProductEditorDialog(
                    categories: const [],
                    repository: _FakeRepository(),
                    photoPanelBuilder: (_) => const SizedBox(height: 40),
                    skuLookup: (prefix) async => {
                      for (final code in existingCodes)
                        if (code.startsWith(prefix.toUpperCase())) code,
                    },
                    optionNameLookup: () async => optionNames,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return hub;
}

Future<void> _fillSimpleBasics(WidgetTester tester) async {
  await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
  await _type(tester, _field('New category name'), 'Hardware');
}

Future<void> _enableVariants(WidgetTester tester) async {
  await tester.tap(find.text('This product has variants'));
  await tester.pumpAndSettle();
}

Future<void> _openVariantsTab(WidgetTester tester) async {
  await tester.tap(find.textContaining('Variants ('));
  await tester.pumpAndSettle();
}

Future<void> _openParentTab(WidgetTester tester) async {
  await tester.tap(find.text('Parent Details'));
  await tester.pumpAndSettle();
}

Future<void> _create(WidgetTester tester) async {
  await tester.tap(find.text('Create Product'));
  await tester.pumpAndSettle();
}

void main() {
  group('A. normal product without variants', () {
    testWidgets('shows no variant UI and suggests an item code from the name', (
      tester,
    ) async {
      await _openEditor(tester);

      expect(find.text('This product has variants'), findsOneWidget);
      expect(find.text('Parent Details'), findsNothing);
      expect(find.textContaining('Variants ('), findsNothing);
      expect(find.text('Add another option'), findsNothing);

      await _type(tester, _field('Product name'), 'ROLEX TOWER BOLT');
      expect(_text(tester, _field('Item code')), 'ROLEXTB');
    });

    testWidgets('Create Product remains the primary action', (tester) async {
      await _openEditor(tester);
      expect(find.text('Create Product'), findsOneWidget);
      expect(find.text('Add Variants'), findsNothing);
    });

    testWidgets('Cost price is shown before Selling price', (tester) async {
      await _openEditor(tester);

      final cost = tester.getTopLeft(_field('Cost price'));
      final selling = tester.getTopLeft(_field('Selling price'));
      expect(cost.dx, lessThan(selling.dx));
    });

    testWidgets('still requires Size when the product has no variants', (
      tester,
    ) async {
      final hub = await _openEditor(tester);
      await _fillSimpleBasics(tester);
      await _type(tester, _field('Cost price'), '40');
      await _type(tester, _field('Selling price'), '60');
      await _type(tester, _field('Opening stock'), '5');

      await _create(tester);
      expect(hub.saved, isEmpty);

      await _type(tester, _field('Size'), '4 inch');
      await _create(tester);

      expect(hub.saved, hasLength(1));
      final input = hub.saved.single;
      expect(input.sku, 'ROLEXTB');
      expect(input.sellingPrice, 60);
      expect(input.costPrice, 40);
      expect(input.currentStockQuantity, 5);
      expect(input.variants, isNull);
      expect(input.attributes['size'], '4 inch');
    });
  });

  group('B. product with variants', () {
    testWidgets('splits into Parent Details and Variants without data loss', (
      tester,
    ) async {
      await _openEditor(tester);
      await _enableVariants(tester);

      expect(find.text('Parent Details'), findsOneWidget);
      expect(find.text('Variants (2)'), findsOneWidget);
      expect(find.text('Handled in Variants'), findsOneWidget);
      expect(find.text('Parent item code'), findsOneWidget);
      expect(tester.widget<TextFormField>(_field('Size')).enabled, isFalse);
      expect(
        tester.widget<TextFormField>(_field('Cost price')).enabled,
        isFalse,
      );
      expect(
        tester.widget<TextFormField>(_field('Selling price')).enabled,
        isFalse,
      );

      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _openVariantsTab(tester);
      expect(find.text('Add another option'), findsWidgets);
      await _type(tester, _field('Option name').first, '4 inches');

      await _openParentTab(tester);
      expect(_text(tester, _field('Product name')), 'Rolex Tower Bolt');
      expect(_text(tester, _field('Parent item code')), 'ROLEXTB');

      await _openVariantsTab(tester);
      expect(_text(tester, _field('Option name').first), '4 inches');
      expect(_text(tester, _field('Item code').first), 'ROLEXTB4');
    });

    testWidgets('does not require the parent Size when variants exist', (
      tester,
    ) async {
      final hub = await _openEditor(tester);
      await _enableVariants(tester);
      expect(tester.widget<TextFormField>(_field('Size')).enabled, isFalse);
      expect(
        tester.widget<TextFormField>(_field('Cost price')).enabled,
        isFalse,
      );
      expect(
        tester.widget<TextFormField>(_field('Selling price')).enabled,
        isFalse,
      );
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('New category name'), 'Hardware');

      await _openVariantsTab(tester);
      await _type(tester, _field('Option name').at(0), '4 inches');
      await _type(tester, _field('Option name').at(1), '6 inches');
      await _type(tester, _field('Selling price').at(0), '60');
      await _type(tester, _field('Selling price').at(1), '90');
      await _type(tester, _field('Cost price').at(0), '40');
      await _type(tester, _field('Cost price').at(1), '55');

      await _create(tester);

      expect(find.text('Size is required.'), findsNothing);
      expect(hub.saved, hasLength(1));
      final input = hub.saved.single;
      expect(input.sku, 'ROLEXTB');
      expect(input.managesMultipleVariants, isTrue);
      expect(input.variants!.map((v) => v.label), ['4 inches', '6 inches']);
      expect(input.variants!.map((v) => v.sku), ['ROLEXTB4', 'ROLEXTB6']);
      expect(input.variants!.map((v) => v.sellingPrice), [60, 90]);
      expect(input.variants!.map((v) => v.unitCost), [40, 55]);
      expect(input.attributes.containsKey('size'), isFalse);
      expect(input.barcode, isEmpty);
    });

    testWidgets('turning variants off restores the simple flow', (
      tester,
    ) async {
      await _openEditor(tester);
      await _enableVariants(tester);
      expect(find.text('Parent Details'), findsOneWidget);

      await _enableVariants(tester);
      expect(find.text('Parent Details'), findsNothing);
      expect(_field('Selling price'), findsOneWidget);
      expect(_field('Size'), findsOneWidget);
    });

    testWidgets('needs at least two variants', (tester) async {
      final hub = await _openEditor(tester);
      await _enableVariants(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('New category name'), 'Hardware');

      await _openVariantsTab(tester);
      await _type(tester, _field('Option name').at(0), '4 inches');
      await _type(tester, _field('Selling price').at(0), '60');
      await _type(tester, _field('Option name').at(1), '6 inches');
      await _type(tester, _field('Selling price').at(1), '90');
      await tester.tap(find.byTooltip('Remove option').first);
      await tester.pumpAndSettle();
      if (find.text('Remove option').evaluate().isNotEmpty) {
        await tester.tap(find.text('Remove option'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Create Product'), findsNothing);
      expect(find.text('Add Another Variant'), findsOneWidget);
      await tester.tap(find.text('Add Another Variant'));
      await tester.pumpAndSettle();

      expect(hub.saved, isEmpty);
      expect(find.text('Add another option'), findsWidgets);
    });

    testWidgets(
      'Add Variants opens the Variants tab without creating a product',
      (tester) async {
        final hub = await _openEditor(tester);
        await _enableVariants(tester);
        await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
        await _type(tester, _field('New category name'), 'Hardware');

        expect(find.text('Create Product'), findsNothing);
        expect(find.text('Add Variants'), findsOneWidget);

        await tester.tap(find.text('Add Variants'));
        await tester.pumpAndSettle();

        expect(hub.saved, isEmpty);
        expect(find.text('Add another option'), findsWidgets);
        expect(_field('Option name').evaluate().length, greaterThanOrEqualTo(2));

        await _openParentTab(tester);
        expect(_text(tester, _field('Product name')), 'Rolex Tower Bolt');
        expect(_text(tester, _field('Parent item code')), 'ROLEXTB');
      },
    );

    testWidgets(
      'one complete variant still requires adding another',
      (tester) async {
        final hub = await _openEditor(tester);
        await _enableVariants(tester);
        await _fillSimpleBasics(tester);
        await _openVariantsTab(tester);
        await _type(tester, _field('Option name').at(0), '4 inches');
        await _type(tester, _field('Selling price').at(0), '60');
        await _openParentTab(tester);

        expect(find.text('Create Product'), findsNothing);
        expect(find.text('Add Another Variant'), findsOneWidget);

        await tester.tap(find.text('Add Another Variant'));
        await tester.pumpAndSettle();

        expect(hub.saved, isEmpty);
        expect(_text(tester, _field('Option name').first), '4 inches');
        await _openParentTab(tester);
        expect(_text(tester, _field('Product name')), 'Rolex Tower Bolt');
      },
    );
  });

  group('C. multiple variants', () {
    testWidgets('Add another option adds a third variant with its own code', (
      tester,
    ) async {
      final hub = await _openEditor(tester);
      await _enableVariants(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('New category name'), 'Hardware');
      await _openVariantsTab(tester);

      await tester.tap(find.text('Add another option').first);
      await tester.pumpAndSettle();
      expect(find.text('Variants (3)'), findsOneWidget);

      for (final entry in {
        0: '4 inches',
        1: '6 inches',
        2: '8 inches',
      }.entries) {
        await _type(tester, _field('Option name').at(entry.key), entry.value);
        await _type(tester, _field('Selling price').at(entry.key), '10');
      }
      await _create(tester);

      final input = hub.saved.single;
      expect(input.variants!.map((v) => v.sku), [
        'ROLEXTB4',
        'ROLEXTB6',
        'ROLEXTB8',
      ]);
    });
  });

  group('duplicate and generated-code conflicts', () {
    testWidgets('parent code avoids an existing product code', (tester) async {
      await _openEditor(tester, existingCodes: {'ROLEXTB'});
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      expect(_text(tester, _field('Item code')), 'ROLEXTB2');
    });

    testWidgets('variant codes avoid existing codes and each other', (
      tester,
    ) async {
      final hub = await _openEditor(tester, existingCodes: {'ROLEXTB4'});
      await _enableVariants(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('New category name'), 'Hardware');
      await _openVariantsTab(tester);

      await _type(tester, _field('Option name').at(0), '4 inches');
      await _type(tester, _field('Option name').at(1), '4 INCH');
      expect(_text(tester, _field('Item code').at(0)), 'ROLEXTB4A');
      expect(_text(tester, _field('Item code').at(1)), 'ROLEXTB4B');

      await _type(tester, _field('Selling price').at(0), '10');
      await _type(tester, _field('Selling price').at(1), '10');
      await _create(tester);
      expect(
        hub.saved.single.variants!.map((v) => v.sku).toSet(),
        hasLength(2),
      );
    });

    testWidgets('identical hand-typed variant codes are rejected', (
      tester,
    ) async {
      final hub = await _openEditor(tester);
      await _enableVariants(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('New category name'), 'Hardware');
      await _openVariantsTab(tester);

      await _type(tester, _field('Option name').at(0), '4 inches');
      await _type(tester, _field('Option name').at(1), '6 inches');
      await _type(tester, _field('Item code').at(0), 'same');
      await _type(tester, _field('Item code').at(1), 'SAME');
      await _type(tester, _field('Selling price').at(0), '10');
      await _type(tester, _field('Selling price').at(1), '10');
      await _create(tester);

      expect(hub.saved, isEmpty);
      expect(find.textContaining('more than one variant'), findsOneWidget);
    });
  });

  group('manual edits are preserved', () {
    testWidgets('parent code is not regenerated after a manual edit', (
      tester,
    ) async {
      await _openEditor(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      expect(_text(tester, _field('Item code')), 'ROLEXTB');

      await _type(tester, _field('Item code'), 'MYCODE');
      await _type(tester, _field('Product name'), 'Completely Different Name');
      expect(_text(tester, _field('Item code')), 'MYCODE');
    });

    testWidgets('clearing the code lets the suggestion return', (tester) async {
      await _openEditor(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('Item code'), 'MYCODE');
      await _type(tester, _field('Item code'), '');
      expect(_text(tester, _field('Item code')), 'ROLEXTB');
    });

    testWidgets('variant codes follow the parent until edited by hand', (
      tester,
    ) async {
      await _openEditor(tester);
      await _enableVariants(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _openVariantsTab(tester);
      await _type(tester, _field('Option name').at(0), '4 inches');
      await _type(tester, _field('Option name').at(1), '6 inches');
      await _type(tester, _field('Item code').at(1), 'HAND-6');

      await _openParentTab(tester);
      await _type(tester, _field('Parent item code'), 'BOLT');
      await _openVariantsTab(tester);

      expect(_text(tester, _field('Item code').at(0)), 'BOLT4');
      expect(_text(tester, _field('Item code').at(1)), 'HAND-6');

      await _type(tester, _field('Option name').at(1), '10 inches');
      expect(_text(tester, _field('Item code').at(1)), 'HAND-6');
    });
  });

  group('C. variant option name autocomplete', () {
    testWidgets('suggests company option names case-insensitively', (
      tester,
    ) async {
      await _openEditor(
        tester,
        optionNames: const ['4 Inches', '6 Inches', 'Black', 'White'],
      );
      await _enableVariants(tester);
      await _openVariantsTab(tester);

      await tester.enterText(_field('Option name').at(0), '4');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('4 Inches'), findsOneWidget);

      await tester.tap(find.text('4 Inches'));
      await tester.pumpAndSettle();
      expect(_text(tester, _field('Option name').at(0)), '4 Inches');

      await tester.enterText(_field('Option name').at(1), 'bla');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Black'), findsOneWidget);
      await tester.tap(find.text('Black'));
      await tester.pumpAndSettle();
      expect(_text(tester, _field('Option name').at(1)), 'Black');
    });

    testWidgets('allows a new option name when nothing matches', (
      tester,
    ) async {
      final hub = await _openEditor(
        tester,
        optionNames: const ['4 Inches', 'Black'],
      );
      await _enableVariants(tester);
      await _type(tester, _field('Product name'), 'Rolex Tower Bolt');
      await _type(tester, _field('New category name'), 'Hardware');
      await _openVariantsTab(tester);

      await tester.enterText(_field('Option name').at(0), 'xyzzy');
      await tester.pump();
      expect(find.text('4 Inches'), findsNothing);
      expect(find.text('Black'), findsNothing);

      await _type(tester, _field('Option name').at(0), 'Custom Cut');
      await _type(tester, _field('Option name').at(1), 'Other Cut');
      await _type(tester, _field('Selling price').at(0), '10');
      await _type(tester, _field('Selling price').at(1), '10');
      await _create(tester);

      expect(hub.saved.single.variants!.map((v) => v.label), [
        'Custom Cut',
        'Other Cut',
      ]);
    });
  });
}
