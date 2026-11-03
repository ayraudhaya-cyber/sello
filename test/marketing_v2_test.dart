import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/features/marketing/presentation/marketing_v2_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    String path = '/',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const MarketingV2Page(),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpMotion(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('v2 page shows dark story and placeholder labels', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 900));

    expect(find.textContaining('Everything your'), findsWidgets);
    expect(find.text('TRUSTED BY'), findsOneWidget);
    expect(
      find.text('One platform for businesses that sell, supply and grow.'),
      findsOneWidget,
    );
    expect(find.text('Questions about Sello?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v2 get started opens onboarding', (tester) async {
    await pumpAt(tester, const Size(1280, 900));

    final getStarted = find.text('Get started').first;
    await tester.ensureVisible(getStarted);
    await tester.tap(getStarted);
    await pumpMotion(tester);
    expect(find.text('Onboarding route'), findsOneWidget);
  });

  testWidgets('v2 sign in opens login', (tester) async {
    await pumpAt(tester, const Size(1280, 900));

    final signIn = find.text('Sign in').first;
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await pumpMotion(tester);
    expect(find.text('Login route'), findsOneWidget);
  });

  testWidgets('v2 lays out on a phone without exceptions', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Open menu'));
    await pumpMotion(tester);
    expect(find.text('Features'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
