import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';

/// Searchable text field with suggestions; free-text / custom values allowed.
class SelloAutocompleteField extends StatefulWidget {
  const SelloAutocompleteField({
    super.key,
    required this.value,
    required this.suggestions,
    required this.onChanged,
    this.controller,
    this.label,
    this.hint,
    this.validator,
    this.enabled = true,
    this.required = false,
    this.maxSuggestions = 16,
    this.suggestWhenEmpty = true,
    this.suggestionFilter,
    this.optionsViewOpenDirection = OptionsViewOpenDirection.down,
  });

  final String value;
  final TextEditingController? controller;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;
  final int maxSuggestions;

  /// When false, suggestions stay hidden until the user types.
  final bool suggestWhenEmpty;

  /// Optional custom ranking/filtering. Receives the raw query text.
  final List<String> Function(String query, List<String> suggestions)?
  suggestionFilter;

  /// Use [OptionsViewOpenDirection.up] inside bottom sheets.
  final OptionsViewOpenDirection optionsViewOpenDirection;

  @override
  State<SelloAutocompleteField> createState() => _SelloAutocompleteFieldState();
}

class _SelloAutocompleteFieldState extends State<SelloAutocompleteField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? TextEditingController(text: widget.value);
    _focusNode = FocusNode(onKeyEvent: _onArrowKeys);
  }

  KeyEventResult _onArrowKeys(FocusNode node, KeyEvent event) {
    return _handleAutocompleteArrowKey(
      node,
      event,
      hasOptions: _optionsFor(_controller.value).isNotEmpty,
    );
  }

  @override
  void didUpdateWidget(covariant SelloAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ownsController &&
        widget.value != oldWidget.value &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Iterable<String> _optionsFor(TextEditingValue value) {
    final filter = widget.suggestionFilter;
    if (filter != null) {
      return filter(value.text, widget.suggestions);
    }
    final query = value.text.trim().toLowerCase();
    final limit = widget.maxSuggestions;
    if (query.isEmpty) {
      return widget.suggestWhenEmpty
          ? widget.suggestions.take(limit)
          : const Iterable<String>.empty();
    }
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
              color: widget.enabled
                  ? AppColors.textTertiary
                  : AppColors.textDisabled,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _SelloSuggestionPanel<String>(
          options: options.toList(growable: false),
          onSelected: onSelected,
          labelOf: (option) => option,
          openUp: openUp,
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
    _focusNode = FocusNode(onKeyEvent: _onArrowKeys)
      ..addListener(() {
        if (!_focusNode.hasFocus) _syncDisplayFromValue();
      });
  }

  KeyEventResult _onArrowKeys(FocusNode node, KeyEvent event) {
    return _handleAutocompleteArrowKey(
      node,
      event,
      hasOptions: _filter(_controller.value).isNotEmpty,
    );
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
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
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
                return _SelloSuggestionPanel<({String code, String label})>(
                  options: options.toList(growable: false),
                  onSelected: onSelected,
                  labelOf: (option) => option.label,
                  selected: (option) =>
                      option.code == widget.value.trim().toUpperCase(),
                  maxHeight: 280,
                  minWidth: 220,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

KeyEventResult _handleAutocompleteArrowKey(
  FocusNode node,
  KeyEvent event, {
  required bool hasOptions,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  if (!hasOptions) return KeyEventResult.ignored;
  final ctx = node.context;
  if (ctx == null || !ctx.mounted) return KeyEventResult.ignored;
  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
    Actions.maybeInvoke<AutocompleteNextOptionIntent>(
      ctx,
      const AutocompleteNextOptionIntent(),
    );
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
    Actions.maybeInvoke<AutocompletePreviousOptionIntent>(
      ctx,
      const AutocompletePreviousOptionIntent(),
    );
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

class _SelloSuggestionPanel<T> extends StatefulWidget {
  const _SelloSuggestionPanel({
    required this.options,
    required this.onSelected,
    required this.labelOf,
    this.selected,
    this.openUp = false,
    this.maxHeight = 240,
    this.minWidth = 200,
  });

  final List<T> options;
  final ValueChanged<T> onSelected;
  final String Function(T option) labelOf;
  final bool Function(T option)? selected;
  final bool openUp;
  final double maxHeight;
  final double minWidth;

  @override
  State<_SelloSuggestionPanel<T>> createState() =>
      _SelloSuggestionPanelState<T>();
}

class _SelloSuggestionPanelState<T> extends State<_SelloSuggestionPanel<T>> {
  final _scroll = ScrollController();
  static const _rowHeight = 40.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (index * _rowHeight).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.options;
    if (list.isEmpty) return const SizedBox.shrink();
    final highlighted = AutocompleteHighlightedOption.of(
      context,
    ).clamp(0, list.length - 1);
    _scrollTo(highlighted);

    return Align(
      alignment: widget.openUp ? Alignment.bottomLeft : Alignment.topLeft,
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.maxHeight,
            minWidth: widget.minWidth,
          ),
          child: Container(
            margin: EdgeInsets.only(
              top: widget.openUp ? 0 : 6,
              bottom: widget.openUp ? 6 : 0,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outlinePanel),
              boxShadow: AppShadows.level2,
            ),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (context, index) {
                final option = list[index];
                final isHighlighted = index == highlighted;
                final isSelected = widget.selected?.call(option) ?? false;
                final emphasize = isHighlighted || isSelected;
                return InkWell(
                  onTap: () => widget.onSelected(option),
                  child: ColoredBox(
                    color: isHighlighted ? AppColors.veil : Colors.transparent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: _rowHeight),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.labelOf(option),
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13.5,
                                  fontWeight: emphasize
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: emphasize
                                      ? context.brandAccent
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: context.brandAccent,
                              ),
                          ],
                        ),
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
  }
}
