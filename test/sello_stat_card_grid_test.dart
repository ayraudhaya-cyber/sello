import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/shared/widgets/cards/sello_card.dart';
import 'package:sello/shared/widgets/layout/sello_equal_height_row.dart';

void main() {
  Widget wrap({required double width, required Widget child}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  List<Widget> kpiCards() => [
        for (var i = 0; i < 5; i++)
          SelloStatCard(
            label: i == 3 ? 'Outstanding Collections' : 'Metric $i',
            value: 'Rs 5,540.00',
            icon: Icons.payments_outlined,
          ),
      ];

  testWidgets('stat grid uses four columns at a 900px content width', (
    tester,
  ) async {
    await setSurface(tester, const Size(1400, 900));
    await tester.pumpWidget(
      wrap(
        width: 900,
        child: SelloStatCardGrid(children: kpiCards()),
      ),
    );
    await tester.pumpAndSettle();

    final rows = tester.widgetList<SelloEqualHeightRow>(
      find.byType(SelloEqualHeightRow),
    );
    expect(rows.length, 2);
    expect(rows.first.children.length, 4);
    expect(rows.last.children.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stat grid keeps five columns on a wide content column', (
    tester,
  ) async {
    await setSurface(tester, const Size(1400, 900));
    await tester.pumpWidget(
      wrap(
        width: 1200,
        child: SelloStatCardGrid(children: kpiCards()),
      ),
    );
    await tester.pumpAndSettle();

    final rows = tester.widgetList<SelloEqualHeightRow>(
      find.byType(SelloEqualHeightRow),
    );
    expect(rows.length, 1);
    expect(rows.first.children.length, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stat grid is a single column on a small phone width', (
    tester,
  ) async {
    await setSurface(tester, const Size(400, 1200));
    await tester.pumpWidget(
      wrap(
        width: 360,
        child: SelloStatCardGrid(children: kpiCards()),
      ),
    );
    await tester.pumpAndSettle();

    final rows = tester.widgetList<SelloEqualHeightRow>(
      find.byType(SelloEqualHeightRow),
    );
    expect(rows.length, 5);
    for (final row in rows) {
      expect(row.children.length, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('currency values do not overflow a narrow KPI card', (
    tester,
  ) async {
    await setSurface(tester, const Size(400, 800));
    FlutterErrorDetails? overflow;
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflow = details;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(
      wrap(
        width: 200,
        child: const SelloStatCard(
          label: 'Outstanding Collections',
          value: 'Rs 5,540.00',
          icon: Icons.credit_card_outlined,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(overflow, isNull);
    expect(find.text('Rs 5,540.00'), findsOneWidget);
  });

  testWidgets('equal-height row stacks when children cannot stay comfortable', (
    tester,
  ) async {
    await setSurface(tester, const Size(800, 600));
    await tester.pumpWidget(
      wrap(
        width: 500,
        child: SelloEqualHeightRow(
          minChildWidth: 300,
          children: const [
            SizedBox(key: Key('a'), height: 40, child: Text('Left')),
            SizedBox(key: Key('b'), height: 40, child: Text('Right')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final left = tester.getTopLeft(find.byKey(const Key('a')));
    final right = tester.getTopLeft(find.byKey(const Key('b')));
    expect(right.dy, greaterThan(left.dy));
  });

  testWidgets('equal-height row stays horizontal when width is enough', (
    tester,
  ) async {
    await setSurface(tester, const Size(1000, 600));
    await tester.pumpWidget(
      wrap(
        width: 800,
        child: SelloEqualHeightRow(
          minChildWidth: 300,
          children: const [
            SizedBox(key: Key('a'), height: 40, child: Text('Left')),
            SizedBox(key: Key('b'), height: 40, child: Text('Right')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final left = tester.getTopLeft(find.byKey(const Key('a')));
    final right = tester.getTopLeft(find.byKey(const Key('b')));
    expect((right.dy - left.dy).abs(), lessThan(1));
    expect(right.dx, greaterThan(left.dx));
  });

  testWidgets('equal-height row stretches the shorter card to the taller', (
    tester,
  ) async {
    await setSurface(tester, const Size(1000, 800));
    await tester.pumpWidget(
      wrap(
        width: 800,
        child: SelloEqualHeightRow(
          minChildWidth: 280,
          children: [
            SelloCard(
              key: const Key('short-card'),
              child: const SizedBox(height: 60, child: Text('Short')),
            ),
            SelloCard(
              key: const Key('tall-card'),
              child: const SizedBox(height: 200, child: Text('Tall')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shortH = tester.getSize(find.byKey(const Key('short-card'))).height;
    final tallH = tester.getSize(find.byKey(const Key('tall-card'))).height;
    expect((shortH - tallH).abs(), lessThan(1));
    expect(shortH, greaterThan(180));
  });

  testWidgets(
    'natural row keeps independent heights with aligned tops',
    (tester) async {
      await setSurface(tester, const Size(1000, 800));
      await tester.pumpWidget(
        wrap(
          width: 800,
          child: SelloEqualHeightRow.natural(
            minChildWidth: 280,
            children: [
              SelloCard(
                key: const Key('short-card'),
                child: const SizedBox(height: 60, child: Text('Short')),
              ),
              SelloCard(
                key: const Key('tall-card'),
                child: const SizedBox(height: 200, child: Text('Tall')),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final short = find.byKey(const Key('short-card'));
      final tall = find.byKey(const Key('tall-card'));
      final shortSize = tester.getSize(short);
      final tallSize = tester.getSize(tall);
      expect(shortSize.height, lessThan(tallSize.height - 80));
      expect(
        (tester.getTopLeft(short).dy - tester.getTopLeft(tall).dy).abs(),
        lessThan(1),
      );
      expect(tester.getTopLeft(tall).dx, greaterThan(tester.getTopLeft(short).dx));
      expect(
        tester.widget<SelloEqualHeightRow>(find.byType(SelloEqualHeightRow))
            .equalizeHeights,
        isFalse,
      );
    },
  );

  testWidgets('natural row still stacks at a narrow content width', (
    tester,
  ) async {
    await setSurface(tester, const Size(500, 900));
    FlutterErrorDetails? overflow;
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflow = details;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(
      wrap(
        width: 360,
        child: SelloEqualHeightRow.natural(
          minChildWidth: 300,
          children: [
            SelloCard(
              key: const Key('a'),
              child: const SizedBox(height: 80, child: Text('Left')),
            ),
            SelloCard(
              key: const Key('b'),
              child: const SizedBox(height: 200, child: Text('Right')),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final left = tester.getTopLeft(find.byKey(const Key('a')));
    final right = tester.getTopLeft(find.byKey(const Key('b')));
    expect(right.dy, greaterThan(left.dy));
    expect((right.dx - left.dx).abs(), lessThan(1));
    expect(overflow, isNull);
    expect(tester.takeException(), isNull);
  });
}
