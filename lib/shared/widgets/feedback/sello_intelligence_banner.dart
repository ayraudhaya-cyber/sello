import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/intelligence_insight.dart';
import 'package:sello/shared/widgets/cards/sello_card.dart';

/// Shared Sello Intelligence surface — lavender gradient, white type.
///
/// Shows a short ranked list of actionable insights (quality over quantity).
/// Canonical style from Sales Home; used across Owner, Manager, and Sales.
class SelloIntelligenceBanner extends StatelessWidget {
  const SelloIntelligenceBanner({
    super.key,
    this.message,
    this.insights = const [],
    this.title = 'Sello Intelligence',
    this.onInsightAction,
    this.maxVisible = 3,
  });

  /// Fallback copy when [insights] is empty (reserved / loading states).
  final String? message;
  final List<IntelligenceInsight> insights;
  final String title;
  final ValueChanged<IntelligenceInsight>? onInsightAction;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final visible = insights.take(maxVisible).toList(growable: false);

    // Empty state stays invisible — Intelligence earns space when it has advice.
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.intelligence,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelloIconBadge(
                  icon: Icons.auto_awesome_rounded,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  size: 34,
                  iconSize: 17,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: context.texts.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _InsightRow(
                insight: visible[i],
                onAction: onInsightAction == null
                    ? null
                    : () => onInsightAction!(visible[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.insight,
    this.onAction,
  });

  final IntelligenceInsight insight;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onAction,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: context.texts.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      insight.message,
                      style: context.texts.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (onAction != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    insight.actionLabel,
                    style: context.texts.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
