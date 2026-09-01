import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/reports/application/report_catalog.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Detail panel for a single report question — reuses overview aggregates.
class ReportDetailDialog extends StatelessWidget {
  const ReportDetailDialog({
    super.key,
    required this.definition,
    required this.overview,
    required this.currencySymbol,
    this.onExport,
    this.onDrillDown,
  });

  final ReportDefinition definition;
  final ReportsOverview overview;
  final String currencySymbol;
  final ValueChanged<ReportExportFormat>? onExport;
  final VoidCallback? onDrillDown;

  @override
  Widget build(BuildContext context) {
    final body = _bodyFor(definition.id);
    final canDrill = onDrillDown != null &&
        (definition.drillRoute != null ||
            definition.category != ReportCategory.notifications);

    return SelloFormDialog(
      title: definition.title,
      subtitle: definition.question,
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${overview.preset.label} · ${SelloFormatters.date(overview.from)} – ${SelloFormatters.date(overview.to)}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          body,
          if (canDrill) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDrillDown,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('View underlying records'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SelloIntelligenceBanner(
            message:
                'Sello Intelligence reuses this report’s analytics — AI '
                'explanations and forecasts will land here later.',
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Close',
        onCancel: () => Navigator.of(context).pop(),
        primaryLabel: 'Export',
        onPrimary: onExport == null
            ? null
            : () => _showExportSheet(context),
      ),
    );
  }

  void _showExportSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final format in ReportExportFormat.values)
              ListTile(
                leading: Icon(switch (format) {
                  ReportExportFormat.pdf => Icons.picture_as_pdf_outlined,
                  ReportExportFormat.excel => Icons.table_chart_outlined,
                  ReportExportFormat.csv => Icons.grid_on_outlined,
                  ReportExportFormat.print => Icons.print_outlined,
                }),
                title: Text(switch (format) {
                  ReportExportFormat.pdf => 'PDF',
                  ReportExportFormat.excel => 'Excel',
                  ReportExportFormat.csv => 'CSV',
                  ReportExportFormat.print => 'Print',
                }),
                subtitle: const Text(
                  'Architecture ready — PDF / Excel / CSV / scheduled email later',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onExport?.call(format);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _bodyFor(String id) {
    String money(num v) =>
        SelloFormatters.currency(v, symbol: currencySymbol);

    switch (id) {
      case 'sales_top_reps':
      case 'employees_performance':
        return _RankedList(
          items: overview.topSalesReps,
          valueLabel: (i) =>
              '${money(i.value)}${i.subtitle == null ? '' : ' · ${i.subtitle}'}',
          empty: 'No completed orders with sales reps in this period.',
        );
      case 'employees_visit_mix':
      case 'visits_rep_performance':
        if (overview.visitRepPerformance.isEmpty) {
          return const Text(
            'No completed visits in this period yet.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          );
        }
        return _MetricBlock(
          items: [
            for (final rep in overview.visitRepPerformance)
              (
                rep.name,
                '${rep.value.toInt()} visits'
                    '${rep.subtitle == null ? '' : ' · ${rep.subtitle}'}',
              ),
          ],
        );
      case 'schedules_coverage':
        return _MetricBlock(
          items: [
            ('Planned visits', '${overview.visitsScheduled}'),
            ('Completed', '${overview.visitsCompleted}'),
            ('Missed', '${overview.visitsMissed}'),
          ],
        );
      case 'schedules_missed':
        return _MetricBlock(
          items: [
            ('Missed visits', '${overview.visitsMissed}'),
            ('Completed', '${overview.visitsCompleted}'),
            ('Planned in period', '${overview.visitsScheduled}'),
          ],
        );
      case 'sales_daily':
      case 'sales_monthly':
      case 'sales_trend':
        return _MetricBlock(
          items: [
            ('Sales in period', money(overview.salesInPeriod)),
            ('Sales today', money(overview.salesToday)),
            ('Orders', '${overview.ordersInPeriod}'),
            ('Average order', money(overview.averageOrderValue)),
          ],
        );
      case 'sales_aov':
        return _MetricBlock(
          items: [
            ('Average order value', money(overview.averageOrderValue)),
            ('Orders in period', '${overview.ordersInPeriod}'),
            ('Total sales', money(overview.salesInPeriod)),
          ],
        );
      case 'sales_top_products':
      case 'products_best':
      case 'inventory_fast':
        return _RankedList(
          items: overview.topProducts,
          valueLabel: (i) => money(i.value),
        );
      case 'sales_top_categories':
      case 'products_categories':
        return _RankedList(
          items: overview.topCategories,
          valueLabel: (i) => money(i.value),
        );
      case 'customers_top':
      case 'customers_frequency':
        return _RankedList(
          items: overview.topCustomers,
          valueLabel: (i) =>
              '${money(i.value)}${i.subtitle == null ? '' : ' · ${i.subtitle}'}',
        );
      case 'customers_outstanding':
      case 'payments_outstanding':
        return _RankedList(
          items: overview.outstandingCustomers,
          valueLabel: (i) => money(i.value),
          empty: 'No outstanding balances.',
        );
      case 'customers_recent':
        return _RankedList(
          items: overview.recentCustomers,
          valueLabel: (i) => i.subtitle ?? 'New',
          empty: 'No new customers in the last 30 days.',
        );
      case 'customers_inactive':
        return _RankedList(
          items: overview.inactiveCustomers,
          valueLabel: (i) => i.subtitle ?? 'Inactive',
          empty: 'No inactive customers flagged.',
        );
      case 'inventory_stock':
      case 'inventory_value':
      case 'inventory_low':
      case 'inventory_out':
      case 'inventory_adjustments':
        return _MetricBlock(
          items: [
            ('SKUs tracked', '${overview.inventory.totalItems}'),
            ('Stock value', money(overview.inventory.stockValue)),
            ('Low stock', '${overview.inventory.lowStock}'),
            ('Out of stock', '${overview.inventory.outOfStock}'),
            ('Recent movements (7d)', '${overview.inventory.recentMovements}'),
          ],
        );
      case 'payments_paid':
      case 'payments_partial':
      case 'payments_methods':
      case 'payments_wallet':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetricBlock(
              items: [
                (
                  'Collection due',
                  money(overview.payments.outstandingReceivables)
                ),
                ('Collected today', money(overview.payments.collectedToday)),
                (
                  'Collections in period',
                  money(overview.collectionsInPeriod)
                ),
                ('Wallet issued', money(overview.payments.walletIssued)),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment methods',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            _RankedList(
              items: overview.paymentMethods,
              valueLabel: (i) => money(i.value),
              empty: 'No collections in this period.',
            ),
            if (overview.paymentStatusCounts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Orders by payment status',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in overview.paymentStatusCounts)
                    SelloMetaPill(value: '${item.label}: ${item.count}'),
                ],
              ),
            ],
          ],
        );
      case 'suppliers_products':
        return _RankedList(
          items: overview.productsBySupplier,
          valueLabel: (i) => i.subtitle ?? '${i.count ?? 0}',
          empty: 'No preferred supplier links yet.',
        );
      case 'suppliers_activity':
      case 'suppliers_recent':
        return _MetricBlock(
          items: [
            ('Total suppliers', '${overview.suppliers.total}'),
            ('Active', '${overview.suppliers.active}'),
            ('Added last 30 days', '${overview.suppliers.recentlyAdded}'),
          ],
        );
      case 'visits_coverage':
        return _MetricBlock(
          items: [
            ('Visits completed', '${overview.visitsCompleted}'),
            ('Visits missed', '${overview.visitsMissed}'),
            ('Planned in period', '${overview.visitsScheduled}'),
          ],
        );
      case 'visits_conversion':
        return _MetricBlock(
          items: [
            ('Visits completed', '${overview.visitsCompleted}'),
            ('Visits with orders', '${overview.visitsWithOrders}'),
            (
              'Conversion rate',
              '${(overview.visitConversionRate * 100).toStringAsFixed(0)}%',
            ),
          ],
        );
      case 'visits_collections':
        return _MetricBlock(
          items: [
            ('Visits completed', '${overview.visitsCompleted}'),
            ('Visits with payments', '${overview.visitsWithPayments}'),
            (
              'Collection rate',
              '${(overview.visitCollectionRate * 100).toStringAsFixed(0)}%',
            ),
            (
              'Collections on visits',
              money(overview.visitCollectionsAmount),
            ),
            (
              'Avg collection / visit',
              money(overview.collectionsPerVisit),
            ),
          ],
        );
      case 'visits_orders_per_visit':
        return _MetricBlock(
          items: [
            ('Visits completed', '${overview.visitsCompleted}'),
            ('Orders linked to visits', '${overview.visitOrdersLinked}'),
            (
              'Orders per visit',
              overview.ordersPerVisit.toStringAsFixed(2),
            ),
          ],
        );
      case 'notifications_volume':
      case 'activity_feed':
        return const Text(
          'Notification Center and company activity are live. '
          'Volume charts and digests will deepen here next.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        );
      default:
        final def = ReportCatalog.definitions
            .where((d) => d.id == id)
            .firstOrNull;
        if (def != null && !def.available) {
          return const Text(
            'This report is reserved for a later release. The data model is '
            'already prepared where possible.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          );
        }
        return const Text(
          'Open this report from the dashboard cards for a focused view.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        );
    }
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  item.$1,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                item.$2,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _RankedList extends StatelessWidget {
  const _RankedList({
    required this.items,
    required this.valueLabel,
    this.empty = 'No data for this period.',
  });

  final List<ReportNamedValue> items;
  final String Function(ReportNamedValue) valueLabel;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        empty,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${i + 1}.',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i].name,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (items[i].subtitle != null)
                      Text(
                        items[i].subtitle!,
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
                valueLabel(items[i]),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
