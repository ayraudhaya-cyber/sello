import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/visits/presentation/visit_customer_context_header.dart';
import 'package:sello/features/visits/presentation/visit_customer_details_sheet.dart';
import 'package:sello/features/visits/presentation/visit_draft_restore_banner.dart';
import 'package:sello/features/visits/presentation/visit_order_status_banner.dart';
import 'package:sello/services/orders/visit_order_draft.dart';
import 'package:sello/services/orders/visit_order_draft_store.dart';
import 'package:sello/services/reliability/reliability_providers.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/reliability/connectivity_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('VisitCustomerContextHeader', () {
    testWidgets('shows storefront icon and shop name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VisitCustomerContextHeader(
              shopName: 'Namson',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Namson'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });
  });

  group('CustomerVisit.durationLabel', () {
    test('formats elapsed in-progress visit time', () {
      final visit = CustomerVisit(
        id: 'v1',
        companyId: 'co',
        customerId: 'c1',
        employeeId: 'e1',
        status: CustomerVisitStatus.inProgress,
        startedAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 47)),
      );
      expect(visit.durationLabel, '2h 47m');
    });

    test('does not cap long in-progress durations', () {
      final visit = CustomerVisit(
        id: 'v1',
        companyId: 'co',
        customerId: 'c1',
        employeeId: 'e1',
        status: CustomerVisitStatus.inProgress,
        startedAt: DateTime.now().subtract(
          const Duration(hours: 212, minutes: 47),
        ),
      );
      expect(visit.durationLabel, '212h 47m');
    });
  });

  group('VisitOrderDraft', () {
    test('round-trips json with tenant scoping fields', () {
      final draft = VisitOrderDraft(
        companyId: 'co1',
        employeeId: 'emp1',
        customerId: 'cust1',
        customerName: 'Namson',
        lines: const [
          VisitOrderDraftLine(productId: 'p1', quantity: 3),
        ],
        updatedAt: DateTime(2026, 9, 1),
        runningTotal: 3600,
      );
      final restored = VisitOrderDraft.fromJson(draft.toJson());
      expect(restored.companyId, 'co1');
      expect(restored.employeeId, 'emp1');
      expect(restored.lines.single.productId, 'p1');
      expect(restored.lines.single.quantity, 3);
      expect(restored.runningTotal, 3600);
    });

    test('store persists and loads per company and employee', () async {
      SharedPreferences.setMockInitialValues({});
      final store = VisitOrderDraftStore();
      final draft = VisitOrderDraft(
        companyId: 'co1',
        employeeId: 'emp1',
        customerId: 'cust1',
        lines: const [
          VisitOrderDraftLine(productId: 'p1', quantity: 10),
        ],
        updatedAt: DateTime(2026, 9, 1),
        runningTotal: 100,
      );
      await store.save(draft);
      final loaded = await store.load(
        companyId: 'co1',
        employeeId: 'emp1',
      );
      expect(loaded?.lines.single.quantity, 10);
      await store.clear(companyId: 'co1', employeeId: 'emp1');
      final cleared = await store.load(
        companyId: 'co1',
        employeeId: 'emp1',
      );
      expect(cleared, isNull);
    });

    test('round-trips checkout stage, notes, and arrangement', () {
      final draft = VisitOrderDraft(
        companyId: 'co1',
        employeeId: 'emp1',
        customerId: 'cust1',
        customerName: 'Namson',
        lines: const [
          VisitOrderDraftLine(productId: 'p1', quantity: 3),
        ],
        visitNotes: 'Deliver before noon',
        stage: VisitOrderDraftStage.checkout,
        arrangement: 'paidToday',
        updatedAt: DateTime(2026, 9, 1),
        runningTotal: 3600,
      );
      final restored = VisitOrderDraft.fromJson(draft.toJson());
      expect(restored.visitNotes, 'Deliver before noon');
      expect(restored.stage, VisitOrderDraftStage.checkout);
      expect(restored.arrangement, 'paidToday');
      expect(restored.customerName, 'Namson');
    });
  });

  group('VisitCustomerDetailsSheet', () {
    testWidgets('labels visit duration with elapsed-time hint', (tester) async {
      final visit = CustomerVisit(
        id: 'v1',
        companyId: 'co',
        customerId: 'c1',
        employeeId: 'e1',
        status: CustomerVisitStatus.inProgress,
        startedAt: DateTime(2026, 9, 1, 9, 30),
      );
      final customer = CustomerSummary(
        id: 'c1',
        companyId: 'co',
        name: 'Namson',
        customerType: CustomerType.retail,
        phone: '+94771234567',
        creditAllowed: false,
        creditLimit: 0,
        openingBalance: 0,
        outstandingBalance: 0,
        walletBalance: 0,
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showVisitCustomerDetailsSheet(
                    context,
                    shopName: 'Namson',
                    customer: customer,
                    activeVisit: visit,
                    currencySymbol: 'Rs',
                    showOutstanding: false,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Visit duration'), findsOneWidget);
      expect(find.text(visit.durationLabel), findsOneWidget);
      expect(
        find.textContaining('Elapsed time since this visit started'),
        findsOneWidget,
      );
      expect(find.text('+94771234567'), findsOneWidget);
    });
  });

  group('VisitDraftRestoreBanner', () {
    testWidgets('shows draft summary and continue action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: VisitDraftRestoreBanner(
              itemQuantity: 3,
              total: 3600,
              currencySymbol: 'Rs',
              onContinue: () {},
            ),
          ),
        ),
      );

      expect(find.text('Draft order'), findsOneWidget);
      expect(find.textContaining('3 items'), findsOneWidget);
      expect(find.textContaining('Rs3,600.00'), findsOneWidget);
      expect(find.text('Continue order'), findsOneWidget);
    });
  });

  group('VisitOrderStatusBanner', () {
    testWidgets('shows offline message when transport is down', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivitySnapshotProvider.overrideWith(
              (ref) => Stream.value(
                ConnectivitySnapshot(
                  status: ConnectivityStatus.offline,
                  updatedAt: DateTime(2026, 9, 1),
                  transportOnline: false,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: VisitOrderStatusBanner(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Offline · Changes saved on this device'),
        findsOneWidget,
      );
    });
  });
}
