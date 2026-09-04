import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';
import 'package:sello/shared/widgets/inputs/sello_switch.dart';

/// Standard desktop width for Sello CRUD form dialogs.
const double kSelloFormDialogWidth = 1120;

/// Standard width for entity detail dialogs (Product, Customer, etc.).
const double kSelloDetailDialogWidth = 1100;

/// Premium enterprise form / detail dialog shell.
///
/// Use for Product, Customer, Employee, Supplier, Order, Branch, etc.
class SelloFormDialog extends StatelessWidget {
  const SelloFormDialog({
    super.key,
    this.title,
    this.subtitle,
    this.header,
    required this.body,
    required this.footer,
    this.formKey,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.maxWidth = kSelloFormDialogWidth,
    this.maxHeightFactor = 0.92,
    this.showCloseButton = true,
    this.onClose,
    this.fullscreenOnMobile = false,
    this.bodyPadding = const EdgeInsets.fromLTRB(32, 28, 32, 8),
    this.scrollableBody = true,
  }) : assert(
         header != null || title != null,
         'Provide either a [header] or a [title].',
       );

  final String? title;
  final String? subtitle;

  /// Replaces the default title/subtitle block (e.g. entity hero).
  final Widget? header;

  final Widget body;
  final Widget footer;
  final GlobalKey<FormState>? formKey;
  final AutovalidateMode autovalidateMode;
  final double maxWidth;
  final double maxHeightFactor;

  /// Top-right dismiss control — default for all Sello dialogs.
  final bool showCloseButton;

  /// Defaults to [Navigator.maybePop].
  final VoidCallback? onClose;

  /// On phone widths, expand edge-to-edge like a full-screen sheet.
  final bool fullscreenOnMobile;

  final EdgeInsetsGeometry bodyPadding;

  /// When false, [body] fills remaining height (e.g. catalog + cart layouts)
  /// and manages its own scrolling instead of the dialog wrapping it.
  final bool scrollableBody;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final isFullscreen = fullscreenOnMobile && media.width < 720;
    final maxH = media.height * maxHeightFactor;
    final close = onClose ?? () => Navigator.of(context).maybePop();

    final content = Material(
      color: AppColors.surface,
      borderRadius: isFullscreen ? BorderRadius.zero : AppRadius.dialogAll,
      clipBehavior: Clip.antiAlias,
      child: Form(
        key: formKey,
        autovalidateMode: autovalidateMode,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: isFullscreen ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                isFullscreen ? 20 : 32,
                isFullscreen ? 12 : 16,
                isFullscreen ? 12 : 20,
                0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 8),
                      child:
                          header ??
                          _SelloDialogTitleBlock(
                            title: title!,
                            subtitle: subtitle,
                          ),
                    ),
                  ),
                  if (showCloseButton)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textTertiary,
                        hoverColor: AppColors.veil,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 22),
                    ),
                ],
              ),
            ),
            Flexible(
              child: scrollableBody
                  ? SingleChildScrollView(padding: bodyPadding, child: body)
                  : Padding(padding: bodyPadding, child: body),
            ),
            // Shared inset so custom footers (raw Rows) get the same margins.
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                isFullscreen ? 20 : 32,
                16,
                isFullscreen ? 20 : 32,
                isFullscreen ? 16 : 24,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.outlinePanel)),
              ),
              child: footer,
            ),
          ],
        ),
      ),
    );

    return Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      insetPadding: isFullscreen
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: isFullscreen ? BorderRadius.zero : AppRadius.dialogAll,
      ),
      child: isFullscreen
          ? SizedBox(
              width: media.width,
              height: media.height,
              child: SafeArea(child: content),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxH,
                // Never exceed [maxWidth] — narrow dialogs (e.g. pickers) must
                // not get a larger minWidth than their max.
                minWidth: media.width < 720
                    ? 0
                    : (maxWidth < 640 ? maxWidth : 640),
              ),
              child: content,
            ),
    );
  }
}

class _SelloDialogTitleBlock extends StatelessWidget {
  const _SelloDialogTitleBlock({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.dialogTitle),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Section label for grouping fields without a visible card chrome.
class SelloSectionTitle extends StatelessWidget {
  const SelloSectionTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01 * 13,
        height: 1.3,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// Logical field group — spacing alone creates hierarchy (no card borders).
class SelloDialogSection extends StatelessWidget {
  const SelloDialogSection({
    super.key,
    required this.title,
    required this.children,
    this.gap = 14,
    this.bottomSpacing = 28,
  });

  final String title;
  final List<Widget> children;
  final double gap;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloSectionTitle(title),
          const SizedBox(height: 12),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Read-only label + value pair for entity detail dialogs.
class SelloDetailField extends StatelessWidget {
  const SelloDetailField({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
    this.trailing,
    this.leading,
    this.placeholder = false,
    this.emphasized = false,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Widget? trailing;
  final Widget? leading;

  /// Softens the value for future / unavailable placeholders.
  final bool placeholder;

  /// Slightly larger, higher-contrast value (e.g. selling price).
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final resolvedValue =
        valueWidget ??
        Text(
          value!,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: emphasized ? 22 : 15,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            height: 1.3,
            letterSpacing: emphasized ? -0.3 : 0,
            color: placeholder ? AppColors.textFaint : AppColors.textPrimary,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.02,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(child: resolvedValue),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ],
    );
  }
}

/// Two equal fields in a row; stacks on very narrow widths.
class SelloFormRow extends StatelessWidget {
  const SelloFormRow({
    super.key,
    required this.left,
    required this.right,
    this.gap = 14,
    this.stackBelow = 520,
  });

  final Widget left;
  final Widget right;
  final double gap;
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    return SelloFormWeightedRow(
      gap: gap,
      stackBelow: stackBelow,
      children: [left, right],
    );
  }
}

/// Multi-field row with optional flex weights (e.g. Category 48% + Brand/Unit).
class SelloFormWeightedRow extends StatelessWidget {
  const SelloFormWeightedRow({
    super.key,
    required this.children,
    this.flexes,
    this.gap = 14,
    this.stackBelow = 640,
  });

  final List<Widget> children;
  final List<int>? flexes;
  final double gap;
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    assert(children.isNotEmpty);
    assert(
      flexes == null || flexes!.length == children.length,
      'flexes length must match children',
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(flex: flexes?[i] ?? 1, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Compact status row with toggle and optional info hint beside the label.
class SelloStatusToggle extends StatelessWidget {
  const SelloStatusToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Active',
    this.helper =
        'Inactive records remain available in reports and history but cannot be used in new activity.',
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  /// Secondary explanation shown via [SelloInfoHint] beside the label.
  final String helper;

  @override
  Widget build(BuildContext context) {
    final hint = helper.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Flexible(
            child: InkWell(
              onTap: () => onChanged(!value),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Row(
                children: [
                  SelloSwitch(value: value, onChanged: onChanged),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(width: 4),
            SelloInfoHint(message: hint, semanticsLabel: 'About $label'),
          ],
        ],
      ),
    );
  }
}

/// Soft-tinted media panel for entity images (products, customers, etc.).
class SelloImagePickerPanel extends StatelessWidget {
  const SelloImagePickerPanel({
    super.key,
    required this.onUpload,
    this.title = 'Image',
    this.networkUrl,
    this.localBytes,
    this.onRemove,
    this.hints = const [
      'Recommended: 1000 × 1000px',
      'Supports: PNG, JPG, WEBP',
      'Maximum: 5MB',
    ],
    this.uploadLabel = 'Upload',
    this.height = 280,
  });

  final String title;
  final String? networkUrl;
  final Uint8List? localBytes;
  final VoidCallback onUpload;
  final VoidCallback? onRemove;
  final List<String> hints;
  final String uploadLabel;
  final double height;

  bool get _hasImage =>
      localBytes != null || (networkUrl != null && networkUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.brandAccent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01 * 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onUpload,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Ink(
                height: height,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.outline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md - 1),
                  child: _Preview(
                    networkUrl: networkUrl,
                    localBytes: localBytes,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelloButton(
                label: uploadLabel,
                icon: Icons.upload_rounded,
                variant: SelloButtonVariant.primary,
                size: SelloButtonSize.small,
                onPressed: onUpload,
              ),
              if (_hasImage && onRemove != null)
                SelloButton(
                  label: 'Remove',
                  icon: Icons.delete_outline_rounded,
                  variant: SelloButtonVariant.ghost,
                  size: SelloButtonSize.small,
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < hints.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Text(
              hints[i],
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                height: 1.4,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.networkUrl, required this.localBytes});

  final String? networkUrl;
  final Uint8List? localBytes;

  @override
  Widget build(BuildContext context) {
    if (localBytes != null) {
      return Image.memory(
        localBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (networkUrl != null && networkUrl!.isNotEmpty) {
      return Image.network(
        networkUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const _EmptyPreview(),
      );
    }

    return const _EmptyPreview();
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.brandAccent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 26,
                color: context.brandAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Drop or click to upload',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog action bar — Cancel (secondary) + primary, generously spaced.
class SelloDialogFooter extends StatelessWidget {
  const SelloDialogFooter({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.primaryLoading = false,
    this.primaryEnabled = true,
    this.cancelVariant = SelloButtonVariant.outline,
    this.destructiveLabel,
    this.onDestructive,
    this.leading,
  });

  final String primaryLabel;

  /// Null or [primaryEnabled] false disables the primary action.
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;
  final String cancelLabel;
  final bool primaryLoading;
  final bool primaryEnabled;
  final SelloButtonVariant cancelVariant;

  /// Optional leading destructive action (e.g. permanent delete).
  final String? destructiveLabel;
  final VoidCallback? onDestructive;

  /// Quiet secondary actions (e.g. icon links) between destructive and Cancel.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final hasDestructive = destructiveLabel != null && onDestructive != null;

    // Left actions grow/wrap; Close + primary stay pinned to the right edge.
    // Padding / top rule live on [SelloFormDialog] so every modal footer
    // shares the same inset — including custom Rows.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasDestructive)
                  SelloButton(
                    label: destructiveLabel!,
                    variant: SelloButtonVariant.danger,
                    onPressed: onDestructive,
                  ),
                ?leading,
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        SelloButton(
          label: cancelLabel,
          variant: cancelVariant,
          onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        SelloButton(
          label: primaryLabel,
          variant: SelloButtonVariant.primary,
          loading: primaryLoading,
          onPressed: primaryEnabled && !primaryLoading ? onPrimary : null,
        ),
      ],
    );
  }
}
