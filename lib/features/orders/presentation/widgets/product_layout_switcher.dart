import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/catalog/sales_catalog_layout_preferences.dart';

/// Compact segmented control for catalog grid / list layouts.
class ProductLayoutSwitcher extends StatelessWidget {
  const ProductLayoutSwitcher({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ProductCatalogLayoutMode mode;
  final ValueChanged<ProductCatalogLayoutMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            tooltip: 'Two-column grid',
            icon: Icons.grid_view_rounded,
            selected: mode == ProductCatalogLayoutMode.gridTwo,
            onTap: () => onChanged(ProductCatalogLayoutMode.gridTwo),
          ),
          _ModeButton(
            tooltip: 'Single-column cards',
            icon: Icons.view_agenda_outlined,
            selected: mode == ProductCatalogLayoutMode.gridOne,
            onTap: () => onChanged(ProductCatalogLayoutMode.gridOne),
          ),
          _ModeButton(
            tooltip: 'List view',
            icon: Icons.view_list_rounded,
            selected: mode == ProductCatalogLayoutMode.list,
            onTap: () => onChanged(ProductCatalogLayoutMode.list),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? context.brandAccentContainer.withValues(alpha: 0.85)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: SizedBox(
            width: 40,
            height: 36,
            child: Icon(
              icon,
              size: 20,
              color: selected ? context.brandAccent : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
