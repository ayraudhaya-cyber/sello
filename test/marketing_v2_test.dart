import 'package:flutter/gestures.dart';
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

  testWidgets('core cards step from the third shade and darken on hover', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 1400));

    BoxDecoration decorationOf(String title) {
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(AnimatedContainer),
      );
      return tester.widget<AnimatedContainer>(card.first).decoration!
          as BoxDecoration;
    }

    Color firstOf(String title) =>
        (decorationOf(title).gradient! as LinearGradient).colors.first;

    expect(firstOf('Customer Management'), const Color(0xFF9E64DA));
    expect(firstOf('Payments & Collections'), const Color(0xFF8C5ACE));
    expect(firstOf('Invoicing'), const Color(0xFF7B4FC3));
    expect(firstOf('Business Notifications'), const Color(0xFF6945B7));
    expect(firstOf('Business Reporting'), const Color(0xFF583AAC));
    expect(firstOf('Team Management'), const Color(0xFF4630A0));
    expect(decorationOf('Customer Management').border, isNull);

    final target = find.text('Customer Management');
    await tester.ensureVisible(target);
    final card = find
        .ancestor(of: target, matching: find.byType(MouseRegion))
        .first;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(card));
    addTearDown(gesture.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final hovered = firstOf('Customer Management');
    expect(
      hovered.computeLuminance(),
      lessThan(const Color(0xFF9E64DA).computeLuminance()),
    );
    expect(decorationOf('Customer Management').border, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v2 lays out on a phone without exceptions', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Open menu'));
    await pumpMotion(tester);
    expect(find.text('Features'), findsWidgets);
    expect(
      tester.getSize(find.byKey(const ValueKey('v2-menu'))).height,
      844,
    );
    expect(tester.takeException(), isNull);
  });
}
