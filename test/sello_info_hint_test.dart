import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/shared/widgets/feedback/sello_info_hint.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';

void main() {
  testWidgets('info hint keeps explanation off the canvas until opened', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelloFieldLabel(
            label: 'Financial year',
            hint: 'The month your reporting year starts.',
          ),
        ),
      ),
    );

    expect(find.text('Financial year'), findsOneWidget);
    expect(find.text('The month your reporting year starts.'), findsNothing);
    expect(find.byType(SelloInfoHint), findsOneWidget);
  });

  testWidgets('info hint shows explanation on tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelloFieldLabel(
            label: 'Default tax mode',
            hint: 'Used as the default when pricing; editable per sale.',
          ),
        ),
      ),
    );

    await tester.tap(find.byType(SelloInfoHint));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(
      find.text('Used as the default when pricing; editable per sale.'),
      findsOneWidget,
    );
  });

  testWidgets('compact fields align controls whether or not a hint exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: SettingsTwoUp(
              children: [
                SettingsCompactField(
                  label: 'Financial year',
                  helper: 'The month your reporting year starts.',
                  child: SizedBox(key: Key('fy-control'), height: 40),
                ),
                SettingsCompactField(
                  label: 'Default tax mode',
                  child: SizedBox(key: Key('tax-control'), height: 40),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final withHint = tester.getTopLeft(find.byKey(const Key('fy-control')));
    final withoutHint = tester.getTopLeft(find.byKey(const Key('tax-control')));
    expect((withHint.dy - withoutHint.dy).abs(), lessThan(1));
    expect(find.text('The month your reporting year starts.'), findsNothing);
  });

  testWidgets('status toggle does not show helper as persistent body text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelloStatusToggle(
            value: true,
            onChanged: (_) {},
            label: 'Low stock alert enabled',
            helper:
                'Show alerts when stock falls to or below the reorder level.',
          ),
        ),
      ),
    );

    expect(find.text('Low stock alert enabled'), findsOneWidget);
    expect(
      find.text('Show alerts when stock falls to or below the reorder level.'),
      findsNothing,
    );
    expect(find.byType(SelloInfoHint), findsOneWidget);
  });

  testWidgets('required label shows asterisk; optional has no marker or hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SelloFieldLabel(label: 'Business name', required: true),
              SelloFieldLabel(label: 'Business phone'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Business name'), findsOneWidget);
    expect(find.text('Business phone'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);
    expect(find.byType(SelloInfoHint), findsNothing);
    expect(find.text('Optional'), findsNothing);
  });

  testWidgets('compact required field keeps asterisk without an Optional hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsCompactField(
            label: 'Business name',
            required: true,
            child: SizedBox(height: 40),
          ),
        ),
      ),
    );

    expect(find.text('Business name'), findsOneWidget);
    expect(find.text('*'), findsOneWidget);
    expect(find.byType(SelloInfoHint), findsNothing);
  });
}
