import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Text link shown beside list filters when the view is not the default.
class SelloClearFiltersLink extends StatelessWidget {
  const SelloClearFiltersLink({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: const Text(
        'Clear filters',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Kept for call sites that place the link under the toolbar.
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SelloClearFiltersLink(onPressed: onClear),
      ),
    );
  }
}
