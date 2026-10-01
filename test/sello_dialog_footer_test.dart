import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';

void main() {
  testWidgets('dialog footer keeps primary and secondary on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: SelloDialogFooter(
                leading: const Text('View invoice'),
                cancelLabel: 'Record delivery',
                onCancel: () {},
                primaryLabel: 'Record collection',
                onPrimary: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final delivery = tester.getRect(find.text('Record delivery'));
    final collection = tester.getRect(find.text('Record collection'));

    expect(
      (delivery.center.dy - collection.center.dy).abs(),
      lessThan(8),
      reason: 'main actions must sit on one row, not stacked',
    );
    expect(
      collection.left,
      greaterThan(delivery.right - 1),
      reason: 'primary should sit beside secondary',
    );
  });

  testWidgets('primary button does not stretch to the full footer width', (
    tester,
  ) async {
    const footerWidth = 640.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: footerWidth,
              child: SelloDialogFooter(
                cancelLabel: 'Record delivery',
                onCancel: () {},
                primaryLabel: 'Record collection',
                onPrimary: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final collection = tester.getRect(
      find.ancestor(
        of: find.text('Record collection'),
        matching: find.byType(SelloButton),
      ),
    );
    expect(collection.width, lessThan(footerWidth * 0.6));
  });

  testWidgets('phone footer pins two actions side by side at the bottom', (
    tester,
  ) async {
    const footerWidth = 360.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: footerWidth,
              child: SelloDialogFooter(
                leading: const Text('View invoice'),
                cancelLabel: 'Record delivery',
                onCancel: () {},
                primaryLabel: 'Record collection',
                onPrimary: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final invoice = tester.getRect(find.text('View invoice'));
    final delivery = tester.getRect(find.text('Record delivery'));
    final collection = tester.getRect(find.text('Record collection'));

    expect(
      invoice.bottom,
      lessThan(delivery.top + 1),
      reason: 'links sit above the action row on phones',
    );
    expect(
      (delivery.center.dy - collection.center.dy).abs(),
      lessThan(8),
      reason: 'two actions share one row',
    );
    expect(
      collection.left,
      greaterThan(delivery.right - 1),
      reason: 'primary sits beside secondary, not below',
    );
    expect(
      delivery.width + collection.width,
      greaterThan(footerWidth * 0.7),
      reason: 'the pair should fill the phone footer',
    );
  });
}
