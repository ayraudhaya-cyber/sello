import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Mutable editor state for one sellable option row.
class ProductOptionEditorRow {
  ProductOptionEditorRow({
    this.id,
    this.isDefault = false,
    this.isActive = true,
    String label = '',
    String sku = '',
    String barcode = '',
    String sellingPrice = '',
    String costPrice = '',
  })  : label = TextEditingController(text: label),
        sku = TextEditingController(text: sku),
        barcode = TextEditingController(text: barcode),
        sellingPrice = TextEditingController(text: sellingPrice),
        costPrice = TextEditingController(text: costPrice);

  String? id;
  bool isDefault;
  bool isActive;
  final TextEditingController label;
  final TextEditingController sku;
  final TextEditingController barcode;
  final TextEditingController sellingPrice;
  final TextEditingController costPrice;

  void dispose() {
    label.dispose();
    sku.dispose();
    barcode.dispose();
    sellingPrice.dispose();
    costPrice.dispose();
  }

  ProductVariantDraft toDraft({
    required int sortOrder,
    required bool includeCost,
  }) {
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
  });

  final List<ProductOptionEditorRow> rows;
  final bool showCost;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback onAddOption;
  final void Function(int index, bool active) onToggleActive;

  @override
  Widget build(BuildContext context) {
    return SelloDialogSection(
      title: 'Sellable options',
      children: [
        const Text(
          'Each option is a separate sellable unit with its own item code, '
          'price, and stock.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
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
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _OptionCard(
            index: i,
            row: rows[i],
            showCost: showCost,
            onChanged: onChanged,
            onToggleActive: (active) => onToggleActive(i, active),
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
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.index,
    required this.row,
    required this.showCost,
    required this.onChanged,
    required this.onToggleActive,
  });

  final int index;
  final ProductOptionEditorRow row;
  final bool showCost;
  final VoidCallback onChanged;
  final ValueChanged<bool> onToggleActive;

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
          border: Border.all(color: AppColors.outlinePanel),
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
                SelloStatusToggle(
                  value: row.isActive,
                  onChanged: onToggleActive,
                  label: 'Active',
                  helper: 'Inactive options stay in history but cannot be sold.',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelloTextField(
              controller: row.label,
              label: 'Label',
              required: true,
              hint: 'e.g. 500ml, Blue, Large',
              onChanged: (_) => onChanged(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a label.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SelloFormRow(
              left: SelloTextField(
                controller: row.sku,
                label: 'Item code',
                required: true,
                onChanged: (_) => onChanged(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter an item code.';
                  }
                  return null;
                },
              ),
              right: SelloTextField(
                controller: row.barcode,
                label: 'Barcode',
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(height: 12),
            if (showCost)
              SelloFormRow(
                left: SelloTextField(
                  controller: row.sellingPrice,
                  label: 'Selling price',
                  required: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  validator: _validatePrice,
                ),
                right: SelloTextField(
                  controller: row.costPrice,
                  label: 'Cost price',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  validator: _validateOptionalPrice,
                ),
              )
            else
              SelloTextField(
                controller: row.sellingPrice,
                label: 'Selling price',
                required: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
                validator: _validatePrice,
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
    ),
    ProductVariantDraft(
      label: secondLabel,
      sku: secondSku,
      sellingPrice: sellingPrice,
      unitCost: unitCost,
      isActive: true,
      isDefault: false,
      sortOrder: 1,
    ),
  ];
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
