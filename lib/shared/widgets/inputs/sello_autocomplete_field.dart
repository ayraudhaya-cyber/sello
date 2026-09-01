import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';

/// Searchable text field with suggestions; free-text / custom values allowed.
class SelloAutocompleteField extends StatefulWidget {
  const SelloAutocompleteField({
    super.key,
    required this.value,
    required this.suggestions,
    required this.onChanged,
    this.label,
    this.hint,
    this.validator,
    this.enabled = true,
    this.required = false,
    this.maxSuggestions = 16,
    this.optionsViewOpenDirection = OptionsViewOpenDirection.down,
  });

  final String value;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;
  final int maxSuggestions;

  /// Use [OptionsViewOpenDirection.up] inside bottom sheets.
  final OptionsViewOpenDirection optionsViewOpenDirection;

  @override
  State<SelloAutocompleteField> createState() => _SelloAutocompleteFieldState();
}

class _SelloAutocompleteFieldState extends State<SelloAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant SelloAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Iterable<String> _optionsFor(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    final limit = widget.maxSuggestions;
    if (query.isEmpty) return widget.suggestions.take(limit);
    return widget.suggestions
        .where((s) => s.toLowerCase().contains(query))
        .take(limit);
  }

  @override
  Widget build(BuildContext context) {
    final openUp =
        widget.optionsViewOpenDirection == OptionsViewOpenDirection.up;

    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsViewOpenDirection: widget.optionsViewOpenDirection,
      optionsBuilder: (textEditingValue) => _optionsFor(textEditingValue),
      onSelected: (selection) {
        _controller.text = selection;
        widget.onChanged(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          validator: widget.validator,
          style: context.texts.bodyMedium,
          cursorWidth: 1.5,
          cursorRadius: const Radius.circular(1),
          onChanged: widget.onChanged,
          onFieldSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            label: SelloFieldLabel.decorationLabel(
              widget.label,
              required: widget.required,
            ),
            hintText: widget.hint,
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            suffixIcon: Icon(
              Icons.arrow_drop_down_rounded,
              size: 22,
              color: AppColors.textTertiary,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList(growable: false);
        if (list.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: openUp ? Alignment.bottomLeft : Alignment.topLeft,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, minWidth: 200),
              child: Container(
                margin: EdgeInsets.only(
                  top: openUp ? 0 : 6,
                  bottom: openUp ? 6 : 0,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.outlinePanel),
                  boxShadow: AppShadows.level2,
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final option = list[index];
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Searchable country picker — stores ISO alpha-2, displays flag + name.
class SelloCountryField extends StatefulWidget {
  const SelloCountryField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hint,
    this.validator,
    this.enabled = true,
    this.required = false,
  });

  /// ISO 3166-1 alpha-2 code, or empty.
  final String value;
  final List<({String code, String label})> options;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;

  @override
  State<SelloCountryField> createState() => _SelloCountryFieldState();
}

class _SelloCountryFieldState extends State<SelloCountryField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  String _labelForCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final option in widget.options) {
      if (option.code == normalized) return option.label;
    }
    return code;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.trim().isEmpty ? '' : _labelForCode(widget.value),
    );
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) _syncDisplayFromValue();
      });
  }

  @override
  void didUpdateWidget(covariant SelloCountryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _syncDisplayFromValue();
    }
  }

  void _syncDisplayFromValue() {
    final next = widget.value.trim().isEmpty ? '' : _labelForCode(widget.value);
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Iterable<({String code, String label})> _filter(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options.where((o) {
      return o.label.toLowerCase().contains(query) ||
          o.code.toLowerCase().contains(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.value,
      validator: (_) => widget.validator?.call(widget.value),
      builder: (formState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RawAutocomplete<({String code, String label})>(
              textEditingController: _controller,
              focusNode: _focusNode,
              displayStringForOption: (option) => option.label,
              optionsBuilder: _filter,
              onSelected: (option) {
                _controller.text = option.label;
                widget.onChanged(option.code);
                formState.didChange(option.code);
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: widget.enabled,
                  style: context.texts.bodyMedium,
                  cursorWidth: 1.5,
                  cursorRadius: const Radius.circular(1),
                  onChanged: (text) {
                    // Typing clears a committed code until a suggestion is picked.
                    if (widget.value.isNotEmpty) {
                      widget.onChanged('');
                      formState.didChange('');
                    }
                  },
                  onSubmitted: (_) => onFieldSubmitted(),
                  decoration: InputDecoration(
                    label: SelloFieldLabel.decorationLabel(
                      widget.label,
                      required: widget.required,
                    ),
                    hintText: widget.hint ?? 'Search country…',
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    errorText: formState.errorText,
                    suffixIcon: Icon(
                      Icons.public_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final list = options.toList(growable: false);
                if (list.isEmpty) return const SizedBox.shrink();

                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 0,
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 280, minWidth: 220),
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.outlinePanel),
                          boxShadow: AppShadows.level2,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final option = list[index];
                            final selected = option.code ==
                                widget.value.trim().toUpperCase();
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        option.label,
                                        style: TextStyle(
                                          fontFamily: AppTypography.fontFamily,
                                          fontSize: 13.5,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: selected
                                              ? context.brandAccent
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: context.brandAccent,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
