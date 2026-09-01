import 'package:sello/core/router/route_paths.dart';
import 'package:sello/data/repositories/report_repository.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Shared analytics platform — single source of truth for Reports + Intelligence.
///
/// Composes [ReportRepository]; never duplicates domain math. Future dashboards,
/// scheduled digests, forecasting, and custom layouts should call here.
class AnalyticsService {
  AnalyticsService({ReportRepository? reports})
      : _reports = reports ?? ReportRepository();

  final ReportRepository _reports;

  /// Load the shared overview for any surface (Hub Reports, Intelligence, …).
  Future<ReportsOverview> fetchOverview({
    required String companyId,
    ReportQuery query = const ReportQuery(),
  }) {
    return _reports.fetchOverview(
      companyId: companyId,
      branchId: query.branchId,
      preset: query.preset,
      query: query,
    );
  }

  /// Reusable KPI cards for dashboards — drill routes are Hub-oriented.
  List<ReportKpi> buildKpis({
    required ReportsOverview overview,
    required String currencySymbol,
  }) {
    String money(num v) =>
        SelloFormatters.currency(v, symbol: currencySymbol);
    final spark = [
      for (final p in overview.salesTrend.take(14)) p.sales.toDouble(),
    ];

    return [
      ReportKpi(
        id: 'sales_today',
        label: 'Sales today',
        value: money(overview.salesToday),
        hint: overview.preset.label,
        iconKey: 'today',
        tone: ReportKpiTone.primary,
        drillRoute: RoutePaths.hubOrders,
        reportId: 'sales_daily',
        sparkPoints: spark,
      ),
      ReportKpi(
        id: 'revenue',
        label: 'Revenue',
        value: money(overview.salesInPeriod),
        hint: 'Completed sales · ${overview.preset.label}',
        iconKey: 'trending_up',
        tone: ReportKpiTone.primary,
        drillRoute: RoutePaths.hubOrders,
        reportId: 'sales_monthly',
        sparkPoints: spark,
      ),
      ReportKpi(
        id: 'orders',
        label: 'Orders',
        value: '${overview.ordersInPeriod}',
        hint: 'Completed in period',
        iconKey: 'receipt',
        tone: ReportKpiTone.ops,
        drillRoute: RoutePaths.hubOrders,
        reportId: 'sales_daily',
      ),
      ReportKpi(
        id: 'aov',
        label: 'Average order value',
        value: money(overview.averageOrderValue),
        hint: '${overview.ordersInPeriod} orders',
        iconKey: 'payments',
        tone: ReportKpiTone.ops,
        drillRoute: RoutePaths.hubOrders,
        reportId: 'sales_aov',
      ),
      ReportKpi(
        id: 'collections_due',
        label: 'Outstanding collections',
        value: money(overview.payments.outstandingReceivables),
        hint: 'Customer receivables',
        iconKey: 'request_quote',
        tone: ReportKpiTone.finance,
        drillRoute: RoutePaths.hubPayments,
        reportId: 'payments_outstanding',
      ),
      ReportKpi(
        id: 'collections_period',
        label: 'Collections',
        value: money(overview.collectionsInPeriod),
        hint: 'Receipts in period',
        iconKey: 'wallet',
        tone: ReportKpiTone.success,
        drillRoute: RoutePaths.hubPayments,
        reportId: 'payments_methods',
      ),
      ReportKpi(
        id: 'low_stock',
        label: 'Products low in stock',
        value: '${overview.inventory.lowStock}',
        hint: '${overview.inventory.outOfStock} out of stock',
        iconKey: 'warning',
        tone: ReportKpiTone.warning,
        drillRoute: RoutePaths.hubInventory,
        reportId: 'inventory_low',
      ),
      ReportKpi(
        id: 'inventory_value',
        label: 'Inventory value',
        value: money(overview.inventory.stockValue),
        hint: 'At cost',
        iconKey: 'warehouse',
        tone: ReportKpiTone.success,
        drillRoute: RoutePaths.hubInventory,
        reportId: 'inventory_value',
      ),
      ReportKpi(
        id: 'visits_completed',
        label: 'Visits completed',
        value: '${overview.visitsCompleted}',
        hint: '${overview.visitsMissed} missed · ${overview.visitsScheduled} planned',
        iconKey: 'map',
        tone: ReportKpiTone.ops,
        drillRoute: RoutePaths.hubVisits,
        reportId: 'visits_coverage',
      ),
      ReportKpi(
        id: 'visit_conversion',
        label: 'Visit conversion',
        value: '${(overview.visitConversionRate * 100).round()}%',
        hint: '${overview.visitsWithOrders} visits with orders',
        iconKey: 'conversion',
        tone: ReportKpiTone.primary,
        drillRoute: RoutePaths.hubVisits,
        reportId: 'visits_conversion',
      ),
      ReportKpi(
        id: 'top_customers',
        label: 'Top customers',
        value: overview.topCustomers.isEmpty
            ? '—'
            : overview.topCustomers.first.name,
        hint: overview.topCustomers.isEmpty
            ? 'No sales in period'
            : money(overview.topCustomers.first.value),
        iconKey: 'groups',
        tone: ReportKpiTone.neutral,
        drillRoute: RoutePaths.hubCustomers,
        reportId: 'customers_top',
      ),
      ReportKpi(
        id: 'top_products',
        label: 'Top products',
        value: overview.topProducts.isEmpty
            ? '—'
            : overview.topProducts.first.name,
        hint: overview.topProducts.isEmpty
            ? 'No product sales'
            : money(overview.topProducts.first.value),
        iconKey: 'inventory',
        tone: ReportKpiTone.neutral,
        drillRoute: RoutePaths.hubProducts,
        reportId: 'sales_top_products',
      ),
    ];
  }

  /// Bucket daily trend points into weekly / monthly aggregates.
  List<ReportTrendPoint> bucketTrend(
    List<ReportTrendPoint> daily, {
    ReportTrendGranularity granularity = ReportTrendGranularity.daily,
  }) {
    if (granularity == ReportTrendGranularity.daily || daily.isEmpty) {
      return daily;
    }

    final buckets = <DateTime, ({num sales, int orders})>{};
    for (final point in daily) {
      final local = point.day.toLocal();
      final key = switch (granularity) {
        ReportTrendGranularity.daily =>
          DateTime(local.year, local.month, local.day),
        ReportTrendGranularity.weekly => () {
            final start = DateTime(local.year, local.month, local.day);
            return start.subtract(Duration(days: start.weekday - 1));
          }(),
        ReportTrendGranularity.monthly => DateTime(local.year, local.month, 1),
      };
      final existing = buckets[key];
      buckets[key] = (
        sales: (existing?.sales ?? 0) + point.sales,
        orders: (existing?.orders ?? 0) + point.orders,
      );
    }

    final keys = buckets.keys.toList()..sort();
    return [
      for (final key in keys)
        ReportTrendPoint(
          day: key.toUtc(),
          sales: buckets[key]!.sales,
          orders: buckets[key]!.orders,
        ),
    ];
  }

  /// Resolve drill-down for a catalog report id.
  String? drillRouteForReport(String reportId) {
    return switch (reportId) {
      'sales_daily' ||
      'sales_monthly' ||
      'sales_trend' ||
      'sales_aov' ||
      'sales_top_reps' ||
      'employees_performance' =>
        RoutePaths.hubOrders,
      'sales_top_products' ||
      'products_best' ||
      'products_categories' ||
      'sales_top_categories' =>
        RoutePaths.hubProducts,
      'customers_top' ||
      'customers_frequency' ||
      'customers_outstanding' ||
      'customers_recent' ||
      'customers_inactive' =>
        RoutePaths.hubCustomers,
      'inventory_stock' ||
      'inventory_value' ||
      'inventory_low' ||
      'inventory_out' ||
      'inventory_fast' ||
      'inventory_adjustments' =>
        RoutePaths.hubInventory,
      'payments_paid' ||
      'payments_partial' ||
      'payments_outstanding' ||
      'payments_methods' ||
      'payments_wallet' =>
        RoutePaths.hubPayments,
      'suppliers_products' ||
      'suppliers_activity' ||
      'suppliers_recent' =>
        RoutePaths.hubSuppliers,
      'visits_coverage' ||
      'visits_conversion' ||
      'visits_collections' ||
      'visits_orders_per_visit' ||
      'visits_rep_performance' =>
        RoutePaths.hubVisits,
      'schedules_coverage' || 'schedules_missed' => RoutePaths.hubSchedule,
      'notifications_volume' || 'activity_feed' => RoutePaths.hubDashboard,
      _ => null,
    };
  }

  /// Export seam — delegates to repository (generation ships later).
  Future<String?> prepareExport(ReportExportRequest request) =>
      _reports.prepareExport(request);

  /// Future: branch comparison matrix — reserved.
  Future<List<ReportNamedValue>> branchComparison({
    required String companyId,
    ReportQuery query = const ReportQuery(),
  }) async {
    return const [];
  }

  /// Future: forecasting hints — reserved for Intelligence / AI.
  Future<List<ReportNamedValue>> forecastHints({
    required String companyId,
    ReportQuery query = const ReportQuery(),
  }) async {
    return const [];
  }
}
