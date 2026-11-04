import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/hub/reports/application/report_catalog.dart';
import 'package:sello/features/hub/reports/presentation/report_charts.dart';
import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/models/report_models.dart';

void main() {
  List<String> ids({
    String query = '',
    ReportCategory? category,
    bool isOwner = true,
  }) {
    return [
      for (final item in ReportCatalog.matching(
        query: query,
        category: category,
        isOwner: isOwner,
      ))
        item.id,
    ];
  }

  test('payment search finds the payment reports', () {
    expect(
      ids(query: 'payment', category: ReportCategory.payments),
      containsAll([
        'payments_paid',
        'payments_partial',
        'payments_outstanding',
        'payments_methods',
        'payments_wallet',
        kCollectionsReportId,
      ]),
    );
  });

  test('payment search does not cross into another category', () {
    expect(
      ids(query: 'payment', category: ReportCategory.customers),
      isEmpty,
    );
  });

  test('stock search finds the inventory stock reports', () {
    expect(
      ids(query: 'stock'),
      containsAll([
        'inventory_stock',
        'inventory_value',
        'inventory_low',
        'inventory_out',
        'inventory_adjustments',
        'inventory_slow',
      ]),
    );
  });

  test('stock value stays owner-only', () {
    expect(ids(query: 'stock value', isOwner: false), isNot(contains('inventory_value')));
    expect(ids(query: 'stock value'), contains('inventory_value'));
  });

  test('sales rep search finds both rep reports and visit performance', () {
    expect(
      ids(query: 'sales rep'),
      containsAll([
        'employees_performance',
        'employees_visit_mix',
        'visits_rep_performance',
      ]),
    );
  });

  test('unavailable reports stay in search results and cannot be opened', () {
    for (final id in [
      'inventory_slow',
      'suppliers_purchases',
      'notifications_volume',
      'activity_feed',
    ]) {
      final item = ReportCatalog.definitions.singleWhere((row) => row.id == id);
      expect(item.available, isFalse, reason: id);
      expect(ids(query: item.title), contains(id));
    }
  });

  test('fixed windows do not pretend to use the page date range', () {
    expect(
      ReportCatalog.fixedWindowCaption('customers_recent'),
      'Created in the last 30 days',
    );
    expect(
      ReportCatalog.fixedWindowCaption('customers_inactive'),
      'No purchase, or last purchase more than 60 days ago',
    );
    expect(
      ReportCatalog.fixedWindowCaption('customers_outstanding'),
      'Current customer balances',
    );
    expect(
      ReportCatalog.fixedWindowCaption('inventory_stock'),
      'Current stock snapshot',
    );
    expect(ReportCatalog.fixedWindowCaption('sales_daily'), isNull);
  });

  testWidgets('sales trend labels the days without changing bar values', (
    tester,
  ) async {
    final points = [
      ReportTrendPoint(day: DateTime.utc(2026, 11, 1), sales: 0, orders: 0),
      ReportTrendPoint(day: DateTime.utc(2026, 11, 4), sales: 242004, orders: 2),
    ];
    String label(DateTime day) {
      final local = day.toLocal();
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[local.weekday - 1]} ${local.day}';
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 480,
            child: ReportBarChart(points: points),
          ),
        ),
      ),
    );

    expect(find.text(label(points.first.day)), findsOneWidget);
    expect(find.text(label(points.last.day)), findsOneWidget);
  });
}
