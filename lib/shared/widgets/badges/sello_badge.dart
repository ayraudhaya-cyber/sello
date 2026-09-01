import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Semantic tone for status communication.
enum SelloStatusTone { neutral, brand, success, warning, danger, info }

/// Status pill used for record state (Active, Shipped, Draft, Overdue...).
///
/// Color is carried by a small dot and the label only; the surface stays a
/// near-white tint so rows of badges never overpower table content.
class SelloStatusBadge extends StatelessWidget {
  const SelloStatusBadge({
    super.key,
    required this.label,
    this.tone = SelloStatusTone.neutral,
    this.showDot = true,
    this.compact = false,
  });

  final String label;
  final SelloStatusTone tone;
  final bool showDot;

  /// Smaller, lighter treatment for dense field lists.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.selloColors;
    final accent = switch (tone) {
      SelloStatusTone.neutral => colors.textSecondary,
      SelloStatusTone.brand => context.brandAccent,
      SelloStatusTone.success => colors.success,
      SelloStatusTone.warning => colors.warning,
      SelloStatusTone.danger => AppColors.error,
      SelloStatusTone.info => colors.info,
    };
    final fill = accent.withValues(alpha: compact ? 0.05 : 0.07);
    final border = accent.withValues(alpha: compact ? 0.10 : 0.16);

    return Container(
      padding: EdgeInsets.only(
        left: showDot ? (compact ? 6 : AppSpacing.xs) : (compact ? 8 : 10),
        right: compact ? 8 : 10,
        top: compact ? 2 : 4,
        bottom: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: border, width: compact ? 0.8 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: compact ? 5 : 6,
              height: compact ? 5 : 6,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: compact ? 5 : 6),
          ],
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              fontSize: compact ? 10.5 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral metadata pill for secondary attributes (brand, unit, category).
class SelloMetaPill extends StatelessWidget {
  const SelloMetaPill({
    super.key,
    required this.value,
    this.label,
    this.icon,
  });

  final String value;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.selloColors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.textTertiary),
            const SizedBox(width: 6),
          ],
          if (label != null) ...[
            Text(
              label!,
              style: context.texts.labelSmall?.copyWith(
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: context.texts.labelMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
