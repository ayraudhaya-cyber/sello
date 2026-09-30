import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/products/presentation/product_options_section.dart';
import 'package:sello/features/hub/products/presentation/product_variant_rules.dart';

void main() {
  group('parentFieldRequirementApplies', () {
    test('every configured requirement applies to a normal product', () {
      for (final key in ['size', 'barcode', 'brand', 'color']) {
        expect(
          parentFieldRequirementApplies(fieldKey: key, hasVariants: false),
          isTrue,
        );
      }
    });

    test('Size and barcode are not required on the parent of variants', () {
      expect(
        parentFieldRequirementApplies(fieldKey: 'size', hasVariants: true),
        isFalse,
      );
      expect(
        parentFieldRequirementApplies(fieldKey: 'SIZE', hasVariants: true),
        isFalse,
      );
      expect(
        parentFieldRequirementApplies(
          fieldKey: 'brand',
          hasVariants: true,
          definitionKey: 'size',
        ),
        isFalse,
      );
      expect(
        parentFieldRequirementApplies(fieldKey: 'barcode', hasVariants: true),
        isFalse,
      );
    });

    test('other parent-level requirements still apply to variant products', () {
      expect(
        parentFieldRequirementApplies(fieldKey: 'brand', hasVariants: true),
        isTrue,
      );
      expect(
        parentFieldRequirementApplies(
          fieldKey: 'unit_label',
          hasVariants: true,
        ),
        isTrue,
      );
    });
  });

  group('variant structure rules', () {
    ProductOptionEditorRow row(String sku) =>
        ProductOptionEditorRow(label: 'x', sku: sku, sellingPrice: '10');

    test('a variant product needs at least two variants', () {
      expect(tooFewVariantsError([row('A')]), isNotNull);
      expect(tooFewVariantsError([row('A'), row('B')]), isNull);
    });

    test('repeated item codes are reported case-insensitively', () {
      expect(duplicateOptionCodeError([row('A4'), row('a4')]), contains('a4'));
      expect(duplicateOptionCodeError([row('A4'), row('A6')]), isNull);
      expect(duplicateOptionCodeError([row(''), row('')]), isNull);
    });

    test('optionRowHasErrors flags missing name, code or price', () {
      expect(optionRowHasErrors(row('A4')), isFalse);
      expect(
        optionRowHasErrors(
          ProductOptionEditorRow(label: '', sku: 'A', sellingPrice: '1'),
        ),
        isTrue,
      );
      expect(
        optionRowHasErrors(
          ProductOptionEditorRow(label: 'x', sku: '', sellingPrice: '1'),
        ),
        isTrue,
      );
      expect(
        optionRowHasErrors(
          ProductOptionEditorRow(label: 'x', sku: 'A', sellingPrice: ''),
        ),
        isTrue,
      );
    });

    test('readyVariantCount ignores empty placeholder rows', () {
      expect(
        readyVariantCount([
          ProductOptionEditorRow(sellingPrice: '10'),
          ProductOptionEditorRow(sellingPrice: '10'),
        ]),
        0,
      );
      expect(readyVariantCount([row('A'), ProductOptionEditorRow()]), 1);
      expect(readyVariantCount([row('A'), row('B')]), 2);
    });

    test('footer names the next variant step until two are ready', () {
      expect(
        variantAwarePrimaryLabel(
          isCreate: true,
          hasVariants: false,
          readyCount: 0,
        ),
        'Create Product',
      );
      expect(
        variantAwarePrimaryLabel(
          isCreate: true,
          hasVariants: true,
          readyCount: 0,
        ),
        'Add Variants',
      );
      expect(
        variantAwarePrimaryLabel(
          isCreate: true,
          hasVariants: true,
          readyCount: 1,
        ),
        'Add Another Variant',
      );
      expect(
        variantAwarePrimaryLabel(
          isCreate: true,
          hasVariants: true,
          readyCount: 2,
        ),
        'Create Product',
      );
      expect(
        variantAwarePrimaryLabel(
          isCreate: false,
          hasVariants: true,
          readyCount: 2,
        ),
        'Save Changes',
      );
    });

    test('a suggested code does not count as entered details', () {
      final suggested = ProductOptionEditorRow(
        sku: 'ROLEXTB4',
        skuManuallyEdited: false,
      );
      expect(suggested.hasEnteredDetails, isFalse);
      suggested.skuManuallyEdited = true;
      expect(suggested.hasEnteredDetails, isTrue);
    });
  });

  group('option name suggestions', () {
    test('are unique case-insensitively and keep the first casing', () {
      expect(
        uniqueOptionLabels(const ['4 Inches', '4 inches', 'Black', ' black ']),
        ['4 Inches', 'Black'],
      );
    });

    test('stay quiet until the user types', () {
      expect(
        filterOptionNameSuggestions(
          query: '',
          saved: const ['4 Inches', 'Black'],
        ),
        isEmpty,
      );
    });

    test('prefer prefix matches and are case-insensitive', () {
      expect(
        filterOptionNameSuggestions(
          query: '4',
          saved: const ['4 Inches', '14 Inches', 'Black'],
        ),
        ['4 Inches', '14 Inches'],
      );
      expect(
        filterOptionNameSuggestions(
          query: 'bla',
          saved: const ['4 Inches', 'Black', 'White'],
        ),
        ['Black'],
      );
    });
  });
}
