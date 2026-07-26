import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

enum SelloButtonVariant { primary, secondary, outline, ghost, gradient }

enum SelloButtonSize { small, medium, large }

/// Design-system button. Prefer this over raw Material buttons in feature UI.
class SelloButton extends StatelessWidget {
  const SelloButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SelloButtonVariant.primary,
    this.size = SelloButtonSize.medium,
    this.icon,
    this.expanded = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final SelloButtonVariant variant;
  final SelloButtonSize size;
  final IconData? icon;
  final bool expanded;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final height = switch (size) {
      SelloButtonSize.small => 40.0,
      SelloButtonSize.medium => AppSpacing.touchTarget,
      SelloButtonSize.large => 56.0,
    };
    final padding = switch (size) {
      SelloButtonSize.small => const EdgeInsets.symmetric(horizontal: 14),
      SelloButtonSize.medium =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      SelloButtonSize.large =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
    };

    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == SelloButtonVariant.outline ||
                      variant == SelloButtonVariant.ghost
                  ? AppColors.primary
                  : AppColors.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(label),
            ],
          );

    final button = switch (variant) {
      SelloButtonVariant.gradient => _GradientButton(
          onPressed: loading ? null : onPressed,
          height: height,
          padding: padding,
          child: child,
        ),
      SelloButtonVariant.primary => ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: Size(expanded ? double.infinity : 64, height),
            padding: padding,
          ),
          child: child,
        ),
      SelloButtonVariant.secondary => FilledButton.tonal(
          onPressed: loading ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: Size(expanded ? double.infinity : 64, height),
            padding: padding,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonAll),
          ),
          child: child,
        ),
      SelloButtonVariant.outline => OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(expanded ? double.infinity : 64, height),
            padding: padding,
          ),
          child: child,
        ),
      SelloButtonVariant.ghost => TextButton(
          onPressed: loading ? null : onPressed,
          style: TextButton.styleFrom(
            minimumSize: Size(expanded ? double.infinity : 64, height),
            padding: padding,
          ),
          child: child,
        ),
    };

    if (expanded && variant != SelloButtonVariant.gradient) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onPressed,
    required this.height,
    required this.padding,
    required this.child,
  });

  final VoidCallback? onPressed;
  final double height;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.buttonAll,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: enabled ? AppGradients.primary : null,
            color: enabled ? null : AppColors.outline,
            borderRadius: AppRadius.buttonAll,
          ),
          child: Padding(
            padding: padding,
            child: DefaultTextStyle(
              style: AppTypography.button.copyWith(color: AppColors.onPrimary),
              child: IconTheme(
                data: const IconThemeData(color: AppColors.onPrimary, size: 20),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
