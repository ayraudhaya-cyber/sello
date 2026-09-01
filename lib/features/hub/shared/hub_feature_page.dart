import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/cards/sello_card.dart';
import 'package:sello/shared/widgets/layout/app_page_scaffold.dart';
import 'package:sello/shared/widgets/states/sello_skeleton.dart';

/// Designed Hub/Sales feature page shell — replaces bare construction placeholders.
class HubFeaturePage extends StatelessWidget {
  const HubFeaturePage({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.layers_outlined,
    this.tone,
    this.rows = const [],
    this.actions,
    this.showBreadcrumbs = true,
    this.loading = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color? tone;
  final List<HubFeatureRow> rows;
  final List<Widget>? actions;
  final bool showBreadcrumbs;

  /// Shows a table skeleton while real list data is fetching.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final accent = tone ?? context.brandAccent;
    return AppPageScaffold(
      title: title,
      subtitle: description,
      showBreadcrumbs: showBreadcrumbs,
      actions: actions,
      maxWidth: AppSpacing.contentMax,
      body: loading
          ? const SelloTableSkeleton(showMetrics: false, rows: 6, columns: 5)
          : SelloFadeIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelloCard(
                    enableHoverLift: false,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        SelloIconBadge(
                          icon: icon,
                          size: 48,
                          iconSize: 24,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.10),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: context.texts.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: context.selloColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.gap),
                    SelloCard(
                      enableHoverLift: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                color: AppColors.outlineSubtle,
                              ),
                            _FeatureRowTile(row: rows[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class HubFeatureRow {
  const HubFeatureRow({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.icon,
    this.tone,
  });

  final String title;
  final String subtitle;
  final String? trailing;
  final IconData? icon;
  final Color? tone;
}

class _FeatureRowTile extends StatelessWidget {
  const _FeatureRowTile({required this.row});

  final HubFeatureRow row;

  @override
  Widget build(BuildContext context) {
    final tone = row.tone ?? context.brandAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          if (row.icon != null) ...[
            SelloIconBadge(
              icon: row.icon!,
              size: 36,
              iconSize: 18,
              color: tone,
              backgroundColor: tone.withValues(alpha: 0.10),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.subtitle,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.selloColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (row.trailing != null)
            Text(
              row.trailing!,
              style: context.texts.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
