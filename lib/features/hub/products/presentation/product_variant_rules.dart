import 'package:sello/features/hub/products/presentation/product_options_section.dart';
import 'package:sello/shared/models/product_field.dart';

export 'package:sello/shared/utils/option_name_suggestions.dart';

/// Product Details fields whose value belongs to each variant when the
/// product has variants. The parent never has to supply them.
const Set<String> variantLevelFieldKeys = {'size', 'barcode'};

/// Whether a configured "required" rule for a parent-level field applies.
///
/// Size and barcode are variant-level for variant products, so a required
/// Size on the parent must not block saving when the variants carry the
/// distinguishing option themselves.
bool parentFieldRequirementApplies({
  required String fieldKey,
  required bool hasVariants,
  String? definitionKey,
}) {
  if (!hasVariants) return true;
  return !isVariantLevelFieldKey(fieldKey) &&
      !isVariantLevelFieldKey(definitionKey);
}

bool isVariantLevelFieldKey(String? key) {
  final normalized = key?.trim().toLowerCase() ?? '';
  return variantLevelFieldKeys.contains(normalized);
}

bool isVariantLevelProductField(CompanyProductField field) {
  return isVariantLevelFieldKey(field.fieldKey) ||
      isVariantLevelFieldKey(field.definition.key);
}

/// Shown when a variant product has fewer than two options.
const String kTooFewVariantsMessage =
    'Add at least two variants, or turn off "This product has variants".';

String? tooFewVariantsError(List<ProductOptionEditorRow> rows) {
  return rows.length < 2 ? kTooFewVariantsMessage : null;
}

/// Options that already have a name, item code and selling price.
///
/// Empty placeholder rows created when variants are turned on do not count —
/// the footer should still send the user to the Variants tab.
int readyVariantCount(List<ProductOptionEditorRow> rows) {
  return rows.where((row) => !optionRowHasErrors(row)).length;
}

/// Footer label for Add / Edit Product. Incomplete variant products name the
/// next step instead of implying the catalog row can be created.
String variantAwarePrimaryLabel({
  required bool isCreate,
  required bool hasVariants,
  required int readyCount,
}) {
  if (hasVariants && readyCount < 2) {
    return readyCount <= 0 ? 'Add Variants' : 'Add Another Variant';
  }
  return isCreate ? 'Create Product' : 'Save Changes';
}

/// Item codes must differ across options of the same product (case-insensitive).
/// Returns a message naming the first repeated code, or null.
String? duplicateOptionCodeError(List<ProductOptionEditorRow> rows) {
  final seen = <String>{};
  for (final row in rows) {
    final code = row.sku.text.trim();
    if (code.isEmpty) continue;
    if (!seen.add(code.toUpperCase())) {
      return 'Item code "$code" is used by more than one variant. '
          'Each variant needs its own item code.';
    }
  }
  return null;
}

/// True when a variant row has something the form validators would reject.
bool optionRowHasErrors(ProductOptionEditorRow row) {
  if (row.label.text.trim().isEmpty) return true;
  if (row.sku.text.trim().isEmpty) return true;
  final selling = num.tryParse(row.sellingPrice.text.trim());
  if (selling == null || selling < 0) return true;
  final cost = row.costPrice.text.trim();
  if (cost.isNotEmpty) {
    final parsed = num.tryParse(cost);
    if (parsed == null || parsed < 0) return true;
  }
  final opening = row.openingStock.text.trim();
  if (opening.isNotEmpty) {
    final parsed = num.tryParse(opening);
    if (parsed == null || parsed < 0) return true;
  }
  return false;
}
