import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/reports/application/hub_reports_provider.dart';
import 'package:sello/features/hub/reports/application/report_catalog.dart';
import 'package:sello/features/hub/reports/presentation/collections_report_dialog.dart';
import 'package:sello/features/hub/reports/presentation/report_charts.dart';
import 'package:sello/features/hub/reports/presentation/report_detail_dialog.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/collections_report.dart';
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
    if (definition.ownerOnly &&
        !(ref.read(currentRoleProvider)?.canViewInventoryValuation ?? false)) {
      return;
    }
    if (definition.id == kCollectionsReportId) {
      await showDialog<void>(
        context: context,
        builder: (_) => const CollectionsReportDialog(),
      );
      return;
    }

    final reports = ref.read(hubReportsProvider);
    final overview = reports.overview;
    if (overview == null) {
      final message = reports.isLoading
          ? 'Analytics are still loading. This report will open once they are ready.'
          : (reports.errorMessage ??
                'No report data yet. Complete a few sales and stock movements, then try again.');
      await _showReportMessage(
        context,
        definition: definition,
        message: message,
        onRetry: reports.isLoading
            ? null
            : () => ref.read(hubReportsProvider.notifier).refresh(),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => ReportDetailDialog(
        definition: definition,
        overview: overview,
        currencySymbol: _currencySymbol(ref),
        onDrillDown: () {
          final route =
              definition.drillRoute ??
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

  Future<void> _showReportMessage(
    BuildContext context, {
    required ReportDefinition definition,
    required String message,
    VoidCallback? onRetry,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => SelloFormDialog(
        title: definition.title,
        subtitle: definition.question,
        maxWidth: 480,
        body: Text(
          message,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (onRetry != null) ...[
              SelloButton(
                label: 'Retry',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onRetry();
                },
              ),
              const SizedBox(width: 8),
            ],
            SelloButton(
              label: 'Close',
              variant: SelloButtonVariant.outline,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
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
            showCategory: false,
            onQueryChanged: (query) =>
                ref.read(hubReportsProvider.notifier).setQuery(query),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.isLoading && overview == null)
            const SelloTableSkeleton(showMetrics: true, rows: 4, columns: 4)
          else if (state.errorMessage != null && overview == null)
            SelloEmptyState(
              title: 'Unable to load analytics',
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
            SelloReportKpiGrid(
              kpis: [
                for (final kpi in ref
                    .read(analyticsServiceProvider)
                    .buildKpis(
                      overview: overview,
                      currencySymbol: currency,
                      amountDisplay: ref
                          .watch(companySettingsProvider)
                          .amountDisplay,
                      includeInventoryValuation:
                          ref
                              .watch(currentRoleProvider)
                              ?.canViewInventoryValuation ??
                          false,
                    ))
                  if (kpi.id != 'top_customers' && kpi.id != 'top_products')
                    kpi,
              ],
              onKpiTap: (kpi) => _onKpiTap(context, ref, kpi),
            ),
            const SizedBox(height: AppSpacing.lg),
            SelloEqualHeightRow(
              gap: AppSpacing.lg,
              flexes: const [3, 2],
              minChildWidth: ResponsiveLayout.sectionCardMinWidth,
              children: [
                _SalesTrendCard(
                  overview: overview,
                  currencySymbol: currency,
                  points: ref
                      .read(analyticsServiceProvider)
                      .bucketTrend(
                        overview.salesTrend,
                        granularity: state.query.granularity,
                      ),
                  granularity: state.query.granularity,
                ),
                _StatusCard(overview: overview),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SelloEqualHeightRow(
              gap: AppSpacing.lg,
              minChildWidth: 260,
              children: [
                _RankCard(
                  title: 'Top sales representatives',
                  child: ReportComparisonBars(
                    items: overview.topSalesReps,
                    valueLabel: (i) =>
                        SelloFormatters.currency(i.value, symbol: currency),
                  ),
                  onOpen: () => _openReport(
                    context,
                    ref,
                    ReportCatalog.definitions.firstWhere(
                      (d) => d.id == 'sales_top_reps',
                    ),
                  ),
                ),
                _RankCard(
                  title: 'Best selling products',
                  child: ReportComparisonBars(
                    items: overview.topProducts,
                    valueLabel: (i) =>
                        SelloFormatters.currency(i.value, symbol: currency),
                  ),
                  onOpen: () => _openReport(
                    context,
                    ref,
                    ReportCatalog.definitions.firstWhere(
                      (d) => d.id == 'sales_top_products',
                    ),
                  ),
                ),
                _RankCard(
                  title: 'Top customers',
                  child: ReportComparisonBars(
                    items: overview.topCustomers,
                    valueLabel: (i) =>
                        SelloFormatters.currency(i.value, symbol: currency),
                  ),
                  onOpen: () => _openReport(
                    context,
                    ref,
                    ReportCatalog.definitions.firstWhere(
                      (d) => d.id == 'customers_top',
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: AppSpacing.lg),
          const SelloSectionHeader(title: 'Report library'),
          const SizedBox(height: AppSpacing.md),
          _ReportLibrary(
            categoryFilter: state.categoryFilter,
            onCategoryChanged: (value) =>
                ref.read(hubReportsProvider.notifier).setCategoryFilter(value),
            isOwner:
                ref.watch(currentRoleProvider)?.canViewInventoryValuation ??
                false,
            onOpen: (definition) => _openReport(context, ref, definition),
          ),
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
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      SelloFormatters.currency(
                        overview.salesInPeriod,
                        symbol: currencySymbol,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReportBarChart(points: points, currencySymbol: currencySymbol),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.title,
    required this.child,
    this.onOpen,
  });

  final String title;
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
                  ],
                ),
              ),
              if (onOpen != null)
                TextButton(onPressed: onOpen, child: const Text('Open')),
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
            'All-time order status',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          OrderStatusDonut(data: OrderStatusDonutData.fromCounts(counts)),
          if (overview.paymentStatusCounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Completed orders in the selected period — payment status',
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

class _ReportLibrary extends StatefulWidget {
  const _ReportLibrary({
    required this.categoryFilter,
    required this.onCategoryChanged,
    required this.onOpen,
    this.isOwner = false,
  });

  final ReportCategory? categoryFilter;
  final ValueChanged<ReportCategory?> onCategoryChanged;
  final ValueChanged<ReportDefinition> onOpen;
  final bool isOwner;

  @override
  State<_ReportLibrary> createState() => _ReportLibraryState();
}

class _ReportLibraryState extends State<_ReportLibrary> {
  String _query = '';

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
      'event' => Icons.event_outlined,
      'event_busy' => Icons.event_busy_outlined,
      'notifications' => Icons.notifications_outlined,
      'timeline' => Icons.timeline_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final matches = ReportCatalog.matching(
      query: _query,
      category: widget.categoryFilter,
      isOwner: widget.isOwner,
    );
    final categories = widget.categoryFilter == null
        ? ReportCategory.values
        : [widget.categoryFilter!];
    final searching = _query.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LibraryControls(
          category: widget.categoryFilter,
          onCategoryChanged: widget.onCategoryChanged,
          onQueryChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (matches.isEmpty)
          SelloEmptyState(
            title: 'No reports match',
            message: searching && widget.categoryFilter != null
                ? 'Nothing in ${widget.categoryFilter!.label} matches “${_query.trim()}”.'
                : searching
                ? 'No report title, description, or category matches “${_query.trim()}”.'
                : 'No reports are listed in ${widget.categoryFilter?.label ?? 'this category'}.',
            icon: Icons.search_off_rounded,
          )
        else
          for (final category in categories) ...[
            if (matches.any((item) => item.category == category)) ...[
              Text(
                category.label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final items = [
                    for (final item in matches)
                      if (item.category == category) item,
                  ];
                  final columns = ResponsiveLayout.columnsFor(
                    width: constraints.maxWidth,
                    itemCount: math.max(items.length, 1),
                    minItemWidth: ResponsiveLayout.sectionCardMinWidth,
                    maxColumns: 3,
                    gap: AppSpacing.md,
                  );
                  final width =
                      (constraints.maxWidth -
                          (AppSpacing.md * (columns - 1))) /
                      columns;
                  return Column(
                    children: [
                      for (var start = 0; start < items.length; start += columns) ...[
                        if (start > 0) const SizedBox(height: AppSpacing.md),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var i = start;
                                i < math.min(start + columns, items.length);
                                i++
                              ) ...[
                                if (i > start) const SizedBox(width: AppSpacing.md),
                                SizedBox(
                                  width: width,
                                  child: _LibraryCard(
                                    definition: items[i],
                                    icon: _iconFor(items[i].icon),
                                    onTap: items[i].available
                                        ? () => widget.onOpen(items[i])
                                        : null,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ],
      ],
    );
  }
}

class _LibraryControls extends StatelessWidget {
  const _LibraryControls({
    required this.category,
    required this.onCategoryChanged,
    required this.onQueryChanged,
  });

  final ReportCategory? category;
  final ValueChanged<ReportCategory?> onCategoryChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final search = SelloSearchBar(
      hint: 'Search reports',
      onChanged: onQueryChanged,
    );
    final filter = SizedBox(
      width: 220,
      child: SelloDropdown<ReportCategory?>(
        compact: true,
        value: category,
        items: [
          const DropdownMenuItem<ReportCategory?>(
            value: null,
            child: Text('All reports'),
          ),
          for (final item in ReportCategory.values)
            DropdownMenuItem(value: item, child: Text(item.label)),
        ],
        onChanged: onCategoryChanged,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = !constraints.maxWidth.isFinite || constraints.maxWidth < 640;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              filter,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            filter,
          ],
        );
      },
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
      emphasizeFocus: enabled,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: enabled
                  ? context.brandAccentContainer
                  : AppColors.surfaceMuted,
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
                  ],
                ),
                if (!definition.available) ...[
                  const SizedBox(height: 6),
                  const SelloMetaPill(value: 'Not available yet'),
                ],
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
