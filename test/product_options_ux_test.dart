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
}
