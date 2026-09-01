import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/widgets/cards/sello_card.dart';

IconData reportKpiIcon(String key) => switch (key) {
      'today' => Icons.today_outlined,
      'trending_up' => Icons.trending_up_rounded,
      'receipt' => Icons.receipt_long_outlined,
      'payments' => Icons.payments_outlined,
      'request_quote' => Icons.request_quote_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'warning' => Icons.warning_amber_rounded,
      'warehouse' => Icons.warehouse_outlined,
      'map' => Icons.map_outlined,
      'conversion' => Icons.trending_up_rounded,
      'groups' => Icons.groups_outlined,
      'inventory' => Icons.inventory_2_outlined,
      _ => Icons.insights_outlined,
    };

(Color accent, Color soft) reportKpiColors(
  BuildContext context,
  ReportKpiTone tone,
) =>
    switch (tone) {
      ReportKpiTone.primary => (
          context.brandAccent,
          context.brandAccentContainer,
        ),
      ReportKpiTone.finance => (AppColors.finance, AppColors.financeSoft),
      ReportKpiTone.success => (AppColors.success, AppColors.successContainer),
      ReportKpiTone.warning => (AppColors.warning, AppColors.warningContainer),
      ReportKpiTone.ops => (AppColors.ops, AppColors.opsSoft),
      ReportKpiTone.neutral => (AppColors.textSecondary, AppColors.surfaceMuted),
    };

/// Reusable analytics KPI — taps drill into domain records or open a report.
class SelloReportKpiCard extends StatelessWidget {
  const SelloReportKpiCard({
    super.key,
    required this.kpi,
    this.onTap,
  });

  final ReportKpi kpi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = reportKpiColors(context, kpi.tone);
    return SelloCard(
      enableHoverLift: onTap != null,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: colors.$2, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(reportKpiIcon(kpi.iconKey), size: 20, color: colors.$1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kpi.label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kpi.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (kpi.hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    kpi.hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}

/// Responsive grid of [SelloReportKpiCard]s.
class SelloReportKpiGrid extends StatelessWidget {
  const SelloReportKpiGrid({
    super.key,
    required this.kpis,
    this.onKpiTap,
  });

  final List<ReportKpi> kpis;
  final ValueChanged<ReportKpi>? onKpiTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;

    if (isMobile) {
      return Column(
        children: [
          for (var i = 0; i < kpis.length; i++) ...[
            SelloReportKpiCard(
              kpi: kpis[i],
              onTap: onKpiTap == null ? null : () => onKpiTap!(kpis[i]),
            ),
            if (i < kpis.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final columns = wide ? 4 : 2;
        final gap = AppSpacing.md;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final kpi in kpis)
              SizedBox(
                width: cardWidth,
                child: SelloReportKpiCard(
                  kpi: kpi,
                  onTap: onKpiTap == null ? null : () => onKpiTap!(kpi),
                ),
              ),
          ],
        );
      },
    );
  }
}
