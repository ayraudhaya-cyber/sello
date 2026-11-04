import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/hub/reports/presentation/report_charts.dart';
import 'package:sello/shared/models/order_summary.dart';

void main() {
  test('donut slices are only open, completed, and cancelled', () {
    final data = OrderStatusDonutData.fromCounts(
      const OrderCounts(total: 20, draft: 4, completed: 12, cancelled: 3),
    );

    expect(data.open, 4);
    expect(data.completed, 12);
    expect(data.cancelled, 3);
    expect(data.total, 19);
    expect(data.isEmpty, isFalse);
  });

  test('zero orders stay an empty chart', () {
    final data = OrderStatusDonutData.fromCounts(
      const OrderCounts(total: 0, draft: 0, completed: 0, cancelled: 0),
    );

    expect(data.isEmpty, isTrue);
    expect(data.total, 0);
  });

  testWidgets('legend shows the three status counts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: OrderStatusDonut(
            data: OrderStatusDonutData(open: 2, completed: 5, cancelled: 1),
          ),
        ),
      ),
    );

    expect(find.text('8'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Unpaid'), findsNothing);
    expect(find.text('Partially paid'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero orders render a centre zero without throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SizedBox(
            width: 220,
            child: OrderStatusDonut(
              data: OrderStatusDonutData(open: 0, completed: 0, cancelled: 0),
            ),
          ),
        ),
      ),
    );

    expect(find.text('0'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
