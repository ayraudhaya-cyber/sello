import 'package:equatable/equatable.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/supplier_summary.dart';

/// Preset windows for report filters — shared across report surfaces.
enum ReportDatePreset {
  today,
  last7Days,
  thisWeek,
  thisMonth,
  last30Days,
  custom,
}

extension ReportDatePresetX on ReportDatePreset {
  String get label => switch (this) {
        ReportDatePreset.today => 'Today',
        ReportDatePreset.last7Days => 'Last 7 days',
        ReportDatePreset.thisWeek => 'This week',
        ReportDatePreset.thisMonth => 'This month',
        ReportDatePreset.last30Days => 'Last 30 days',
        ReportDatePreset.custom => 'Custom range',
      };

  /// Inclusive local-day window converted to UTC bounds for queries.
  ///
  /// [customFrom]/[customTo] are used when preset is [ReportDatePreset.custom].
  ({DateTime from, DateTime to}) bounds({
    DateTime? now,
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final local = (now ?? DateTime.now()).toLocal();
    final startOfToday = DateTime(local.year, local.month, local.day);
    final endOfToday = startOfToday
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));

    switch (this) {
      case ReportDatePreset.today:
        return (from: startOfToday.toUtc(), to: endOfToday.toUtc());
      case ReportDatePreset.last7Days:
        return (
          from: startOfToday.subtract(const Duration(days: 6)).toUtc(),
          to: endOfToday.toUtc(),
        );
      case ReportDatePreset.thisWeek:
        final weekday = startOfToday.weekday; // Mon=1 … Sun=7
        final weekStart = startOfToday.subtract(Duration(days: weekday - 1));
        return (from: weekStart.toUtc(), to: endOfToday.toUtc());
      case ReportDatePreset.thisMonth:
        return (
          from: DateTime(local.year, local.month, 1).toUtc(),
          to: endOfToday.toUtc(),
        );
      case ReportDatePreset.last30Days:
        return (
          from: startOfToday.subtract(const Duration(days: 29)).toUtc(),
          to: endOfToday.toUtc(),
        );
      case ReportDatePreset.custom:
        final fromLocal = customFrom?.toLocal() ?? startOfToday;
        final toLocal = customTo?.toLocal() ?? endOfToday;
        final fromDay = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);
        final toDay = DateTime(toLocal.year, toLocal.month, toLocal.day)
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        return (from: fromDay.toUtc(), to: toDay.toUtc());
    }
  }
}

/// How trend points are bucketed for charts and digests.
enum ReportTrendGranularity {
  daily,
  weekly,
  monthly,
}

extension ReportTrendGranularityX on ReportTrendGranularity {
  String get label => switch (this) {
        ReportTrendGranularity.daily => 'Daily',
        ReportTrendGranularity.weekly => 'Weekly',
        ReportTrendGranularity.monthly => 'Monthly',
      };
}

/// Future comparison modes — UI may offer; calculation ships later.
enum ReportComparisonMode {
  none,
  previousPeriod,
  yearOverYear,
}

extension ReportComparisonModeX on ReportComparisonMode {
  String get label => switch (this) {
        ReportComparisonMode.none => 'No comparison',
        ReportComparisonMode.previousPeriod => 'Previous period',
        ReportComparisonMode.yearOverYear => 'Year over year',
      };
}

/// Shared filter bag for every report surface (Hub, Intelligence, future Sales).
class ReportQuery extends Equatable {
  const ReportQuery({
    this.preset = ReportDatePreset.thisMonth,
    this.customFrom,
    this.customTo,
    this.granularity = ReportTrendGranularity.daily,
    this.comparison = ReportComparisonMode.none,
    this.branchId,
    this.employeeId,
    this.customerId,
    this.supplierId,
    this.categoryId,
    this.status,
  });

  final ReportDatePreset preset;
  final DateTime? customFrom;
  final DateTime? customTo;
  final ReportTrendGranularity granularity;
  final ReportComparisonMode comparison;
  final String? branchId;
  final String? employeeId;
  final String? customerId;
  final String? supplierId;
  final String? categoryId;
  final String? status;

  ({DateTime from, DateTime to}) bounds({DateTime? now}) => preset.bounds(
        now: now,
        customFrom: customFrom,
        customTo: customTo,
      );

  ReportQuery copyWith({
    ReportDatePreset? preset,
    DateTime? customFrom,
    DateTime? customTo,
    bool clearCustom = false,
    ReportTrendGranularity? granularity,
    ReportComparisonMode? comparison,
    String? branchId,
    bool clearBranch = false,
    String? employeeId,
    bool clearEmployee = false,
    String? customerId,
    bool clearCustomer = false,
    String? supplierId,
    bool clearSupplier = false,
    String? categoryId,
    bool clearCategory = false,
    String? status,
    bool clearStatus = false,
  }) {
    return ReportQuery(
      preset: preset ?? this.preset,
      customFrom: clearCustom ? null : (customFrom ?? this.customFrom),
      customTo: clearCustom ? null : (customTo ?? this.customTo),
      granularity: granularity ?? this.granularity,
      comparison: comparison ?? this.comparison,
      branchId: clearBranch ? null : (branchId ?? this.branchId),
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      status: clearStatus ? null : (status ?? this.status),
    );
  }

  @override
  List<Object?> get props => [
        preset,
        customFrom,
        customTo,
        granularity,
        comparison,
        branchId,
        employeeId,
        customerId,
        supplierId,
        categoryId,
        status,
      ];
}

/// Future-ready export formats — UI may offer, implementation ships later.
enum ReportExportFormat { pdf, excel, csv, print }

class ReportExportRequest {
  const ReportExportRequest({
    required this.reportId,
    required this.format,
    required this.preset,
    this.branchId,
    this.query,
    this.scheduleCron,
    this.emailRecipients = const [],
  });

  final String reportId;
  final ReportExportFormat format;
  final ReportDatePreset preset;
  final String? branchId;

  /// Preferred over [preset]/[branchId] when present.
  final ReportQuery? query;

  /// Future: cron expression for scheduled delivery.
  final String? scheduleCron;

  /// Future: email / channel recipients for scheduled reports.
  final List<String> emailRecipients;
}

enum ReportCategory {
  sales,
  customers,
  products,
  inventory,
  payments,
  suppliers,
  employees,
  visits,
  schedules,
  notifications,
}

extension ReportCategoryX on ReportCategory {
  String get label => switch (this) {
        ReportCategory.sales => 'Sales',
        ReportCategory.customers => 'Customers',
        ReportCategory.products => 'Products',
        ReportCategory.inventory => 'Inventory',
        ReportCategory.payments => 'Payments',
        ReportCategory.suppliers => 'Suppliers',
        ReportCategory.employees => 'Sales Reps',
        ReportCategory.visits => 'Customer Visits',
        ReportCategory.schedules => 'Schedules',
        ReportCategory.notifications => 'Activity',
      };

  bool get isAvailable => true;
}

/// Catalog entry for the Reports workspace — answers one business question.
class ReportDefinition {
  const ReportDefinition({
    required this.id,
    required this.category,
    required this.title,
    required this.question,
    required this.icon,
    this.available = true,
    this.drillRoute,
  });

  final String id;
  final ReportCategory category;
  final String title;
  final String question;
  final String icon;
  final bool available;

  /// Optional deep link into the underlying domain workspace.
  final String? drillRoute;
}

enum ReportKpiTone { primary, finance, success, warning, ops, neutral }

/// Reusable KPI card model — built by [AnalyticsService], rendered anywhere.
class ReportKpi extends Equatable {
  const ReportKpi({
    required this.id,
    required this.label,
    required this.value,
    this.hint,
    this.iconKey = 'insights',
    this.tone = ReportKpiTone.primary,
    this.drillRoute,
    this.reportId,
    this.sparkPoints,
  });

  final String id;
  final String label;
  final String value;
  final String? hint;
  final String iconKey;
  final ReportKpiTone tone;

  /// Navigate to the domain list / workspace that backs this KPI.
  final String? drillRoute;

  /// Optional catalog report to open in the detail dialog.
  final String? reportId;

  /// Optional sparkline samples (normalized 0–1 or raw values).
  final List<double>? sparkPoints;

  @override
  List<Object?> get props =>
      [id, label, value, hint, iconKey, tone, drillRoute, reportId];
}

class ReportNamedValue extends Equatable {
  const ReportNamedValue({
    required this.id,
    required this.name,
    required this.value,
    this.subtitle,
    this.count,
    this.referenceType,
  });

  final String id;
  final String name;
  final num value;
  final String? subtitle;
  final int? count;

  /// Entity type for drill-down (`customer`, `product`, `employee`, …).
  final String? referenceType;

  String? get drillRouteHint {
    final type = referenceType?.trim();
    if (type == null || type.isEmpty) return null;
    return switch (type) {
      'order' => '${RoutePaths.hubOrders}?id=$id',
      'customer' => '${RoutePaths.hubCustomers}?id=$id',
      'product' => '${RoutePaths.hubProducts}?id=$id',
      'supplier' => '${RoutePaths.hubSuppliers}?id=$id',
      'employee' => '${RoutePaths.hubEmployees}?id=$id',
      'payment' => '${RoutePaths.hubPayments}?id=$id',
      'visit' || 'customer_visit' => '${RoutePaths.hubVisits}?id=$id',
      _ => null,
    };
  }

  @override
  List<Object?> get props =>
      [id, name, value, subtitle, count, referenceType];
}

class ReportTrendPoint extends Equatable {
  const ReportTrendPoint({
    required this.day,
    required this.sales,
    required this.orders,
  });

  final DateTime day;
  final num sales;
  final int orders;

  @override
  List<Object?> get props => [day, sales, orders];
}

class ReportStatusCount extends Equatable {
  const ReportStatusCount({
    required this.key,
    required this.label,
    required this.count,
  });

  final String key;
  final String label;
  final int count;

  @override
  List<Object?> get props => [key, label, count];
}

/// Aggregated insight payload for the Hub Reports dashboard.
class ReportsOverview extends Equatable {
  const ReportsOverview({
    required this.preset,
    required this.from,
    required this.to,
    required this.salesToday,
    required this.salesInPeriod,
    required this.ordersInPeriod,
    required this.averageOrderValue,
    required this.inventory,
    required this.payments,
    required this.orderCounts,
    required this.suppliers,
    this.query = const ReportQuery(),
    this.salesTrend = const [],
    this.topProducts = const [],
    this.topCategories = const [],
    this.topCustomers = const [],
    this.topSalesReps = const [],
    this.outstandingCustomers = const [],
    this.recentCustomers = const [],
    this.inactiveCustomers = const [],
    this.paymentMethods = const [],
    this.paymentStatusCounts = const [],
    this.productsBySupplier = const [],
    this.recentSuppliers = 0,
    this.collectionsInPeriod = 0,
    this.visitsCompleted = 0,
    this.visitsMissed = 0,
    this.visitsScheduled = 0,
    this.visitsWithOrders = 0,
    this.visitsWithPayments = 0,
    this.visitOrdersLinked = 0,
    this.visitCollectionsAmount = 0,
    this.visitRepPerformance = const [],
    this.comparisonOverview,
  });

  final ReportDatePreset preset;
  final DateTime from;
  final DateTime to;
  final ReportQuery query;

  final num salesToday;
  final num salesInPeriod;
  final int ordersInPeriod;
  final num averageOrderValue;
  final num collectionsInPeriod;

  final InventoryDashboardStats inventory;
  final PaymentDashboardStats payments;
  final OrderCounts orderCounts;
  final SupplierDashboardStats suppliers;

  final List<ReportTrendPoint> salesTrend;
  final List<ReportNamedValue> topProducts;
  final List<ReportNamedValue> topCategories;
  final List<ReportNamedValue> topCustomers;
  final List<ReportNamedValue> topSalesReps;
  final List<ReportNamedValue> outstandingCustomers;
  final List<ReportNamedValue> recentCustomers;
  final List<ReportNamedValue> inactiveCustomers;
  final List<ReportNamedValue> paymentMethods;
  final List<ReportStatusCount> paymentStatusCounts;
  final List<ReportNamedValue> productsBySupplier;
  final int recentSuppliers;

  /// Visit report foundation metrics (from VisitRepository).
  final int visitsCompleted;
  final int visitsMissed;
  final int visitsScheduled;
  final int visitsWithOrders;
  final int visitsWithPayments;

  /// Total orders linked to visits in the period.
  final int visitOrdersLinked;

  /// Payment amounts collected on visits in the period.
  final num visitCollectionsAmount;

  /// Per-representative completed visits / conversion.
  final List<ReportNamedValue> visitRepPerformance;

  /// Future: previous-period / YoY snapshot for comparison charts.
  final ReportsOverview? comparisonOverview;

  double get visitConversionRate =>
      visitsCompleted == 0 ? 0 : visitsWithOrders / visitsCompleted;

  double get visitCollectionRate =>
      visitsCompleted == 0 ? 0 : visitsWithPayments / visitsCompleted;

  double get ordersPerVisit =>
      visitsCompleted == 0 ? 0 : visitOrdersLinked / visitsCompleted;

  double get collectionsPerVisit =>
      visitsCompleted == 0 ? 0 : visitCollectionsAmount / visitsCompleted;

  @override
  List<Object?> get props => [
        preset,
        from,
        to,
        query,
        salesToday,
        salesInPeriod,
        ordersInPeriod,
        averageOrderValue,
        collectionsInPeriod,
        inventory,
        payments,
        orderCounts,
        suppliers,
        salesTrend,
        topProducts,
        topCategories,
        topCustomers,
        topSalesReps,
        outstandingCustomers,
        recentCustomers,
        inactiveCustomers,
        paymentMethods,
        paymentStatusCounts,
        productsBySupplier,
        recentSuppliers,
        visitsCompleted,
        visitsMissed,
        visitsScheduled,
        visitsWithOrders,
        visitsWithPayments,
        visitOrdersLinked,
        visitCollectionsAmount,
        visitRepPerformance,
      ];
}
