import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Primary CTAs use solid brand purple — same as Quick Create / Add Product.
///
/// [SelloButtonVariant.gradient] is retained as a deprecated alias of [primary].
enum SelloButtonVariant { primary, secondary, outline, ghost, gradient, danger }

enum SelloButtonSize { small, medium, large }

/// Design-system button. Prefer this over raw Material buttons in feature UI.
///
/// Primary (and legacy gradient) use solid brand purple — same as Quick Create.
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

  BorderRadius get _radius => switch (size) {
        SelloButtonSize.small => AppRadius.buttonSmAll,
        SelloButtonSize.medium || SelloButtonSize.large => AppRadius.buttonAll,
      };

  bool get _isPrimary =>
      variant == SelloButtonVariant.primary ||
      variant == SelloButtonVariant.gradient;

  @override
  Widget build(BuildContext context) {
    final height = switch (size) {
      SelloButtonSize.small => AppSpacing.controlHeightCompact,
      SelloButtonSize.medium => AppSpacing.controlHeight,
      SelloButtonSize.large => 52.0,
    };
    final padding = switch (size) {
      SelloButtonSize.small => const EdgeInsets.symmetric(horizontal: 12),
      SelloButtonSize.medium =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.mdPlus),
      SelloButtonSize.large =>
        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
    };
    final iconSize = size == SelloButtonSize.small ? 16.0 : 18.0;
    final shape = RoundedRectangleBorder(borderRadius: _radius);

    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              strokeCap: StrokeCap.round,
              color: variant == SelloButtonVariant.outline ||
                      variant == SelloButtonVariant.ghost
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: iconSize),
                const SizedBox(width: 6),
              ],
              Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
            ],
          );

    final Widget button;
    if (_isPrimary) {
      button = _PrimaryButton(
        onPressed: loading ? null : onPressed,
        height: height,
        padding: padding,
        expanded: expanded,
        borderRadius: _radius,
        child: child,
      );
    } else {
      ButtonStyle materialStyle({
        Color? backgroundColor,
        Color? foregroundColor,
      }) {
        return ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(expanded ? double.infinity : 64, height),
          ),
          maximumSize: WidgetStatePropertyAll(
            Size(double.infinity, height),
          ),
          padding: WidgetStatePropertyAll(padding),
          shape: WidgetStatePropertyAll(shape),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: backgroundColor == null
              ? null
              : WidgetStatePropertyAll(backgroundColor),
          foregroundColor: foregroundColor == null
              ? null
              : WidgetStatePropertyAll(foregroundColor),
        );
      }

      final materialButton = switch (variant) {
        SelloButtonVariant.secondary => FilledButton.tonal(
            onPressed: loading ? null : onPressed,
            style: materialStyle(),
            child: child,
          ),
        SelloButtonVariant.outline => OutlinedButton(
            onPressed: loading ? null : onPressed,
            style: materialStyle().copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.85),
                  );
                }
                return const BorderSide(color: AppColors.outlineStrong);
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.textFaint;
                }
                return AppColors.textPrimary;
              }),
            ),
            child: child,
          ),
        SelloButtonVariant.ghost => TextButton(
            onPressed: loading ? null : onPressed,
            style: materialStyle(),
            child: child,
          ),
        SelloButtonVariant.danger => FilledButton(
            onPressed: loading ? null : onPressed,
            style: materialStyle(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onError,
            ),
            child: child,
          ),
        SelloButtonVariant.primary || SelloButtonVariant.gradient =>
          const SizedBox.shrink(),
      };

      button = SizedBox(height: height, child: materialButton);
    }

    if (expanded && !_isPrimary) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// Solid brand-purple CTA — hover darkens purple, never greys out.
class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.onPressed,
    required this.height,
    required this.padding,
    required this.borderRadius,
    required this.child,
    this.expanded = false,
  });

  final VoidCallback? onPressed;
  final double height;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Widget child;
  final bool expanded;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  Color get _fill {
    final scheme = Theme.of(context).colorScheme;
    if (!_enabled) return AppColors.outline;
    if (_pressed) return Color.lerp(scheme.primary, Colors.black, 0.18)!;
    if (_hovered) return Color.lerp(scheme.primary, Colors.white, 0.12)!;
    return scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: _enabled
          ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
          : null,
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: widget.expanded ? double.infinity : null,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: widget.borderRadius,
            boxShadow: _enabled
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(
                        alpha: _hovered ? 0.32 : 0.22,
                      ),
                      blurRadius: _hovered ? 16 : 12,
                      offset: Offset(0, _hovered ? 6 : 4),
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle(
            style: AppTypography.button.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: Theme.of(context).colorScheme.onPrimary,
                size: 18,
              ),
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
