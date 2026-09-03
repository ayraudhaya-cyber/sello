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
    return SelloStatCard(
      label: kpi.label,
      value: kpi.value,
      icon: reportKpiIcon(kpi.iconKey),
      tone: colors.$1,
      hint: kpi.hint,
      onTap: onTap,
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
    return SelloStatCardGrid(
      maxColumns: 6,
      children: [
        for (final kpi in kpis)
          SelloReportKpiCard(
            kpi: kpi,
            onTap: onKpiTap == null ? null : () => onKpiTap!(kpi),
          ),
      ],
    );
  }
}
