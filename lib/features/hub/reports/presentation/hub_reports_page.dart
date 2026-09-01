import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/reports/application/hub_reports_provider.dart';
import 'package:sello/features/hub/reports/application/report_catalog.dart';
import 'package:sello/features/hub/reports/presentation/report_charts.dart';
import 'package:sello/features/hub/reports/presentation/report_detail_dialog.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/intelligence/application/intelligence_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubReportsPage extends ConsumerWidget {
  const HubReportsPage({super.key});

  String _currencySymbol(WidgetRef ref) {
    return SelloFormatters.currencySymbol(
      ref.read(companySettingsProvider).currency,
    );
  }

  Future<void> _openReport(
    BuildContext context,
    WidgetRef ref,
    ReportDefinition definition,
  ) async {
    final overview = ref.read(hubReportsProvider).overview;
    if (overview == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) => ReportDetailDialog(
        definition: definition,
        overview: overview,
        currencySymbol: _currencySymbol(ref),
        onExport: (format) async {
          final message = await ref
              .read(hubReportsProvider.notifier)
              .requestExport(reportId: definition.id, format: format);
          if (!context.mounted) return;
          if (message != null) {
            SelloSnackbars.info(context, message);
          }
        },
        onDrillDown: () {
          final route = definition.drillRoute ??
              ref
                  .read(analyticsServiceProvider)
                  .drillRouteForReport(definition.id);
          if (route != null) {
            Navigator.of(context).pop();
            context.go(route);
          }
        },
      ),
    );
  }

  void _onKpiTap(BuildContext context, WidgetRef ref, ReportKpi kpi) {
    final reportId = kpi.reportId;
    if (reportId != null) {
      final match = ReportCatalog.definitions
          .where((d) => d.id == reportId)
          .firstOrNull;
      if (match != null) {
        _openReport(context, ref, match);
        return;
      }
    }
    final route = kpi.drillRoute;
    if (route != null) context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hubReportsProvider);
    ref.watch(hubSettingsProvider);
    final currency = _currencySymbol(ref);
    final overview = state.overview;

    return AppPageScaffold(
      title: 'Reports',
      subtitle:
          'Reusable analytics from live sales, visits, inventory, payments, and suppliers.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      actions: [
        SelloButton(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          variant: SelloButtonVariant.outline,
          onPressed: state.isLoading
              ? null
              : () => ref.read(hubReportsProvider.notifier).refresh(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloReportFiltersBar(
            query: state.query,
            categoryFilter: state.categoryFilter,
            onQueryChanged: (query) =>
                ref.read(hubReportsProvider.notifier).setQuery(query),
            onCategoryChanged: (value) =>
                ref.read(hubReportsProvider.notifier).setCategoryFilter(value),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.isLoading && overview == null)
            const SelloTableSkeleton(showMetrics: true, rows: 4, columns: 4)
          else if (state.errorMessage != null)
            SelloEmptyState(
              title: 'Unable to load reports',
              message: state.errorMessage,
              icon: Icons.error_outline_rounded,
              actionLabel: 'Retry',
              onAction: () => ref.read(hubReportsProvider.notifier).refresh(),
            )
          else if (overview == null)
            const SelloEmptyState(
              title: 'No report data yet',
              message:
                  'Complete a few sales and stock movements — insights appear here.',
              icon: Icons.insights_outlined,
            )
          else ...[
            Consumer(
              builder: (context, ref, _) {
                final intel = ref.watch(hubIntelligenceProvider);
                final session = ref.watch(currentSessionProvider);
                final role = session?.appRole;
                return intel.when(
                  data: (snap) => SelloIntelligenceBanner(
                    insights: snap.insights,
                    message:
                        'Sello Intelligence reuses these same analytics — '
                        'forecasting and AI digests come next.',
                    onInsightAction: role == null
                        ? null
                        : (insight) => context.go(insight.routeFor(role)),
                  ),
                  loading: () => const SelloIntelligenceBanner(
                    message: 'Analysing sales, stock, visits, and collections…',
                  ),
                  error: (_, _) => const SelloIntelligenceBanner(
                    message:
                        'Sello Intelligence reuses these same analytics — '
                        'forecasting and AI digests come next.',
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            SelloReportKpiGrid(
              kpis: ref.read(analyticsServiceProvider).buildKpis(
                    overview: overview,
                    currencySymbol: currency,
                  ),
              onKpiTap: (kpi) => _onKpiTap(context, ref, kpi),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SalesTrendCard(
              overview: overview,
              currencySymbol: currency,
              points: ref.read(analyticsServiceProvider).bucketTrend(
                    overview.salesTrend,
                    granularity: state.query.granularity,
                  ),
              granularity: state.query.granularity,
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveBuilder(
              mobile: (_) => Column(
                children: [
                  _RankCard(
                    title: 'Best selling products',
                    subtitle: 'Revenue leaders this period',
                    child: ReportComparisonBars(
                      items: overview.topProducts,
                      valueLabel: (i) => SelloFormatters.currency(
                        i.value,
                        symbol: currency,
                      ),
                    ),
                    onOpen: () => _openReport(
                      context,
                      ref,
                      ReportCatalog.definitions
                          .firstWhere((d) => d.id == 'sales_top_products'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RankCard(
                    title: 'Top customers',
                    subtitle: 'Highest completed order value',
                    child: ReportComparisonBars(
                      items: overview.topCustomers,
                      valueLabel: (i) => SelloFormatters.currency(
                        i.value,
                        symbol: currency,
                      ),
                    ),
                    onOpen: () => _openReport(
                      context,
                      ref,
                      ReportCatalog.definitions
                          .firstWhere((d) => d.id == 'customers_top'),
                    ),
                  ),
                ],
              ),
              tablet: (_) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _RankCard(
                      title: 'Best selling products',
                      subtitle: 'Revenue leaders this period',
                      child: ReportComparisonBars(
                        items: overview.topProducts,
                        valueLabel: (i) => SelloFormatters.currency(
                          i.value,
                          symbol: currency,
                        ),
                      ),
                      onOpen: () => _openReport(
                        context,
                        ref,
                        ReportCatalog.definitions
                            .firstWhere((d) => d.id == 'sales_top_products'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _RankCard(
                      title: 'Top customers',
                      subtitle: 'Highest completed order value',
                      child: ReportComparisonBars(
                        items: overview.topCustomers,
                        valueLabel: (i) => SelloFormatters.currency(
                          i.value,
                          symbol: currency,
                        ),
                      ),
                      onOpen: () => _openReport(
                        context,
                        ref,
                        ReportCatalog.definitions
                            .firstWhere((d) => d.id == 'customers_top'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveBuilder(
              mobile: (_) => Column(
                children: [
                  _StatusCard(overview: overview),
                  const SizedBox(height: AppSpacing.lg),
                  _RankCard(
                    title: 'Top sales representatives',
                    subtitle: 'Completed order value by rep',
                    child: ReportComparisonBars(
                      items: overview.topSalesReps,
                      valueLabel: (i) => SelloFormatters.currency(
                        i.value,
                        symbol: currency,
                      ),
                    ),
                    onOpen: () => _openReport(
                      context,
                      ref,
                      ReportCatalog.definitions
                          .firstWhere((d) => d.id == 'sales_top_reps'),
                    ),
                  ),
                ],
              ),
              tablet: (_) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _StatusCard(overview: overview)),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _RankCard(
                      title: 'Top sales representatives',
                      subtitle: 'Completed order value by rep',
                      child: ReportComparisonBars(
                        items: overview.topSalesReps,
                        valueLabel: (i) => SelloFormatters.currency(
                          i.value,
                          symbol: currency,
                        ),
                      ),
                      onOpen: () => _openReport(
                        context,
                        ref,
                        ReportCatalog.definitions
                            .firstWhere((d) => d.id == 'sales_top_reps'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SelloSectionHeader(
              title: 'Report library',
              subtitle:
                  'Each report answers one business question. Open any card for detail and export options.',
            ),
            const SizedBox(height: AppSpacing.md),
            _ReportLibrary(
              categoryFilter: state.categoryFilter,
              onOpen: (definition) => _openReport(context, ref, definition),
            ),
          ],
        ],
      ),
    );
  }
}


class _SalesTrendCard extends StatelessWidget {
  const _SalesTrendCard({
    required this.overview,
    required this.currencySymbol,
    required this.points,
    required this.granularity,
  });

  final ReportsOverview overview;
  final String currencySymbol;
  final List<ReportTrendPoint> points;
  final ReportTrendGranularity granularity;

  @override
  Widget build(BuildContext context) {
    final grainLabel = switch (granularity) {
      ReportTrendGranularity.daily => 'by day',
      ReportTrendGranularity.weekly => 'by week',
      ReportTrendGranularity.monthly => 'by month',
    };
    return SelloCard(
      enableHoverLift: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sales trend',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Completed order value $grainLabel',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                SelloFormatters.currency(
                  overview.salesInPeriod,
                  symbol: currencySymbol,
                ),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReportBarChart(points: points),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onOpen,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      enableHoverLift: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpen != null)
                TextButton(
                  onPressed: onOpen,
                  child: const Text('Open'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.overview});

  final ReportsOverview overview;

  @override
  Widget build(BuildContext context) {
    final counts = overview.orderCounts;
    return SelloCard(
      enableHoverLift: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Orders by status',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'All-time operational mix (from Orders)',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SelloMetaPill(value: 'Total ${counts.total}'),
              SelloMetaPill(value: 'Open ${counts.draft}'),
              SelloMetaPill(value: 'Completed ${counts.completed}'),
              SelloMetaPill(value: 'Cancelled ${counts.cancelled}'),
            ],
          ),
          if (overview.paymentStatusCounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Completed orders — payment status',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in overview.paymentStatusCounts)
                  SelloMetaPill(value: '${item.label} ${item.count}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportLibrary extends StatelessWidget {
  const _ReportLibrary({
    required this.categoryFilter,
    required this.onOpen,
  });

  final ReportCategory? categoryFilter;
  final ValueChanged<ReportDefinition> onOpen;

  IconData _iconFor(String key) {
    return switch (key) {
      'trending_up' => Icons.trending_up_rounded,
      'calendar_month' => Icons.calendar_month_outlined,
      'show_chart' => Icons.show_chart_rounded,
      'payments' => Icons.payments_outlined,
      'inventory_2' => Icons.inventory_2_outlined,
      'category' => Icons.category_outlined,
      'groups' => Icons.groups_outlined,
      'repeat' => Icons.repeat_rounded,
      'account_balance_wallet' => Icons.account_balance_wallet_outlined,
      'person_add' => Icons.person_add_alt_1_outlined,
      'person_off' => Icons.person_off_outlined,
      'star' => Icons.star_outline_rounded,
      'pie_chart' => Icons.pie_chart_outline_rounded,
      'warehouse' => Icons.warehouse_outlined,
      'attach_money' => Icons.attach_money_rounded,
      'warning_amber' => Icons.warning_amber_rounded,
      'remove_shopping_cart' => Icons.remove_shopping_cart_outlined,
      'speed' => Icons.speed_rounded,
      'hourglass_bottom' => Icons.hourglass_bottom_rounded,
      'sync_alt' => Icons.sync_alt_rounded,
      'check_circle' => Icons.check_circle_outline,
      'pending' => Icons.pending_outlined,
      'request_quote' => Icons.request_quote_outlined,
      'credit_card' => Icons.credit_card_outlined,
      'savings' => Icons.savings_outlined,
      'local_shipping' => Icons.local_shipping_outlined,
      'insights' => Icons.insights_outlined,
      'add_business' => Icons.add_business_outlined,
      'receipt_long' => Icons.receipt_long_outlined,
      'badge' => Icons.badge_outlined,
      'map' => Icons.map_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final categories = categoryFilter == null
        ? ReportCategory.values
        : [categoryFilter!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in categories) ...[
          Text(
            category.label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (!category.isAvailable)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Coming soon — structure reserved.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 640
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - (AppSpacing.md * (columns - 1))) /
                      columns;
              final items = ReportCatalog.forCategory(category);
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: width,
                      child: _LibraryCard(
                        definition: item,
                        icon: _iconFor(item.icon),
                        onTap: item.available ? () => onOpen(item) : null,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.definition,
    required this.icon,
    this.onTap,
  });

  final ReportDefinition definition;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SelloCard(
      onTap: onTap,
      enableHoverLift: enabled,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled ? context.brandAccentContainer : AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? context.brandAccent : AppColors.textFaint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        definition.title,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (!definition.available)
                      const SelloMetaPill(value: 'Soon'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  definition.question,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
