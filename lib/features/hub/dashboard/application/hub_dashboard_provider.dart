import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Live Hub Dashboard snapshot — always derived from tenant-scoped repos.
class HubDashboardSnapshot {
  const HubDashboardSnapshot({
    required this.overview,
    required this.activity,
    required this.activeCustomers,
    required this.currencySymbol,
    this.previousSales = 0,
    this.previousOrders = 0,
    this.previousCollections = 0,
    this.collectionsByDay = const {},
  });

  final ReportsOverview overview;
  final List<CompanyActivityEvent> activity;
  final int activeCustomers;
  final String currencySymbol;

  /// Same-length window immediately before the selected period.
  final num previousSales;
  final int previousOrders;
  final num previousCollections;

  /// Completed collections keyed by UTC day.
  final Map<DateTime, num> collectionsByDay;

  InventoryDashboardStats get inventory => overview.inventory;

  num get revenue => overview.salesInPeriod;
  int get orders => overview.ordersInPeriod;
  num get outstanding => overview.payments.outstandingReceivables;
  int get lowStock => overview.inventory.lowStock;
  num get collections => overview.collectionsInPeriod;

  bool get hasSales =>
      overview.salesInPeriod > 0 || overview.ordersInPeriod > 0;
  bool get hasInventory => overview.inventory.totalItems > 0;
  bool get hasActivity => activity.isNotEmpty;
  bool get hasTopCustomers => overview.topCustomers.isNotEmpty;
  bool get hasBestSellers => overview.topProducts.isNotEmpty;

  /// Full amount. Detail tooltips and exact reads use this.
  String money(num value) =>
      SelloFormatters.currency(value, symbol: currencySymbol);

  /// Summary cards, chips, and ranked lists. Follows Settings → Summary amounts.
  String summary(
    num value, {
    AmountDisplayStyle style = AmountDisplayStyle.exact,
  }) => SelloFormatters.summaryAmount(
    value,
    symbol: currencySymbol,
    style: style,
  );

  List<double> sparkForMetric(String metric) {
    final points = switch (metric) {
      'orders' => [for (final p in overview.salesTrend) p.orders.toDouble()],
      'collections' => [
        for (final p in overview.salesTrend)
          (collectionsByDay[_utcDay(p.day)] ?? 0).toDouble(),
      ],
      _ => [for (final p in overview.salesTrend) p.sales.toDouble()],
    };
    if (points.isEmpty || points.every((v) => v <= 0)) return const [];
    final series = _downsample(points, maxPoints: 40);
    final max = series.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return const [];
    return [for (final v in series) v / max];
  }

  /// Daily values for the performance chart. Orders stay a count.
  List<({DateTime day, num value})> seriesForMetric(String metric) {
    return [
      for (final point in overview.salesTrend)
        (
          day: point.day,
          value: switch (metric) {
            'orders' => point.orders,
            'collections' => collectionsByDay[_utcDay(point.day)] ?? 0,
            _ => point.sales,
          },
        ),
    ];
  }

  static DateTime _utcDay(DateTime day) =>
      DateTime.utc(day.toUtc().year, day.toUtc().month, day.toUtc().day);

  /// Sums neighbouring days so a year of daily points stays readable in a
  /// small sparkline.
  static List<double> _downsample(
    List<double> points, {
    required int maxPoints,
  }) {
    if (points.length <= maxPoints) return points;
    final size = (points.length / maxPoints).ceil();
    return [
      for (var i = 0; i < points.length; i += size)
        points
            .sublist(i, (i + size).clamp(0, points.length))
            .fold<double>(0, (sum, v) => sum + v),
    ];
  }

  String formatActivityTime(DateTime at) {
    return DateFormat('HH:mm').format(at.toLocal());
  }
}

ReportDatePreset hubDashboardPresetForRange(String range) {
  return switch (range) {
    'today' => ReportDatePreset.today,
    'week' => ReportDatePreset.thisWeek,
    'year' => ReportDatePreset.thisYear,
    _ => ReportDatePreset.thisMonth,
  };
}

/// KPI caption for the selected dashboard range.
String hubDashboardRevenueLabel(String range) {
  return switch (range) {
    'today' => 'Revenue today',
    'week' => 'Revenue this week',
    'year' => 'Revenue this year',
    _ => 'Revenue this month',
  };
}

String hubDashboardOrdersLabel(String range) {
  return switch (range) {
    'today' => 'Orders today',
    'week' => 'Orders this week',
    'year' => 'Orders this year',
    _ => 'Orders this month',
  };
}

String hubDashboardCollectionsLabel(String range) {
  return switch (range) {
    'today' => 'Collected today',
    'week' => 'Collected this week',
    'year' => 'Collected this year',
    _ => 'Collected this month',
  };
}

/// Name of the matching previous window, for “vs last month”.
String hubDashboardPreviousPeriodName(String range) {
  return switch (range) {
    'today' => 'yesterday',
    'week' => 'last week',
    'year' => 'last year',
    _ => 'last month',
  };
}

/// Same elapsed span one period earlier. A month-to-date compares with the
/// same dates last month, not the whole previous month.
({DateTime from, DateTime to}) hubDashboardPreviousBounds(
  String range, {
  DateTime? now,
}) {
  final local = (now ?? DateTime.now()).toLocal();
  final startOfToday = DateTime(local.year, local.month, local.day);
  final endOfToday = startOfToday
      .add(const Duration(days: 1))
      .subtract(const Duration(milliseconds: 1));

  switch (range) {
    case 'today':
      final start = startOfToday.subtract(const Duration(days: 1));
      return (
        from: start.toUtc(),
        to: endOfToday.subtract(const Duration(days: 1)).toUtc(),
      );
    case 'week':
      return (
        from: startOfToday
            .subtract(Duration(days: 7 + local.weekday - 1))
            .toUtc(),
        to: endOfToday.subtract(const Duration(days: 7)).toUtc(),
      );
    case 'year':
      final start = DateTime(local.year - 1, 1, 1);
      final end = DateTime(local.year - 1, local.month, local.day, 23, 59, 59, 999);
      return (from: start.toUtc(), to: end.toUtc());
    default:
      final start = DateTime(local.year, local.month - 1, 1);
      final lastDay = DateTime(local.year, local.month, 0).day;
      final day = local.day.clamp(1, lastDay);
      final end = DateTime(start.year, start.month, day, 23, 59, 59, 999);
      return (from: start.toUtc(), to: end.toUtc());
  }
}

/// Short comparison for a period card. Null when both sides are zero.
String? hubDashboardComparison({
  required num current,
  required num previous,
  required String periodName,
}) {
  if (current == 0 && previous == 0) return null;
  if (previous == 0) return 'New vs $periodName';
  final pct = ((current - previous) / previous * 100).round();
  if (pct == 0) return 'Same as $periodName';
  final sign = pct > 0 ? '+' : '';
  return '$sign$pct% vs $periodName';
}

final hubDashboardProvider = FutureProvider.autoDispose
    .family<HubDashboardSnapshot, String>((ref, range) async {
      final session = ref.watch(currentSessionProvider);
      if (session == null) {
        throw StateError('Sign in required.');
      }

      final settings = await ref.watch(selloCompanySettingsProvider.future);
      final symbol = SelloFormatters.currencySymbol(settings.currency);
      final preset = hubDashboardPresetForRange(range);
      final bounds = preset.bounds();
      final previous = hubDashboardPreviousBounds(range);
      final reports = ref.read(reportRepositoryProvider);

      final overviewFuture = reports.fetchOverview(
        companyId: session.company.id,
        branchId: session.branch?.id,
        preset: preset,
      );
      final previousFuture = reports.fetchPeriodHeadline(
        from: previous.from,
        to: previous.to,
        branchId: session.branch?.id,
      );
      final collectionsFuture = reports.fetchCollectionAmountsByDay(
        from: bounds.from,
        to: bounds.to,
      );
      final activityFuture = ref
          .read(notificationRepositoryProvider)
          .fetchCompanyActivity(companyId: session.company.id, limit: 8);
      final activeCustomersFuture = _countActiveCustomers(ref);

      final overview = await overviewFuture;
      final activity = await activityFuture;
      final activeCustomers = await activeCustomersFuture;
      final previousHeadline = await previousFuture;
      final collectionsByDay = await collectionsFuture;

      return HubDashboardSnapshot(
        overview: overview,
        activity: activity,
        activeCustomers: activeCustomers,
        currencySymbol: symbol,
        previousSales: previousHeadline.sales,
        previousOrders: previousHeadline.orders,
        previousCollections: previousHeadline.collections,
        collectionsByDay: collectionsByDay,
      );
    });

Future<int> _countActiveCustomers(Ref ref) async {
  try {
    return await ref.read(customerRepositoryProvider).countActiveCustomers();
  } catch (_) {
    return 0;
  }
}
