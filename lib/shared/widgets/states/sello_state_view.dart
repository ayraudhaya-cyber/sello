import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';

enum SelloStateVariant { empty, error, loading }

/// Empty / error / loading placeholder for feature screens.
class SelloStateView extends StatelessWidget {
  const SelloStateView({
    super.key,
    required this.variant,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  const SelloStateView.empty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
  }) : variant = SelloStateVariant.empty;

  const SelloStateView.error({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.error_outline_rounded,
    this.actionLabel,
    this.onAction,
  }) : variant = SelloStateVariant.error;

  const SelloStateView.loading({
    super.key,
    this.title = 'Loading',
    this.message,
  })  : variant = SelloStateVariant.loading,
        icon = null,
        actionLabel = null,
        onAction = null;

  final SelloStateVariant variant;
  final String title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (variant == SelloStateVariant.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: context.texts.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(
                  color: context.selloColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final accent = variant == SelloStateVariant.error
        ? AppColors.error
        : AppColors.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: variant == SelloStateVariant.empty
                      ? AppGradients.primarySoft
                      : null,
                  color: variant == SelloStateVariant.error
                      ? AppColors.errorContainer
                      : null,
                  borderRadius: AppRadius.cardAll,
                ),
                child: Icon(icon, size: 32, color: accent),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.texts.titleLarge,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.selloColors.textSecondary,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                SelloButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  variant: SelloButtonVariant.gradient,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact inline loading indicator.
class SelloLoading extends StatelessWidget {
  const SelloLoading({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}
