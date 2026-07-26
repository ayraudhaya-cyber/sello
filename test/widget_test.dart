import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/app.dart';

void main() {
  testWidgets('Splash then login shell renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SelloApp()));

    // Splash while session bootstraps.
    expect(find.text('Sello'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
