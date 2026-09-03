import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Prompt to continue a locally saved visit order draft.
class VisitDraftRestoreBanner extends StatelessWidget {
  const VisitDraftRestoreBanner({
    super.key,
    required this.itemQuantity,
    required this.total,
    required this.currencySymbol,
    required this.onContinue,
  });

  final num itemQuantity;
  final num total;
  final String currencySymbol;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final qty = itemQuantity.round();
    final itemsLabel = qty == 1 ? '1 item' : '$qty items';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.brandAccentContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: context.brandAccent.withValues(alpha: 0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Draft order',
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$itemsLabel · ${SelloFormatters.currency(total, symbol: currencySymbol)}',
                style: context.texts.bodyMedium?.copyWith(
                  color: context.selloColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SelloButton(
                label: 'Continue order',
                expanded: true,
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
