import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/option_name_suggestions.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Mutable editor state for one sellable option row.
class ProductOptionEditorRow {
  ProductOptionEditorRow({
    this.id,
    this.isDefault = false,
    this.isActive = true,
    this.currentStockQuantity,
    String label = '',
    String sku = '',
    String barcode = '',
    String sellingPrice = '',
    String costPrice = '',
    String openingStock = '',
    bool? skuManuallyEdited,
  }) : skuManuallyEdited = skuManuallyEdited ?? sku.trim().isNotEmpty,
       label = TextEditingController(text: label),
       sku = TextEditingController(text: sku),
       barcode = TextEditingController(text: barcode),
       sellingPrice = TextEditingController(text: sellingPrice),
       costPrice = TextEditingController(text: costPrice),
       openingStock = TextEditingController(text: openingStock);

  String? id;
  bool isDefault;
  bool isActive;

  /// True once the user typed (or a saved option supplied) this item code.
  /// While false the code is a suggestion that may follow the option name
  /// and the parent code; once true it is never overwritten.
  bool skuManuallyEdited;

  /// Live inventory qty for an existing option (display only — never overwritten
  /// by the Opening stock field).
  final num? currentStockQuantity;

  final TextEditingController label;
  final TextEditingController sku;
  final TextEditingController barcode;
  final TextEditingController sellingPrice;
  final TextEditingController costPrice;
  final TextEditingController openingStock;

  bool get isNew => id == null || id!.trim().isEmpty;

  bool get hasEnteredDetails {
    return label.text.trim().isNotEmpty ||
        (skuManuallyEdited && sku.text.trim().isNotEmpty) ||
        barcode.text.trim().isNotEmpty ||
        (isNew &&
            openingStock.text.trim().isNotEmpty &&
            openingStock.text.trim() != '0');
  }

  void dispose() {
    label.dispose();
    sku.dispose();
    barcode.dispose();
    sellingPrice.dispose();
    costPrice.dispose();
    openingStock.dispose();
  }

  ProductVariantDraft toDraft({
    required int sortOrder,
    required bool includeCost,
  }) {
    final opening = num.tryParse(openingStock.text.trim());
    return ProductVariantDraft(
      id: id,
      label: label.text.trim(),
      sku: sku.text.trim(),
      barcode: barcode.text.trim(),
      sellingPrice: num.tryParse(sellingPrice.text.trim()) ?? 0,
      unitCost: includeCost ? (num.tryParse(costPrice.text.trim()) ?? 0) : null,
      isActive: isActive,
      isDefault: isDefault,
      sortOrder: sortOrder,
      openingStock: isNew ? (opening ?? 0) : null,
    );
  }

  static ProductOptionEditorRow fromVariant(
    ProductVariant variant, {
    num? unitCost,
  }) {
    return ProductOptionEditorRow(
      id: variant.id,
      isDefault: variant.isDefault,
      isActive: variant.isActive,
      currentStockQuantity: variant.stockQuantity,
      label: variant.label ?? '',
      sku: variant.sku,
      barcode: variant.barcode ?? '',
      sellingPrice: variant.sellingPrice.toString(),
      costPrice: (unitCost ?? variant.unitCost ?? 0).toString(),
    );
  }

  /// Seeds the evolved first option + a blank second option from parent fields.
  static List<ProductOptionEditorRow> evolveFromSimple({
    required String? existingVariantId,
    required String sku,
    required String barcode,
    required String sellingPrice,
    required String costPrice,
    required bool isActive,
    String openingStock = '',
  }) {
    return [
      ProductOptionEditorRow(
        id: existingVariantId,
        isDefault: true,
        isActive: isActive,
        label: '',
        sku: sku,
        barcode: barcode,
        sellingPrice: sellingPrice,
        costPrice: costPrice,
        // Bound default on create still accepts opening stock once.
        openingStock: existingVariantId == null ? openingStock : '',
        currentStockQuantity: existingVariantId == null ? null : null,
      ),
      ProductOptionEditorRow(
        isDefault: false,
        isActive: true,
        label: '',
        sku: '',
        barcode: '',
        sellingPrice: sellingPrice,
        costPrice: costPrice,
      ),
    ];
  }
}

/// Sellable options section — shown only when the product manages multiple options.
class ProductOptionsEditorSection extends StatelessWidget {
  const ProductOptionsEditorSection({
    super.key,
    required this.rows,
    required this.showCost,
    required this.errorText,
    required this.onChanged,
    required this.onAddOption,
    required this.onToggleActive,
    this.onRemoveOption,
    this.onOptionNameChanged,
    this.onItemCodeEdited,
    this.lockedNote,
    this.optionNameSuggestions = const [],
  });

  final List<ProductOptionEditorRow> rows;
  final bool showCost;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback onAddOption;
  final void Function(int index, bool active) onToggleActive;
  final void Function(int index)? onRemoveOption;

  /// Fired when the option name changes (item-code suggestions follow it).
  final void Function(ProductOptionEditorRow row)? onOptionNameChanged;

  /// Fired when the user edits an item code by hand (or clears it).
  final void Function(ProductOptionEditorRow row)? onItemCodeEdited;

  /// Shown when the product cannot go back to a single-product setup.
  final String? lockedNote;
  final List<String> optionNameSuggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Variants',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Each variant is a separate sellable unit with its own '
                      'item code, price and stock.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SelloButton(
                label: 'Add another option',
                icon: Icons.add_rounded,
                variant: SelloButtonVariant.secondary,
                size: SelloButtonSize.small,
                onPressed: onAddOption,
              ),
            ],
          ),
          if (lockedNote != null) ...[
            const SizedBox(height: 8),
            Text(
              lockedNote!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _OptionCard(
              index: i,
              row: rows[i],
              showCost: showCost,
              canRemove: canRemoveDraftOption(rows: rows, index: i),
              onChanged: onChanged,
              onToggleActive: (active) => onToggleActive(i, active),
              onRemove: onRemoveOption == null
                  ? null
                  : () => onRemoveOption!(i),
              onNameChanged: onOptionNameChanged,
              onCodeEdited: onItemCodeEdited,
              optionNameSuggestions: optionNameSuggestions,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SelloButton(
              label: 'Add another option',
              icon: Icons.add_rounded,
              variant: SelloButtonVariant.ghost,
              size: SelloButtonSize.small,
              onPressed: onAddOption,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.index,
    required this.row,
    required this.showCost,
    required this.canRemove,
    required this.onChanged,
    required this.onToggleActive,
    this.onRemove,
    this.onNameChanged,
    this.onCodeEdited,
    this.optionNameSuggestions = const [],
  });

  final int index;
  final ProductOptionEditorRow row;
  final bool showCost;
  final bool canRemove;
  final VoidCallback onChanged;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback? onRemove;
  final void Function(ProductOptionEditorRow row)? onNameChanged;
  final void Function(ProductOptionEditorRow row)? onCodeEdited;
  final List<String> optionNameSuggestions;

  @override
  Widget build(BuildContext context) {
    final muted = !row.isActive;
    return Opacity(
      opacity: muted ? 0.72 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.outlineSubtle),
          boxShadow: AppShadows.level1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Option ${index + 1}',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (canRemove && onRemove != null) ...[
                  IconButton(
                    onPressed: onRemove,
                    tooltip: 'Remove option',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                SizedBox(
                  width: 136,
                  child: SelloStatusToggle(
                    value: row.isActive,
                    onChanged: onToggleActive,
                    label: 'Active',
                    helper:
                        'Inactive options stay in history but cannot be sold.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelloFormRow(
              left: SelloAutocompleteField(
                key: ObjectKey(row),
                value: row.label.text,
                label: 'Option name',
                required: true,
                hint: 'e.g. 12 inches, Black, Large',
                suggestions: optionNameSuggestions,
                suggestWhenEmpty: false,
                suggestionFilter: (query, saved) =>
                    filterOptionNameSuggestions(query: query, saved: saved),
                onChanged: (value) {
                  if (row.label.text != value) row.label.text = value;
                  onNameChanged?.call(row);
                  onChanged();
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter an option name.';
                  }
                  return null;
                },
              ),
              right: SelloTextField(
                controller: row.sku,
                label: 'Item code',
                required: true,
                onChanged: (value) {
                  row.skuManuallyEdited = value.trim().isNotEmpty;
                  onCodeEdited?.call(row);
                  onChanged();
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter an item code.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            if (showCost)
              SelloFormRow(
                left: SelloTextField(
                  controller: row.costPrice,
                  label: 'Cost price',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => onChanged(),
                  validator: _validateOptionalPrice,
                ),
                right: SelloTextField(
                  controller: row.sellingPrice,
                  label: 'Selling price',
                  required: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => onChanged(),
                  validator: _validatePrice,
                ),
              )
            else
              SelloTextField(
                controller: row.sellingPrice,
                label: 'Selling price',
                required: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => onChanged(),
                validator: _validatePrice,
              ),
            const SizedBox(height: 12),
            SelloFormRow(
              left: SelloTextField(
                controller: row.barcode,
                label: 'Barcode',
                onChanged: (_) => onChanged(),
              ),
              right: row.isNew
                  ? SelloTextField(
                      controller: row.openingStock,
                      label: 'Opening stock',
                      hint: '0',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => onChanged(),
                      validator: _validateOptionalStock,
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        'Current stock: '
                        '${SelloFormatters.quantity(row.currentStockQuantity ?? 0)}'
                        ' · Adjust in Inventory',
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validatePrice(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required.';
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < 0) return 'Value cannot be negative.';
    return null;
  }

  String? _validateOptionalPrice(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < 0) return 'Value cannot be negative.';
    return null;
  }

  String? _validateOptionalStock(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < 0) return 'Value cannot be negative.';
    return null;
  }
}

/// Pure helper for tests — builds drafts after evolving a simple product.
List<ProductVariantDraft> buildEvolvedOptionDrafts({
  required String existingVariantId,
  required String firstLabel,
  required String firstSku,
  required String secondLabel,
  required String secondSku,
  required num sellingPrice,
  required num unitCost,
  num? firstOpeningStock,
  num? secondOpeningStock,
}) {
  return [
    ProductVariantDraft(
      id: existingVariantId,
      label: firstLabel,
      sku: firstSku,
      sellingPrice: sellingPrice,
      unitCost: unitCost,
      isActive: true,
      isDefault: true,
      sortOrder: 0,
      openingStock: firstOpeningStock,
    ),
    ProductVariantDraft(
      label: secondLabel,
      sku: secondSku,
      sellingPrice: sellingPrice,
      unitCost: unitCost,
      isActive: true,
      isDefault: false,
      sortOrder: 1,
      openingStock: secondOpeningStock,
    ),
  ];
}

/// True when local option drafts contain user-entered details worth confirming.
bool optionDraftsHaveDetails(List<ProductOptionEditorRow> rows) {
  return rows.any((row) => row.hasEnteredDetails);
}

/// Draft-only remove: never for saved variants; never when only one option remains.
bool canRemoveDraftOption({
  required List<ProductOptionEditorRow> rows,
  required int index,
}) {
  if (index < 0 || index >= rows.length) return false;
  if (!rows[index].isNew) return false;
  return rows.length > 1;
}

/// Whether removing this draft option should ask for confirmation first.
bool draftOptionRemoveNeedsConfirmation(ProductOptionEditorRow row) {
  return row.isNew && row.hasEnteredDetails;
}

/// Removes a draft option in place. Returns false when the remove is blocked.
/// Caller must dispose the returned row when non-null.
ProductOptionEditorRow? removeDraftOptionAt({
  required List<ProductOptionEditorRow> rows,
  required int index,
}) {
  if (!canRemoveDraftOption(rows: rows, index: index)) return null;
  return rows.removeAt(index);
}

/// Re-export last-active validation for editor callers.
String? optionDeactivateError({
  required List<ProductOptionEditorRow> rows,
  required int index,
  required bool nextActive,
}) {
  if (nextActive) return null;
  final activeAfter = rows.asMap().entries.where((entry) {
    if (entry.key == index) return false;
    return entry.value.isActive;
  }).length;
  return validateLastActiveOption(activeCountAfterChange: activeAfter);
}
