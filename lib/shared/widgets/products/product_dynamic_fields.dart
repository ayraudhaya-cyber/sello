import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/country_catalog.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/product_detail_suggestions.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';
import 'package:sello/shared/widgets/inputs/sello_autocomplete_field.dart';
import 'package:sello/shared/widgets/inputs/sello_dropdown.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Renders enabled configurable Product Details for Hub forms / Sales present.
class ProductDynamicFields extends StatelessWidget {
  const ProductDynamicFields({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.readOnly = false,
    this.includeColumnBacked = true,
    this.includeInventory = true,
    this.includeAttributes = true,
  });

  final List<CompanyProductField> fields;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;
  final bool readOnly;
  final bool includeColumnBacked;
  final bool includeInventory;
  final bool includeAttributes;

  @override
  Widget build(BuildContext context) {
    final visible = fields.where((field) {
      if (!field.enabled) return false;
      if (field.fieldKey == 'description') return false;
      return switch (field.definition.storage) {
        ProductFieldStorage.column => includeColumnBacked,
        ProductFieldStorage.inventory => includeInventory,
        ProductFieldStorage.attribute => includeAttributes,
      };
    }).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _FieldControl(
            field: visible[i],
            value: values[visible[i].fieldKey] ?? '',
            readOnly: readOnly,
            onChanged: (next) {
              final updated = Map<String, String>.from(values);
              if (next.trim().isEmpty) {
                updated.remove(visible[i].fieldKey);
              } else {
                updated[visible[i].fieldKey] = next;
              }
              onChanged(updated);
            },
          ),
        ],
      ],
    );
  }
}

class _FieldControl extends StatelessWidget {
  const _FieldControl({
    required this.field,
    required this.value,
    required this.onChanged,
    required this.readOnly,
  });

  final CompanyProductField field;
  final String value;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  String? _requiredValidator(String? input) {
    if (!field.required) return null;
    if (input == null || input.trim().isEmpty) {
      return 'Enter ${field.label.toLowerCase()}.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = field.label;
    final def = field.definition;
    final options = field.effectiveOptions;

    if (readOnly) {
      final display = switch (def.fieldType) {
        ProductFieldType.country => CountryCatalog.display(value),
        ProductFieldType.boolean => value == 'true'
            ? 'Yes'
            : (value == 'false' ? 'No' : '—'),
        _ => value.trim().isEmpty ? '—' : value,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label.toUpperCase(),
            style: context.texts.labelSmall?.copyWith(
              color: context.selloColors.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            display,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return switch (def.fieldType) {
      ProductFieldType.country => SelloCountryField(
          value: value,
          label: label,
          required: field.required,
          options: CountryCatalog.asSelectOptions(),
          validator: (_) => _requiredValidator(value),
          onChanged: onChanged,
        ),
      ProductFieldType.select => SelloDropdown<String>(
          value: value.isEmpty ? null : value,
          label: label,
          required: field.required,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (next) => onChanged(next ?? ''),
        ),
      ProductFieldType.date => _DateFieldControl(
          label: label,
          value: value,
          required: field.required,
          onChanged: onChanged,
        ),
      ProductFieldType.colour => _ColourFieldControl(
          label: label,
          value: value,
          required: field.required,
          onChanged: onChanged,
        ),
      ProductFieldType.boolean => _BooleanFieldControl(
          label: label,
          value: value,
          required: field.required,
          onChanged: onChanged,
        ),
      ProductFieldType.barcode ||
      ProductFieldType.currency ||
      ProductFieldType.number ||
      ProductFieldType.multiline ||
      ProductFieldType.text =>
        _buildTextLike(label, options),
    };
  }

  Widget _buildTextLike(String label, List<String> options) {
    final def = field.definition;
    final suggestions = ProductDetailSuggestions.forKey(
      field.fieldKey,
      options: options,
    );
    if (suggestions.isNotEmpty &&
        (ProductDetailSuggestions.usesAutocomplete(field.fieldKey) ||
            options.isNotEmpty) &&
        (def.fieldType == ProductFieldType.text ||
            def.fieldType == ProductFieldType.colour)) {
      return SelloAutocompleteField(
        value: value,
        label: label,
        required: field.required,
        suggestions: suggestions,
        validator: _requiredValidator,
        onChanged: onChanged,
      );
    }

    return _TextFieldControl(
      label: label,
      value: value,
      required: field.required,
      maxLines: def.fieldType == ProductFieldType.multiline ? 4 : 1,
      keyboardType: switch (def.fieldType) {
        ProductFieldType.number || ProductFieldType.currency =>
          const TextInputType.numberWithOptions(decimal: true),
        ProductFieldType.barcode => TextInputType.visiblePassword,
        _ => TextInputType.text,
      },
      validator: _requiredValidator,
      onChanged: onChanged,
    );
  }
}

class _TextFieldControl extends StatefulWidget {
  const _TextFieldControl({
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;

  @override
  State<_TextFieldControl> createState() => _TextFieldControlState();
}

class _TextFieldControlState extends State<_TextFieldControl> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _TextFieldControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelloTextField(
      controller: _controller,
      label: widget.label,
      required: widget.required,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
    );
  }
}

class _DateFieldControl extends StatelessWidget {
  const _DateFieldControl({
    required this.label,
    required this.value,
    required this.required,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool required;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value);
    return FormField<String>(
      initialValue: value,
      validator: (v) {
        if (!required) return null;
        if (v == null || v.trim().isEmpty) {
          return 'Choose a date.';
        }
        return null;
      },
      builder: (state) {
        return InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: parsed ?? DateTime.now(),
              firstDate: DateTime(1990),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            final iso = picked.toIso8601String().split('T').first;
            onChanged(iso);
            state.didChange(iso);
          },
          borderRadius: AppRadius.inputAll,
          child: InputDecorator(
            decoration: InputDecoration(
              label: SelloFieldLabel.decorationLabel(
                label,
                required: required,
              ),
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(
              parsed != null ? SelloFormatters.date(parsed) : 'Select date',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: parsed == null
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BooleanFieldControl extends StatelessWidget {
  const _BooleanFieldControl({
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final isYes = value == 'true';
    return InputDecorator(
      decoration: InputDecoration(
        label: SelloFieldLabel.decorationLabel(label, required: required),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          isYes ? 'Yes' : 'No',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
          ),
        ),
        value: isYes,
        onChanged: (next) => onChanged(next ? 'true' : 'false'),
      ),
    );
  }
}

class _ColourFieldControl extends StatelessWidget {
  const _ColourFieldControl({
    required this.label,
    required this.value,
    required this.required,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool required;
  final ValueChanged<String> onChanged;

  static const _swatches = <(String, Color)>[
    ('Black', Color(0xFF111827)),
    ('White', Color(0xFFF9FAFB)),
    ('Grey', Color(0xFF9CA3AF)),
    ('Red', Color(0xFFDC2626)),
    ('Blue', Color(0xFF2563EB)),
    ('Green', Color(0xFF16A34A)),
    ('Yellow', Color(0xFFEAB308)),
    ('Orange', Color(0xFFEA580C)),
    ('Brown', Color(0xFF92400E)),
    ('Pink', Color(0xFFDB2777)),
    ('Purple', Color(0xFF7C3AED)),
    ('Gold', Color(0xFFD97706)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloAutocompleteField(
          value: value,
          label: label,
          required: required,
          suggestions: [
            for (final swatch in _swatches) swatch.$1,
            ...ProductDetailSuggestions.forKey('color'),
          ],
          validator: (input) {
            if (!required) return null;
            if (input == null || input.trim().isEmpty) {
              return 'Enter a colour.';
            }
            return null;
          },
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final swatch in _swatches)
              InkWell(
                onTap: () => onChanged(swatch.$1),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: swatch.$2,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: value.toLowerCase() == swatch.$1.toLowerCase()
                          ? context.brandAccent
                          : AppColors.outlinePanel,
                      width: value.toLowerCase() == swatch.$1.toLowerCase()
                          ? 2.5
                          : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String? productFieldRawValue(ProductSummary product, String key) {
  return switch (key) {
    'barcode' => product.barcode,
    'brand' => product.brand,
    'unit_label' => product.unitLabel,
    'description' => product.description,
    'reorder_level' => product.reorderLevel?.toString(),
    _ => product.attribute(key),
  };
}

String productSpecLine({
  required List<CompanyProductField> fields,
  required String? Function(String key) readValue,
  int maxParts = 4,
}) {
  final ordered = [...fields]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final parts = <String>[];
  for (final field in ordered) {
    if (field.fieldKey == 'description') continue;
    final raw = readValue(field.fieldKey);
    if (raw == null || raw.trim().isEmpty) continue;
    final display = switch (field.definition.fieldType) {
      ProductFieldType.country => CountryCatalog.display(raw),
      ProductFieldType.boolean =>
        raw == 'true' ? 'Yes' : (raw == 'false' ? 'No' : raw),
      _ => raw.trim(),
    };
    parts.add(display);
    if (parts.length >= maxParts) break;
  }
  return parts.join(' · ');
}
