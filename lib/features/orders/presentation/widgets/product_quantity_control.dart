import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/orders/order_stock_policy.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Touch-friendly quantity stepper with direct numeric entry for field sales.
class ProductQuantityControl extends StatelessWidget {
  const ProductQuantityControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowZero = false,
    this.showRemove = false,
    this.onRemove,
    this.maxQuantity,
    this.onIncreaseBlocked,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final bool allowZero;
  final bool showRemove;
  final VoidCallback? onRemove;
  final num? maxQuantity;
  final VoidCallback? onIncreaseBlocked;

  /// Width reserved for the number so 1, 99 and 999 stay in the same place.
  static const double quantitySlotWidth = 44;

  /// Comfortable thumb target. Shared by every catalog view.
  static const double buttonSize = 44;

  @override
  Widget build(BuildContext context) {
    final canDecrease = allowZero || value > 1;
    final max = maxQuantity;
    final canIncrease = max == null || value < max;

    final stepper = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          enabled: canDecrease,
          onTap: () {
            final next = value - 1;
            if (allowZero || next >= 1) onChanged(next);
          },
          tooltip: 'Decrease quantity',
        ),
        const SizedBox(width: 2),
        _quantityLabel(context),
        const SizedBox(width: 2),
        _StepButton(
          icon: Icons.add_rounded,
          enabled: canIncrease,
          onTap: () => onChanged(value + 1),
          onDisabledTap: onIncreaseBlocked,
          tooltip:
              canIncrease ? 'Increase quantity' : 'Maximum quantity reached',
        ),
      ],
    );

    final showDelete = showRemove && value > 0;
    if (!showDelete) return stepper;

    const deleteGap = 10.0;
    final remove = _RemoveButton(onTap: onRemove ?? () => onChanged(0));

    return LayoutBuilder(
      builder: (context, constraints) {
        final needed = _stepperWidth + deleteGap + buttonSize;
        final fits = !constraints.maxWidth.isFinite ||
            constraints.maxWidth >= needed;
        if (fits) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              stepper,
              const SizedBox(width: deleteGap),
              remove,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            stepper,
            const SizedBox(height: 8),
            remove,
          ],
        );
      },
    );
  }

  static double get _stepperWidth =>
      buttonSize + 2 + quantitySlotWidth + 2 + buttonSize;

  Widget _quantityLabel(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: () => _openQuantityEditor(context),
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Tooltip(
          message: 'Edit quantity',
          child: SizedBox(
            width: quantitySlotWidth,
            height: buttonSize,
            child: Center(
              child: Text(
                SelloFormatters.quantity(value),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openQuantityEditor(BuildContext context) async {
    final parsed = await showModalBottomSheet<num>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.bottomSheetAll,
      ),
      builder: (sheetContext) => _QuantityEditorSheet(
        initialValue: value,
        allowZero: allowZero,
        maxQuantity: maxQuantity,
        onLimitExceeded: onIncreaseBlocked,
      ),
    );

    if (parsed != null) {
      onChanged(parsed);
    }
  }
}

class _QuantityEditorSheet extends StatefulWidget {
  const _QuantityEditorSheet({
    required this.initialValue,
    required this.allowZero,
    this.maxQuantity,
    this.onLimitExceeded,
  });

  final num initialValue;
  final bool allowZero;
  final num? maxQuantity;
  final VoidCallback? onLimitExceeded;

  @override
  State<_QuantityEditorSheet> createState() => _QuantityEditorSheetState();
}

class _QuantityEditorSheetState extends State<_QuantityEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == widget.initialValue.roundToDouble()
          ? widget.initialValue.round().toString()
          : SelloFormatters.quantity(widget.initialValue),
    );
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final raw = _controller.text.trim();
    final parsed = num.tryParse(raw);
    if (parsed == null || parsed < 0) {
      SelloSnackbars.error(context, 'Enter a valid quantity.');
      return;
    }
    if (!widget.allowZero && parsed < 1) {
      SelloSnackbars.error(context, 'Quantity must be at least 1.');
      return;
    }
    if (widget.maxQuantity != null && parsed > widget.maxQuantity!) {
      widget.onLimitExceeded?.call();
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter quantity',
              style: context.texts.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SelloTextField(
              controller: _controller,
              focusNode: _focus,
              label: 'Quantity',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              autofillHints: const [],
              autovalidateMode: AutovalidateMode.disabled,
              validator: (value) {
                final raw = value?.trim() ?? '';
                if (raw.isEmpty) return 'Quantity is required';
                final parsed = num.tryParse(raw);
                if (parsed == null || parsed < 0) {
                  return 'Enter a valid quantity';
                }
                if (!widget.allowZero && parsed < 1) {
                  return 'Quantity must be at least 1';
                }
                if (widget.maxQuantity != null && parsed > widget.maxQuantity!) {
                  return OrderStockPolicy.onlyAvailableMessage(
                    widget.maxQuantity!,
                  );
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            SelloButton(
              label: 'Update quantity',
              expanded: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.tooltip,
    this.onDisabledTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onDisabledTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: enabled ? onTap : onDisabledTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Container(
            width: ProductQuantityControl.buttonSize,
            height: ProductQuantityControl.buttonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.button),
              border: Border.all(color: AppColors.outlinePanel),
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? AppColors.textSecondary : AppColors.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Remove from order',
      child: Material(
        color: AppColors.attentionSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: const SizedBox(
            width: ProductQuantityControl.buttonSize,
            height: ProductQuantityControl.buttonSize,
            child: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: AppColors.attention,
            ),
          ),
        ),
      ),
    );
  }
}
