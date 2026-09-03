import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';

/// Styled text field using theme input decoration.
class SelloTextField extends StatelessWidget {
  const SelloTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.autofillHints,
    this.maxLines = 1,
    this.helperText,
    this.tooltip,
    this.required = false,
    this.inputFormatters,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
    this.focusNode,
    this.onFieldSubmitted,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final String? helperText;

  /// Shown via an info icon next to the label (hover, focus, or tap).
  /// Use for real explanations — never to mark the field as optional.
  final String? tooltip;

  /// Soft-red asterisk after the label. Optional fields stay unmarked.
  final bool required;
  final List<TextInputFormatter>? inputFormatters;
  final AutovalidateMode autovalidateMode;
  final FocusNode? focusNode;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final hasTooltip = tooltip != null && tooltip!.trim().isNotEmpty;
    final useLabelWidget = required || hasTooltip;

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      enabled: enabled,
      autofillHints: autofillHints,
      maxLines: obscureText ? 1 : maxLines,
      inputFormatters: inputFormatters,
      autovalidateMode: autovalidateMode,
      style: context.texts.bodyMedium,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(1),
      decoration: InputDecoration(
        labelText: useLabelWidget ? null : label,
        label: useLabelWidget
            ? SelloFieldLabel.decorationLabel(
                label,
                required: required,
                hint: tooltip,
              )
            : null,
        hintText: hint,
        helperText: helperText,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 19, color: AppColors.textTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// Search field for app bars and list headers.
///
/// Height matches [AppSpacing.controlHeight] / medium [SelloButton].
/// Corner radius matches buttons (8px).
class SelloSearchBar extends StatefulWidget {
  const SelloSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Search products, customers or orders...',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<SelloSearchBar> createState() => _SelloSearchBarState();
}

class _SelloSearchBarState extends State<SelloSearchBar> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_syncClearButton);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncClearButton);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _syncClearButton() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.controlHeight,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        textInputAction: TextInputAction.search,
        style: context.texts.bodyMedium,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: AppSpacing.controlHeight,
          ),
          suffixIcon: _hasText
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: widget.enabled ? _clear : null,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: AppSpacing.controlHeight,
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: const OutlineInputBorder(
            borderRadius: AppRadius.inputAll,
            borderSide: BorderSide(color: AppColors.outline),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: AppRadius.inputAll,
            borderSide: BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.inputAll,
            borderSide: BorderSide(color: context.brandAccent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 0,
          ),
          constraints: const BoxConstraints.tightFor(
            height: AppSpacing.controlHeight,
          ),
        ),
      ),
    );
  }
}
