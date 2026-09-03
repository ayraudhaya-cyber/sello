import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/dashboard/application/hub_dashboard_provider.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/models/supplier_summary.dart';

ReportsOverview _emptyOverview() {
  final now = DateTime.utc(2026, 9, 1);
  return ReportsOverview(
    preset: ReportDatePreset.thisMonth,
    from: now,
    to: now,
    salesToday: 0,
    salesInPeriod: 0,
    ordersInPeriod: 0,
    averageOrderValue: 0,
    inventory: const InventoryDashboardStats(
      totalItems: 0,
      lowStock: 0,
      outOfStock: 0,
      recentlyUpdated: 0,
    ),
    payments: const PaymentDashboardStats(
      collectedToday: 0,
      outstandingReceivables: 0,
      walletIssued: 0,
      pendingCredit: 0,
    ),
    orderCounts: const OrderCounts(
      total: 0,
      draft: 0,
      completed: 0,
      cancelled: 0,
    ),
    suppliers: const SupplierDashboardStats(),
  );
}

void main() {
  group('HubDashboardSnapshot empty tenant', () {
    late HubDashboardSnapshot snap;

    setUp(() {
      snap = HubDashboardSnapshot(
        overview: _emptyOverview(),
        activity: const [],
        activeCustomers: 0,
        currencySymbol: 'Rs ',
      );
    });

    test('KPIs are zero — no demo revenue or fake counts', () {
      expect(snap.revenue, 0);
      expect(snap.orders, 0);
      expect(snap.activeCustomers, 0);
      expect(snap.outstanding, 0);
      expect(snap.lowStock, 0);
      expect(snap.moneyCompact(0), 'Rs 0.00');
      expect(snap.money(0), isNot(contains('4.82')));
      expect(snap.moneyCompact(612000), contains('K'));
      expect(snap.moneyCompact(4820000), contains('M'));
    });

    test('empty flags drive truthful empty states', () {
      expect(snap.hasSales, isFalse);
      expect(snap.hasInventory, isFalse);
      expect(snap.hasActivity, isFalse);
      expect(snap.hasTopCustomers, isFalse);
      expect(snap.hasBestSellers, isFalse);
    });

    test('spark series stays empty when there is no trend data', () {
      expect(snap.sparkForMetric('revenue'), isEmpty);
      expect(snap.sparkForMetric('orders'), isEmpty);
      expect(snap.sparkForMetric('collections'), isEmpty);
    });
  });

  group('HubDashboardSnapshot with real data', () {
    test('surfaces tenant overview values without inventing extras', () {
      final now = DateTime.utc(2026, 9, 1);
      final real = ReportsOverview(
        preset: ReportDatePreset.thisMonth,
        from: now,
        to: now,
        salesToday: 1000,
        salesInPeriod: 4820000,
        ordersInPeriod: 12,
        averageOrderValue: 400000,
        inventory: const InventoryDashboardStats(
          totalItems: 40,
          lowStock: 5,
          outOfStock: 5,
          recentlyUpdated: 3,
        ),
        payments: const PaymentDashboardStats(
          collectedToday: 2000,
          outstandingReceivables: 612000,
          walletIssued: 0,
          pendingCredit: 0,
        ),
        orderCounts: const OrderCounts(
          total: 12,
          draft: 0,
          completed: 12,
          cancelled: 0,
        ),
        suppliers: const SupplierDashboardStats(total: 1, active: 1),
        topCustomers: const [
          ReportNamedValue(id: 'c1', name: 'Acme Stores', value: 1000),
        ],
        topProducts: const [
          ReportNamedValue(id: 'p1', name: 'Widget', value: 500),
        ],
        salesTrend: [
          ReportTrendPoint(day: now, sales: 100, orders: 1),
          ReportTrendPoint(
            day: now.add(const Duration(days: 1)),
            sales: 200,
            orders: 2,
          ),
        ],
      );

      final snap = HubDashboardSnapshot(
        overview: real,
        activity: const [],
        activeCustomers: 4,
        currencySymbol: 'Rs ',
      );

      expect(snap.revenue, 4820000);
      expect(snap.orders, 12);
      expect(snap.activeCustomers, 4);
      expect(snap.outstanding, 612000);
      expect(snap.hasTopCustomers, isTrue);
      expect(snap.hasBestSellers, isTrue);
      expect(snap.hasInventory, isTrue);
      expect(snap.sparkForMetric('revenue'), isNotEmpty);
    });
  });

  test('hubDashboardPresetForRange maps UI ranges to report presets', () {
    expect(hubDashboardPresetForRange('today'), ReportDatePreset.today);
    expect(hubDashboardPresetForRange('week'), ReportDatePreset.thisWeek);
    expect(hubDashboardPresetForRange('month'), ReportDatePreset.thisMonth);
    expect(hubDashboardPresetForRange('year'), ReportDatePreset.last30Days);
  });
}
