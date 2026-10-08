import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';

/// Shown under a Hub toolbar when the list is not in its default view.
class SelloClearFiltersBar extends StatelessWidget {
  const SelloClearFiltersBar({
    super.key,
    required this.visible,
    required this.onClear,
    this.label = 'Filters are on',
  });

  final bool visible;
  final VoidCallback onClear;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.outlinePanel),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SelloButton(
              label: 'Clear filter',
              size: SelloButtonSize.small,
              variant: SelloButtonVariant.outline,
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}
