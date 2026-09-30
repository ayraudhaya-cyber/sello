import 'package:flutter/material.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// "This product has variants" switch shown at the top of Add / Edit Product.
class ProductVariantsToggleCard extends StatelessWidget {
  const ProductVariantsToggleCard({
    super.key,
    required this.value,
    required this.onChanged,
    this.lockedNote,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Explains why the switch cannot be turned off (saved variants exist).
  final String? lockedNote;

  @override
  Widget build(BuildContext context) {
    final interactive = onChanged != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: value
            ? context.brandAccent.withValues(alpha: 0.05)
            : AppColors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: value
              ? context.brandAccent.withValues(alpha: 0.25)
              : AppColors.outlinePanel,
        ),
      ),
      child: InkWell(
        onTap: interactive ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Row(
          children: [
            SelloSwitch(value: value, onChanged: onChanged),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This product has variants',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lockedNote ??
                        'For sizes, colours or lengths. Each variant gets its '
                            'own item code, price and stock.',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductEditorTab {
  const ProductEditorTab({required this.label, this.hasError = false});

  final String label;
  final bool hasError;
}

/// Compact pill tabs for the Parent Details / Variants split.
class ProductEditorTabs extends StatelessWidget {
  const ProductEditorTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<ProductEditorTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _TabPill(
                tab: tabs[i],
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ProductEditorTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppCurves.standard,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            boxShadow: selected ? AppShadows.level1 : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? context.brandAccent
                      : AppColors.textSecondary,
                ),
              ),
              if (tab.hasError) ...[
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet note above parent fields that are managed per variant.
class HandledInVariantsNote extends StatelessWidget {
  const HandledInVariantsNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Handled in Variants',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.brandAccent,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Size and pricing are set individually for each variant.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
