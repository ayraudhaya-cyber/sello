import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/products/presentation/product_options_section.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/models/user_role.dart';

Map<String, dynamic> _variantRow({
  required String id,
  required String sku,
  String? label,
  num sellingPrice = 100,
  num? unitCost,
  bool isDefault = false,
  bool isActive = true,
  int sortOrder = 0,
}) {
  return {
    'id': id,
    'company_id': 'c1',
    'product_id': 'p1',
    'label': label,
    'sku': sku,
    'selling_price': sellingPrice,
    'unit_cost': ?unitCost,
    'is_default': isDefault,
    'is_active': isActive,
    'sort_order': sortOrder,
  };
}

ProductSummary _productFromRows({
  required List<Map<String, dynamic>> variants,
  required List<Map<String, dynamic>> inventory,
  num sellingPrice = 100,
  num costPrice = 40,
}) {
  return ProductSummary.fromQueryRow({
    'id': 'p1',
    'company_id': 'c1',
    'name': 'Door Lock',
    'sku': 'DL',
    'selling_price': sellingPrice,
    'cost_price': costPrice,
    'is_active': true,
    'inventory': inventory,
    'product_variants': variants,
  });
}

void main() {
  group('Product options UX refinement', () {
    test('1. single product mode stays a simple default variant', () {
      final product = _productFromRows(
        variants: [
          _variantRow(id: 'v1', sku: 'DL', isDefault: true, isActive: true),
        ],
        inventory: [
          {
            'branch_id': 'b1',
            'variant_id': 'v1',
            'quantity': 10,
            'reserved_quantity': 0,
          },
        ],
      );

      expect(product.isMultiOptionProduct, isFalse);
      expect(product.hasMultipleActiveVariants, isFalse);
      expect(product.sellingPrice, 100);
      expect(product.costPrice, 40);
      expect(product.currentStockQuantity, 10);
    });

    test('2. evolving from simple seeds two option rows (multi mode)', () {
      final rows = ProductOptionEditorRow.evolveFromSimple(
        existingVariantId: null,
        sku: 'DL',
        barcode: '',
        sellingPrice: '6000',
        costPrice: '4000',
        isActive: true,
        openingStock: '25',
      );

      expect(rows.length, 2);
      expect(rows.first.isDefault, isTrue);
      expect(rows.first.sku.text, 'DL');
      expect(rows.first.openingStock.text, '25');
      expect(rows.last.isNew, isTrue);
      expect(rows.last.sku.text, isEmpty);
      for (final row in rows) {
        row.dispose();
      }
    });

    test('3. multi-option drafts carry sellable fields on options only', () {
      final drafts = buildEvolvedOptionDrafts(
        existingVariantId: 'v-default',
        firstLabel: '12 inches',
        firstSku: 'DL-12',
        secondLabel: '18 inches',
        secondSku: 'DL-18',
        sellingPrice: 6000,
        unitCost: 4000,
        firstOpeningStock: 25,
        secondOpeningStock: 12,
      );

      final input = ProductUpsertInput(
        name: 'Door Lock',
        sku: 'DL',
        categoryName: 'Hardware',
        sellingPrice: drafts.first.sellingPrice,
        costPrice: drafts.first.unitCost ?? 0,
        currentStockQuantity: 0,
        reorderLevel: 5,
        variants: drafts,
      );

      expect(input.managesMultipleVariants, isTrue);
      expect(input.currentStockQuantity, 0);
      expect(drafts.map((d) => d.label).toList(), ['12 inches', '18 inches']);
      expect(drafts.map((d) => d.openingStock).toList(), [25, 12]);
    });

    test('4. option editor drafts use option name (label field)', () {
      final row = ProductOptionEditorRow(
        label: '12 inches',
        sku: 'DL-12',
        sellingPrice: '6000',
        openingStock: '25',
      );
      final draft = row.toDraft(sortOrder: 0, includeCost: true);
      expect(draft.label, '12 inches');
      expect(draft.sku, 'DL-12');
      row.dispose();
    });

    test('5. opening stock is captured only for new options', () {
      final newRow = ProductOptionEditorRow(
        label: '12 inches',
        sku: 'DL-12',
        sellingPrice: '6000',
        openingStock: '25',
      );
      final existingRow = ProductOptionEditorRow(
        id: 'v-existing',
        label: '18 inches',
        sku: 'DL-18',
        sellingPrice: '6500',
        openingStock: '99',
        currentStockQuantity: 12,
      );

      expect(newRow.toDraft(sortOrder: 0, includeCost: false).openingStock, 25);
      expect(
        existingRow.toDraft(sortOrder: 1, includeCost: false).openingStock,
        isNull,
      );
      newRow.dispose();
      existingRow.dispose();
    });

    test('6. multiple options keep separate opening stock values', () {
      final drafts = buildEvolvedOptionDrafts(
        existingVariantId: 'v1',
        firstLabel: '12 inches',
        firstSku: 'DL-12',
        secondLabel: '18 inches',
        secondSku: 'DL-18',
        sellingPrice: 6000,
        unitCost: 4000,
        firstOpeningStock: 25,
        secondOpeningStock: 12,
      );
      expect(drafts[0].openingStock, 25);
      expect(drafts[1].openingStock, 12);
    });

    test('7. parent stock aggregates ACTIVE option inventory only', () {
      final product = _productFromRows(
        variants: [
          _variantRow(
            id: 'v12',
            sku: 'DL-12',
            label: '12 inches',
            isDefault: true,
            isActive: true,
          ),
          _variantRow(
            id: 'v18',
            sku: 'DL-18',
            label: '18 inches',
            isActive: true,
            sortOrder: 1,
          ),
        ],
        inventory: [
          {
            'branch_id': 'b1',
            'variant_id': 'v12',
            'quantity': 25,
            'reserved_quantity': 0,
          },
          {
            'branch_id': 'b1',
            'variant_id': 'v18',
            'quantity': 12,
            'reserved_quantity': 0,
          },
        ],
      );

      expect(product.currentStockQuantity, 37);
      expect(product.isMultiOptionProduct, isTrue);
      expect(product.activeOptionCount, 2);
    });

    test('8. inactive option stock is excluded from parent aggregate', () {
      final product = _productFromRows(
        variants: [
          _variantRow(
            id: 'v12',
            sku: 'DL-12',
            label: '12 inches',
            isDefault: true,
            isActive: true,
          ),
          _variantRow(
            id: 'v18',
            sku: 'DL-18',
            label: '18 inches',
            isActive: true,
            sortOrder: 1,
          ),
          _variantRow(
            id: 'v24',
            sku: 'DL-24',
            label: '24 inches',
            isActive: false,
            sortOrder: 2,
          ),
        ],
        inventory: [
          {
            'branch_id': 'b1',
            'variant_id': 'v12',
            'quantity': 25,
            'reserved_quantity': 0,
          },
          {
            'branch_id': 'b1',
            'variant_id': 'v18',
            'quantity': 12,
            'reserved_quantity': 0,
          },
          {
            'branch_id': 'b1',
            'variant_id': 'v24',
            'quantity': 8,
            'reserved_quantity': 0,
          },
        ],
      );

      expect(product.currentStockQuantity, 37);
      expect(product.variants.firstWhere((v) => v.id == 'v24').stockQuantity, 8);
    });

    test('9. multi-option parent hides unit price/cost in list helpers', () {
      final product = _productFromRows(
        variants: [
          _variantRow(
            id: 'v12',
            sku: 'DL-12',
            label: '12 inches',
            sellingPrice: 6000,
            isDefault: true,
            isActive: true,
          ),
          _variantRow(
            id: 'v18',
            sku: 'DL-18',
            label: '18 inches',
            sellingPrice: 6500,
            isActive: true,
            sortOrder: 1,
          ),
        ],
        inventory: const [],
        sellingPrice: 6000,
        costPrice: 4000,
      );

      expect(product.isMultiOptionProduct, isTrue);
      // Parent row still carries legacy columns for DB, but UI must not use them.
      expect(product.sellingPrice, 6000);
      expect(product.costPrice, 4000);
    });

    test('10. single-product parent price/cost remain authoritative', () {
      final product = _productFromRows(
        variants: [
          _variantRow(
            id: 'v1',
            sku: 'DL',
            sellingPrice: 6000,
            unitCost: 4000,
            isDefault: true,
            isActive: true,
          ),
        ],
        inventory: const [],
        sellingPrice: 6000,
        costPrice: 4000,
      );

      expect(product.isMultiOptionProduct, isFalse);
      expect(product.sellingPrice, 6000);
      expect(product.costPrice, 4000);
    });

    test('11. unsaved option drafts can be cleared (switch-to-single safety)', () {
      final emptyRows = ProductOptionEditorRow.evolveFromSimple(
        existingVariantId: null,
        sku: 'DL',
        barcode: '',
        sellingPrice: '100',
        costPrice: '40',
        isActive: true,
      );
      // First row has SKU from parent — counts as entered details.
      expect(optionDraftsHaveDetails(emptyRows), isTrue);

      final blankSecondOnly = [
        ProductOptionEditorRow(
          isDefault: true,
          sku: '',
          sellingPrice: '',
        ),
        ProductOptionEditorRow(),
      ];
      expect(optionDraftsHaveDetails(blankSecondOnly), isFalse);

      for (final row in [...emptyRows, ...blankSecondOnly]) {
        row.dispose();
      }
    });

    test('12. saved multi-option products are flagged (no silent conversion)', () {
      final product = _productFromRows(
        variants: [
          _variantRow(
            id: 'v12',
            sku: 'DL-12',
            label: '12 inches',
            isDefault: true,
            isActive: true,
          ),
          _variantRow(
            id: 'v18',
            sku: 'DL-18',
            label: '18 inches',
            isActive: true,
            sortOrder: 1,
          ),
        ],
        inventory: const [],
      );

      expect(product.isMultiOptionProduct, isTrue);
      expect(product.variants.length, 2);
      expect(product.variants.map((v) => v.id).toList(), ['v12', 'v18']);
    });

    test('13. evolving preserves the existing default variant id', () {
      final drafts = buildEvolvedOptionDrafts(
        existingVariantId: 'historical-v1',
        firstLabel: '12 inches',
        firstSku: 'DL-12',
        secondLabel: '18 inches',
        secondSku: 'DL-18',
        sellingPrice: 6000,
        unitCost: 4000,
      );

      expect(drafts.first.id, 'historical-v1');
      expect(drafts.last.id, isNull);
    });

    test('14. order/draft identity stays on variant ids (unchanged contract)', () {
      final drafts = buildEvolvedOptionDrafts(
        existingVariantId: 'v-order-linked',
        firstLabel: '12 inches',
        firstSku: 'DL-12',
        secondLabel: '18 inches',
        secondSku: 'DL-18',
        sellingPrice: 6000,
        unitCost: 4000,
      );
      expect(drafts.first.id, 'v-order-linked');
    });

    test('15. cost visibility: drafts omit unitCost when role cannot view', () {
      expect(UserRole.salesRepresentative.canViewProductCost, isFalse);
      final row = ProductOptionEditorRow(
        label: '12 inches',
        sku: 'DL-12',
        sellingPrice: '6000',
        costPrice: '4000',
      );
      final withoutCost = row.toDraft(sortOrder: 0, includeCost: false);
      final withCost = row.toDraft(sortOrder: 0, includeCost: true);
      expect(withoutCost.unitCost, isNull);
      expect(withCost.unitCost, 4000);
      row.dispose();
    });
  });

  group('Product option remove / deactivate', () {
    test('A. sole draft option cannot be removed', () {
      final rows = [
        ProductOptionEditorRow(label: '12"', sku: 'A'),
      ];
      expect(canRemoveDraftOption(rows: rows, index: 0), isFalse);
      expect(removeDraftOptionAt(rows: rows, index: 0), isNull);
      expect(rows.length, 1);
      rows.first.dispose();
    });

    test('A. second unsaved option can be removed without confirmation when empty', () {
      final rows = ProductOptionEditorRow.evolveFromSimple(
        existingVariantId: null,
        sku: 'DL',
        barcode: '',
        sellingPrice: '100',
        costPrice: '40',
        isActive: true,
      );
      expect(rows.length, 2);
      expect(rows.every((r) => r.isNew), isTrue);
      expect(canRemoveDraftOption(rows: rows, index: 1), isTrue);
      expect(draftOptionRemoveNeedsConfirmation(rows[1]), isFalse);

      final removed = removeDraftOptionAt(rows: rows, index: 1);
      expect(removed, isNotNull);
      expect(rows.length, 1);
      expect(rows.first.sku.text, 'DL');
      removed!.dispose();
      rows.first.dispose();
    });

    test('A. populated unsaved option requires confirmation', () {
      final row = ProductOptionEditorRow(
        label: '24"',
        sku: 'DL-24',
        sellingPrice: '200',
      );
      expect(draftOptionRemoveNeedsConfirmation(row), isTrue);
      row.dispose();
    });

    test('A. removing one draft leaves sibling options unchanged', () {
      final rows = [
        ProductOptionEditorRow(label: '12"', sku: 'A', sellingPrice: '100'),
        ProductOptionEditorRow(label: '20"', sku: 'B', sellingPrice: '200'),
        ProductOptionEditorRow(label: '24"', sku: 'C', sellingPrice: '300'),
      ];
      final removed = removeDraftOptionAt(rows: rows, index: 1);
      expect(removed!.sku.text, 'B');
      expect(rows.map((r) => r.sku.text).toList(), ['A', 'C']);
      removed.dispose();
      for (final row in rows) {
        row.dispose();
      }
    });

    test('B. saved option cannot be physically removed', () {
      final rows = [
        ProductOptionEditorRow(
          id: 'v1',
          label: '12"',
          sku: 'A',
          sellingPrice: '100',
        ),
        ProductOptionEditorRow(
          id: 'v2',
          label: '20"',
          sku: 'B',
          sellingPrice: '200',
        ),
      ];
      expect(rows.first.isNew, isFalse);
      expect(canRemoveDraftOption(rows: rows, index: 0), isFalse);
      expect(canRemoveDraftOption(rows: rows, index: 1), isFalse);
      expect(removeDraftOptionAt(rows: rows, index: 0), isNull);
      expect(rows.length, 2);
      for (final row in rows) {
        row.dispose();
      }
    });

    test('B. deactivating saved option preserves variant id', () {
      final rows = [
        ProductOptionEditorRow(
          id: 'v1',
          isActive: true,
          label: '12"',
          sku: 'A',
          sellingPrice: '100',
        ),
        ProductOptionEditorRow(
          id: 'v2',
          isActive: true,
          label: '20"',
          sku: 'B',
          sellingPrice: '200',
        ),
      ];
      expect(optionDeactivateError(rows: rows, index: 1, nextActive: false), isNull);
      rows[1].isActive = false;
      final draft = rows[1].toDraft(sortOrder: 1, includeCost: false);
      expect(draft.id, 'v2');
      expect(draft.isActive, isFalse);
      expect(draft.sku, 'B');
      expect(draft.openingStock, isNull);
      for (final row in rows) {
        row.dispose();
      }
    });

    test('B. last active option cannot be deactivated', () {
      final rows = [
        ProductOptionEditorRow(
          id: 'v1',
          isActive: true,
          label: '12"',
          sku: 'A',
          sellingPrice: '100',
        ),
        ProductOptionEditorRow(
          id: 'v2',
          isActive: false,
          label: '20"',
          sku: 'B',
          sellingPrice: '200',
        ),
      ];
      expect(
        optionDeactivateError(rows: rows, index: 0, nextActive: false),
        'Keep at least one active sellable option.',
      );
      for (final row in rows) {
        row.dispose();
      }
    });

    test('C. new draft on existing product can be removed; saved stay', () {
      final rows = [
        ProductOptionEditorRow(
          id: 'v1',
          label: '12"',
          sku: 'A',
          sellingPrice: '100',
        ),
        ProductOptionEditorRow(
          id: 'v2',
          label: '20"',
          sku: 'B',
          sellingPrice: '200',
        ),
        ProductOptionEditorRow(
          label: '24"',
          sku: 'C',
          sellingPrice: '300',
        ),
      ];
      expect(canRemoveDraftOption(rows: rows, index: 2), isTrue);
      expect(canRemoveDraftOption(rows: rows, index: 0), isFalse);
      final removed = removeDraftOptionAt(rows: rows, index: 2);
      expect(removed!.isNew, isTrue);
      expect(rows.map((r) => r.id).toList(), ['v1', 'v2']);
      removed.dispose();
      for (final row in rows) {
        row.dispose();
      }
    });

    test('D. switch-to-single helpers still detect draft details', () {
      final empty = [
        ProductOptionEditorRow(isDefault: true),
        ProductOptionEditorRow(),
      ];
      expect(optionDraftsHaveDetails(empty), isFalse);
      final withSku = ProductOptionEditorRow.evolveFromSimple(
        existingVariantId: null,
        sku: 'DL',
        barcode: '',
        sellingPrice: '1',
        costPrice: '0',
        isActive: true,
      );
      expect(optionDraftsHaveDetails(withSku), isTrue);
      for (final row in [...empty, ...withSku]) {
        row.dispose();
      }
    });
  });

  group('Product options UX polish — view/list data', () {
    ProductSummary multiProduct() => _productFromRows(
          variants: [
            _variantRow(
              id: 'v12',
              sku: '26342',
              label: '12"',
              sellingPrice: 120,
              isDefault: true,
              isActive: true,
            ),
            _variantRow(
              id: 'v20',
              sku: '13424',
              label: '20"',
              sellingPrice: 200,
              isActive: true,
              sortOrder: 1,
            ),
            _variantRow(
              id: 'v24',
              sku: '99999',
              label: '24"',
              sellingPrice: 250,
              isActive: false,
              sortOrder: 2,
            ),
          ],
          inventory: [
            {
              'branch_id': 'b1',
              'variant_id': 'v12',
              'quantity': 0,
              'reserved_quantity': 0,
            },
            {
              'branch_id': 'b1',
              'variant_id': 'v20',
              'quantity': 100,
              'reserved_quantity': 0,
            },
            {
              'branch_id': 'b1',
              'variant_id': 'v24',
              'quantity': 8,
              'reserved_quantity': 0,
            },
          ],
          sellingPrice: 120,
          costPrice: 80,
        );

    test('view data: all active options expose label, sku, price, stock', () {
      final product = multiProduct();
      final options = product.activeVariants;

      expect(options.length, 2);
      expect(options.map((o) => o.optionDisplayName).toList(), ['12"', '20"']);
      expect(options.map((o) => o.sku).toList(), ['26342', '13424']);
      expect(options.map((o) => o.sellingPrice).toList(), [120, 200]);
      expect(options.map((o) => o.stockQuantity).toList(), [0, 100]);
    });

    test('view data: aggregate total stock is active-only sum', () {
      final product = multiProduct();
      expect(product.currentStockQuantity, 100);
      expect(product.activeOptionCount, 2);
    });

    test('view data: inactive options excluded from active breakdown', () {
      final product = multiProduct();
      expect(
        product.activeVariants.any((o) => o.sku == '99999'),
        isFalse,
      );
      expect(
        product.variants.firstWhere((o) => o.sku == '99999').stockQuantity,
        8,
      );
    });

    test('optionDisplayName never surfaces Default', () {
      final product = _productFromRows(
        variants: [
          _variantRow(
            id: 'v1',
            sku: 'DL-1',
            label: 'Default',
            isDefault: true,
            isActive: true,
          ),
          _variantRow(
            id: 'v2',
            sku: 'DL-2',
            label: 'Large',
            isActive: true,
            sortOrder: 1,
          ),
        ],
        inventory: const [],
      );
      expect(product.variants.first.optionDisplayName, 'DL-1');
      expect(product.variants.first.optionDisplayName.toLowerCase(), isNot('default'));
      expect(product.variants.last.optionDisplayName, 'Large');
    });

    test('simple products retain single-row display signals', () {
      final product = _productFromRows(
        variants: [
          _variantRow(id: 'v1', sku: 'DL', sellingPrice: 120, isDefault: true),
        ],
        inventory: [
          {
            'branch_id': 'b1',
            'variant_id': 'v1',
            'quantity': 15,
            'reserved_quantity': 0,
          },
        ],
        sellingPrice: 120,
        costPrice: 80,
      );
      expect(product.isMultiOptionProduct, isFalse);
      expect(product.hasMultipleActiveVariants, isFalse);
      expect(product.sellingPrice, 120);
      expect(product.costPrice, 80);
      expect(product.currentStockQuantity, 15);
    });

    test('multi-option parent price/cost stay list-empty (—) candidates', () {
      final product = multiProduct();
      expect(product.isMultiOptionProduct, isTrue);
      // UI shows —; parent columns remain compatibility values only.
      expect(product.sellingPrice, 120);
      expect(product.costPrice, 80);
    });

    test('parent catalog code stays separate from option SKUs', () {
      final product = multiProduct();
      expect(product.sku, 'DL');
      expect(product.activeVariants.map((o) => o.sku).toSet(), {'26342', '13424'});
      expect(product.activeVariants.map((o) => o.sku).contains(product.sku), isFalse);
    });
  });
}
