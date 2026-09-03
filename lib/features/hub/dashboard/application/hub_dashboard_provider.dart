import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';
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
  });

  final ReportsOverview overview;
  final List<CompanyActivityEvent> activity;
  final int activeCustomers;
  final String currencySymbol;

  InventoryDashboardStats get inventory => overview.inventory;

  num get revenue => overview.salesInPeriod;
  int get orders => overview.ordersInPeriod;
  num get outstanding => overview.payments.outstandingReceivables;
  int get lowStock => overview.inventory.lowStock;
  num get collections => overview.collectionsInPeriod;

  bool get hasSales => overview.salesInPeriod > 0 || overview.ordersInPeriod > 0;
  bool get hasInventory => overview.inventory.totalItems > 0;
  bool get hasActivity => activity.isNotEmpty;
  bool get hasTopCustomers => overview.topCustomers.isNotEmpty;
  bool get hasBestSellers => overview.topProducts.isNotEmpty;

  String money(num value) =>
      SelloFormatters.currency(value, symbol: currencySymbol);

  String moneyCompact(num value) {
    final abs = value.abs();
    if (abs >= 1000000) {
      final m = value / 1000000;
      final text = m == m.roundToDouble()
          ? m.toStringAsFixed(0)
          : m.toStringAsFixed(2);
      return '$currencySymbol${text}M';
    }
    if (abs >= 1000) {
      final k = value / 1000;
      final text = k == k.roundToDouble()
          ? k.toStringAsFixed(0)
          : k.toStringAsFixed(1);
      return '$currencySymbol${text}K';
    }
    return money(value);
  }

  List<double> sparkForMetric(String metric) {
    final points = switch (metric) {
      'orders' => [
          for (final p in overview.salesTrend) p.orders.toDouble(),
        ],
      'collections' => [
          if (collections > 0)
            for (final p in overview.salesTrend) p.sales.toDouble(),
        ],
      _ => [
          for (final p in overview.salesTrend) p.sales.toDouble(),
        ],
    };
    if (points.isEmpty || points.every((v) => v <= 0)) return const [];
    final max = points.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return const [];
    return [for (final v in points) (v / max).clamp(0.05, 1.0)];
  }

  String formatActivityTime(DateTime at) {
    return DateFormat('HH:mm').format(at.toLocal());
  }
}

ReportDatePreset hubDashboardPresetForRange(String range) {
  return switch (range) {
    'today' => ReportDatePreset.today,
    'week' => ReportDatePreset.thisWeek,
    'year' => ReportDatePreset.last30Days,
    _ => ReportDatePreset.thisMonth,
  };
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

  final overview = await ref.read(reportRepositoryProvider).fetchOverview(
        companyId: session.company.id,
        branchId: session.branch?.id,
        preset: preset,
      );

  final activity = await ref
      .read(notificationRepositoryProvider)
      .fetchCompanyActivity(
        companyId: session.company.id,
        limit: 8,
      );

  final activeCustomers = await _countActiveCustomers(ref);

  return HubDashboardSnapshot(
    overview: overview,
    activity: activity,
    activeCustomers: activeCustomers,
    currencySymbol: symbol,
  );
});

Future<int> _countActiveCustomers(Ref ref) async {
  try {
    final page = await ref
        .read(customerRepositoryProvider)
        .fetchCustomers(isActive: true, pageSize: 1000);
    return page.items.length;
  } catch (_) {
    return 0;
  }
}
