import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

enum SelloCardElevation { flat, soft, raised }

/// Surface card with consistent radius, border, and optional soft shadow.
class SelloCard extends StatelessWidget {
  const SelloCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevation = SelloCardElevation.flat,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final SelloCardElevation elevation;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final shadows = switch (elevation) {
      SelloCardElevation.flat => AppShadows.none,
      SelloCardElevation.soft => AppShadows.level1,
      SelloCardElevation.raised => AppShadows.level2,
    };

    final content = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: borderColor ?? AppColors.outline,
          width: 1,
        ),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: content,
      ),
    );
  }
}

/// KPI / statistic tile for dashboards.
class SelloStatCard extends StatelessWidget {
  const SelloStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trendLabel,
    this.trendPositive,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? trendLabel;
  final bool? trendPositive;

  @override
  Widget build(BuildContext context) {
    final colors = context.selloColors;
    return SelloCard(
      elevation: SelloCardElevation.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.texts.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: context.texts.headlineMedium),
          if (trendLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              trendLabel!,
              style: context.texts.labelSmall?.copyWith(
                color: trendPositive == true
                    ? colors.success
                    : trendPositive == false
                        ? AppColors.error
                        : colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dashboard section card with title and optional action.
class SelloDashboardCard extends StatelessWidget {
  const SelloDashboardCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      elevation: SelloCardElevation.soft,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.texts.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: context.texts.bodySmall?.copyWith(
                          color: context.selloColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
