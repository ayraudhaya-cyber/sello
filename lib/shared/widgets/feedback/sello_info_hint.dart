import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Subtle info icon that reveals secondary explanation on hover, focus, or tap.
///
/// Use for definitions and “what this setting does” copy — not for validation
/// errors, required-field messages, optional-field markers, or live status.
/// Optional fields stay unlabeled; required fields use [SelloFieldLabel.required].
class SelloInfoHint extends StatefulWidget {
  const SelloInfoHint({super.key, required this.message, this.semanticsLabel});

  final String message;

  /// Screen-reader name for the icon. Defaults to “More information”.
  final String? semanticsLabel;

  @override
  State<SelloInfoHint> createState() => _SelloInfoHintState();
}

class _SelloInfoHintState extends State<SelloInfoHint> {
  final _tooltipKey = GlobalKey<TooltipState>();

  void _reveal() {
    _tooltipKey.currentState?.ensureTooltipVisible();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message.trim();
    if (message.isEmpty) return const SizedBox.shrink();

    final label = widget.semanticsLabel?.trim().isNotEmpty == true
        ? widget.semanticsLabel!.trim()
        : 'More information';

    return Tooltip(
      key: _tooltipKey,
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: const Duration(milliseconds: 220),
      showDuration: const Duration(seconds: 6),
      exitDuration: const Duration(milliseconds: 120),
      preferBelow: true,
      verticalOffset: 8,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      textStyle: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12.5,
        height: 1.35,
        color: Colors.white,
      ),
      enableFeedback: false,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        hint: 'Shows an explanation',
        child: InkResponse(
          onTap: _reveal,
          onHover: (hovering) {
            if (hovering) _reveal();
          },
          onFocusChange: (focused) {
            if (focused) _reveal();
          },
          radius: 12,
          child: const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Setting / form label with an optional required mark and [SelloInfoHint].
///
/// Required fields show a soft-red asterisk after the label. Optional fields
/// have no marker, tooltip, or “Optional” copy — [hint] is only for real help.
class SelloFieldLabel extends StatelessWidget {
  const SelloFieldLabel({
    super.key,
    required this.label,
    this.hint,
    this.required = false,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String label;

  /// Secondary explanation via [SelloInfoHint]. Never use to say “Optional”.
  final String? hint;

  /// When true, a pinkish asterisk follows the label.
  final bool required;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// [InputDecoration.label] widget, or null when [text] is empty.
  static Widget? decorationLabel(
    String? text, {
    bool required = false,
    String? hint,
    TextStyle? style,
  }) {
    if (text == null || text.trim().isEmpty) return null;
    return SelloFieldLabel(
      label: text,
      required: required,
      hint: hint,
      style: style ?? const TextStyle(fontFamily: AppTypography.fontFamily),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hintText = hint?.trim();
    final hasHint = hintText != null && hintText.isNotEmpty;
    final labelStyle =
        style ??
        const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        );
    final markSize = (labelStyle.fontSize ?? 13) + 1;

    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: maxLines,
              overflow: overflow,
              style: labelStyle,
            ),
          ),
          if (required) ...[
            const SizedBox(width: 2),
            Text(
              '*',
              style: labelStyle.copyWith(
                color: AppColors.requiredMark,
                fontWeight: FontWeight.w700,
                fontSize: markSize,
                height: 1,
              ),
            ),
          ],
          if (hasHint) ...[
            const SizedBox(width: 4),
            SelloInfoHint(message: hintText, semanticsLabel: 'About $label'),
          ],
        ],
      ),
    );
  }
}
