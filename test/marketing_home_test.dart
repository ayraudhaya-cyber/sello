import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/features/marketing/presentation/marketing_home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const MarketingHomePage(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Text('Login route')),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) =>
              const Scaffold(body: Text('Onboarding route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('marketing page shows the public story and routes', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 900));

    expect(
      find.text('Run your business operations\nin one place.'),
      findsOneWidget,
    );
    expect(
      find.text('One platform for businesses that sell, supply and grow.'),
      findsOneWidget,
    );
    expect(
      find.text('One connected platform, not a pile of separate tools.'),
      findsOneWidget,
    );
    expect(
      find.text('From customer order to successful collection.'),
      findsOneWidget,
    );
    expect(find.text('Your entire team, working in sync.'), findsOneWidget);
    expect(
      find.text('Your business, wherever work takes you.'),
      findsOneWidget,
    );
    expect(
      find.text('A clearer picture of your business, every day.'),
      findsOneWidget,
    );
    expect(find.text('Questions about Sello?'), findsOneWidget);
    expect(
      find.text('Your business deserves a better way to operate.'),
      findsOneWidget,
    );
    expect(find.text('sello@cashro.pro'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Can I manage multiple branches?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Can I manage multiple branches?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Head Office'), findsOneWidget);

    await tester.tap(find.text('Get started').first);
    await tester.pumpAndSettle();
    expect(find.text('Onboarding route'), findsOneWidget);
  });

  testWidgets('sign in opens the login route', (tester) async {
    await pumpAt(tester, const Size(1280, 900));

    await tester.tap(find.text('Sign in').first);
    await tester.pumpAndSettle();
    expect(find.text('Login route'), findsOneWidget);
  });

  testWidgets('marketing page lays out on a tablet and a wide desktop', (
    tester,
  ) async {
    await pumpAt(tester, const Size(834, 1112));
    expect(
      find.text('Run your business operations\nin one place.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await pumpAt(tester, const Size(1440, 900));
    expect(
      find.text('Run your business operations\nin one place.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('marketing page lays out on a phone without exceptions', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));

    expect(
      find.text('Run your business operations in one place.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('How it works'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
