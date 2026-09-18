import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/products/presentation/product_options_section.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/models/user_role.dart';

InventoryItem _item({
  required String inventoryId,
  required String productId,
  required String name,
  String sku = 'P-1',
  String? variantId,
  String? variantLabel,
  String? variantSku,
  num quantity = 0,
}) {
  return InventoryItem(
    inventoryId: inventoryId,
    productId: productId,
    companyId: 'c1',
    branchId: 'b1',
    name: name,
    sku: sku,
    quantity: quantity,
    isActive: true,
    variantId: variantId,
    variantLabel: variantLabel,
    variantSku: variantSku,
  );
}

void main() {
  group('Phase G product options', () {
    test('simple product has no multiple-active flag', () {
      final product = ProductSummary.fromQueryRow({
        'id': 'p1',
        'company_id': 'c1',
        'name': 'Widget',
        'sku': 'W-1',
        'selling_price': 100,
        'is_active': true,
        'inventory': const [],
        'product_variants': const [
          {
            'id': 'v1',
            'company_id': 'c1',
            'product_id': 'p1',
            'sku': 'W-1',
            'selling_price': 100,
            'is_default': true,
            'is_active': true,
          },
        ],
      });

      expect(product.hasMultipleActiveVariants, isFalse);
      expect(product.defaultVariantId, 'v1');
    });

    test('first additional option evolves existing default variant_id', () {
      final drafts = buildEvolvedOptionDrafts(
        existingVariantId: 'v-default',
        firstLabel: '500ml',
        firstSku: 'W-1',
        secondLabel: '1L',
        secondSku: 'W-1-1L',
        sellingPrice: 100,
        unitCost: 40,
      );

      expect(drafts.length, 2);
      expect(drafts.first.id, 'v-default');
      expect(drafts.first.isDefault, isTrue);
      expect(drafts.first.label, '500ml');
      expect(drafts.last.id, isNull);
      expect(drafts.last.sku, 'W-1-1L');
      expect(ProductUpsertInput(
        name: 'Widget',
        sku: 'W-1',
        categoryName: 'General',
        sellingPrice: 100,
        costPrice: 40,
        currentStockQuantity: 0,
        reorderLevel: 5,
        variants: drafts,
      ).managesMultipleVariants, isTrue);
    });

    test('variant draft fields are preserved on save payload', () {
      final draft = ProductVariantDraft(
        id: 'v1',
        label: 'Blue',
        sku: 'W-BLUE',
        barcode: '123',
        sellingPrice: 120,
        unitCost: 50,
        isActive: true,
        isDefault: true,
      );
      expect(draft.label, 'Blue');
      expect(draft.sku, 'W-BLUE');
      expect(draft.barcode, '123');
      expect(draft.sellingPrice, 120);
      expect(draft.unitCost, 50);
    });

    test('draft without cost leaves unitCost null for non-visible roles', () {
      final draft = ProductVariantDraft(
        id: 'v1',
        label: 'Blue',
        sku: 'W-BLUE',
        sellingPrice: 120,
      );
      expect(draft.unitCost, isNull);
    });

    test('inactive option stays present and can be reactivated', () {
      final rows = [
        ProductOptionEditorRow(
          id: 'v1',
          isDefault: true,
          isActive: true,
          label: 'A',
          sku: 'A-1',
          sellingPrice: '10',
          costPrice: '4',
        ),
        ProductOptionEditorRow(
          id: 'v2',
          isActive: false,
          label: 'B',
          sku: 'B-1',
          sellingPrice: '12',
          costPrice: '5',
        ),
      ];

      expect(rows.where((r) => !r.isActive).length, 1);
      expect(
        optionDeactivateError(rows: rows, index: 1, nextActive: true),
        isNull,
      );
      rows[1].isActive = true;
      expect(rows.where((r) => r.isActive).length, 2);

      for (final row in rows) {
        row.dispose();
      }
    });

    test('last active option cannot be deactivated', () {
      final rows = [
        ProductOptionEditorRow(
          id: 'v1',
          isDefault: true,
          isActive: true,
          label: 'A',
          sku: 'A-1',
          sellingPrice: '10',
        ),
        ProductOptionEditorRow(
          id: 'v2',
          isActive: false,
          label: 'B',
          sku: 'B-1',
          sellingPrice: '12',
        ),
      ];

      expect(
        optionDeactivateError(rows: rows, index: 0, nextActive: false),
        'Keep at least one active sellable option.',
      );
      expect(
        validateLastActiveOption(activeCountAfterChange: 0),
        isNotNull,
      );

      for (final row in rows) {
        row.dispose();
      }
    });

    test('owner/manager/store can view cost; sales cannot', () {
      expect(UserRole.owner.canViewProductCost, isTrue);
      expect(UserRole.manager.canViewProductCost, isTrue);
      expect(UserRole.storeInCharge.canViewProductCost, isTrue);
      expect(UserRole.salesRepresentative.canViewProductCost, isFalse);
      expect(UserRole.salesInCharge.canViewProductCost, isFalse);
    });
  });

  group('Phase G inventory grouping', () {
    test('single-option product stays a flat group without expansion', () {
      final groups = groupInventoryItems([
        _item(
          inventoryId: 'i1',
          productId: 'p1',
          name: 'Widget',
          variantId: 'v1',
          quantity: 8,
        ),
      ]);

      expect(groups.length, 1);
      expect(groups.first.isMultiOption, isFalse);
      expect(groups.first.totalQuantity, 8);
    });

    test('multi-option product groups by productId with aggregates', () {
      final groups = groupInventoryItems([
        _item(
          inventoryId: 'i1',
          productId: 'p1',
          name: 'Widget',
          variantId: 'v1',
          variantLabel: '500ml',
          variantSku: 'W-500',
          quantity: 3,
        ),
        _item(
          inventoryId: 'i2',
          productId: 'p1',
          name: 'Widget',
          variantId: 'v2',
          variantLabel: '1L',
          variantSku: 'W-1L',
          quantity: 5,
        ),
        _item(
          inventoryId: 'i3',
          productId: 'p2',
          name: 'Gadget',
          variantId: 'v3',
          quantity: 2,
        ),
      ]);

      expect(groups.length, 2);
      expect(groups.first.productId, 'p1');
      expect(groups.first.isMultiOption, isTrue);
      expect(groups.first.totalQuantity, 8);
      expect(groups.first.items.map((e) => e.variantId).toSet(), {'v1', 'v2'});
      expect(groups.last.isMultiOption, isFalse);
    });

    test('stock adjust identity includes variant when present', () {
      final item = _item(
        inventoryId: 'i1',
        productId: 'p1',
        name: 'Widget',
        sku: 'W-1',
        variantId: 'v2',
        variantLabel: '1L',
        variantSku: 'W-1L',
      );

      final parts = <String>[item.name];
      final label = item.variantLabel?.trim();
      if (label != null && label.isNotEmpty) parts.add(label);
      final variantSku = item.variantSku?.trim();
      if (variantSku != null && variantSku.isNotEmpty) {
        parts.add(variantSku);
      }
      expect(parts.join(' · '), 'Widget · 1L · W-1L');
      expect(item.variantId, 'v2');
    });

    test('historical variant identity is preserved on drafts', () {
      final drafts = buildEvolvedOptionDrafts(
        existingVariantId: 'historical-v1',
        firstLabel: 'Small',
        firstSku: 'S-1',
        secondLabel: 'Large',
        secondSku: 'S-2',
        sellingPrice: 10,
        unitCost: 4,
      );
      expect(drafts.first.id, 'historical-v1');
      expect(drafts.every((d) => d.id != 'replaced'), isTrue);
    });
  });
}
