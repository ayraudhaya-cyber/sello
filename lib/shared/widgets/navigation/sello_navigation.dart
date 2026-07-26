import 'package:flutter/material.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/theme/theme.dart';

class SelloNavDestination {
  const SelloNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.location,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String location;
}

/// Official Sello mark + optional wordmark.
class SelloBrandMark extends StatelessWidget {
  const SelloBrandMark({
    super.key,
    this.compact = false,
    this.hub = false,
    this.size,
  });

  final bool compact;
  final bool hub;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final title = hub ? 'Sello Hub' : 'Sello';
    final logoSize = size ?? (compact ? 32.0 : 36.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.22),
            boxShadow: AppShadows.level1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            AppAssets.logo,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: context.texts.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ],
    );
  }
}

/// Desktop / tablet permanent sidebar for Hub.
class SelloSideNav extends StatelessWidget {
  const SelloSideNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.footer,
    this.width = 260,
  });

  final List<SelloNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: const SelloBrandMark(hub: true),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              itemCount: destinations.length,
              itemBuilder: (context, index) {
                final item = destinations[index];
                final selected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Material(
                    color: selected
                        ? AppColors.primaryContainer
                        : Colors.transparent,
                    borderRadius: AppRadius.buttonAll,
                    child: InkWell(
                      onTap: () => onDestinationSelected(index),
                      borderRadius: AppRadius.buttonAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected ? item.selectedIcon : item.icon,
                              size: 22,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                item.label,
                                style: context.texts.labelLarge?.copyWith(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: footer,
            ),
        ],
      ),
    );
  }
}
