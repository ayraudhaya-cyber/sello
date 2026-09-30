import 'package:flutter/material.dart';
import 'package:sello/shared/data/sri_lanka_banks.dart';
import 'package:sello/shared/widgets/inputs/sello_autocomplete_field.dart';

/// Searchable Sri Lankan bank field. Free-text is still allowed.
class SelloSriLankaBankField extends StatelessWidget {
  const SelloSriLankaBankField({
    super.key,
    required this.controller,
    this.onChanged,
    this.required = true,
    this.enabled = true,
    this.optionsViewOpenDirection = OptionsViewOpenDirection.down,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool required;
  final bool enabled;
  final OptionsViewOpenDirection optionsViewOpenDirection;

  @override
  Widget build(BuildContext context) {
    return SelloAutocompleteField(
      controller: controller,
      value: controller.text,
      label: 'Bank',
      hint: 'Search bank…',
      required: required,
      enabled: enabled,
      suggestions: sriLankaBankNames,
      maxSuggestions: 24,
      suggestWhenEmpty: true,
      optionsViewOpenDirection: optionsViewOpenDirection,
      suggestionFilter: (query, _) => filterSriLankaBanks(query),
      onChanged: onChanged ?? (_) {},
    );
  }
}
