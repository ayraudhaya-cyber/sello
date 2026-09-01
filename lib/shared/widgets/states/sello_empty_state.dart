import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';

enum EmptyStateTone { neutral, brand, warning }

/// Production empty-state block for lists and modules.
class SelloEmptyState extends StatelessWidget {
  const SelloEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.tone = EmptyStateTone.brand,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final EmptyStateTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final (Color accent, Color? fill, Gradient? gradient) = switch (tone) {
      EmptyStateTone.brand => (
          context.brandAccent,
          null,
          AppGradients.primarySoft,
        ),
      EmptyStateTone.neutral => (
          AppColors.textSecondary,
          AppColors.surfaceMuted,
          null,
        ),
      EmptyStateTone.warning => (
          AppColors.warning,
          AppColors.warningContainer,
          null,
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: fill ?? accent.withValues(alpha: 0.07),
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: accent.withValues(alpha: 0.1)),
                ),
                child: Icon(icon, size: 28, color: accent),
              ),
              const SizedBox(height: AppSpacing.mdPlus),
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
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SelloButton(
                      label: actionLabel!,
                      onPressed: onAction,
                      variant: SelloButtonVariant.primary,
                    ),
                    if (secondaryActionLabel != null &&
                        onSecondaryAction != null)
                      SelloButton(
                        label: secondaryActionLabel!,
                        onPressed: onSecondaryAction,
                        variant: SelloButtonVariant.outline,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
