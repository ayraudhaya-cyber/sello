import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/orders/presentation/order_details_dialog.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/payment_status.dart';

void main() {
  testWidgets('order details keeps products visible on a wide window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 10, 30);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_QuietSession.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: OrderDetailsDialog(
              currencySymbol: 'Rs ',
              detail: OrderDetail(
                summary: OrderSummary(
                  id: 'order-1',
                  companyId: 'company-1',
                  branchId: 'branch-1',
                  customerId: 'customer-1',
                  employeeId: 'employee-1',
                  orderNumber: 'SO-20261030-0003',
                  status: OrderStatus.placed,
                  paymentStatus: PaymentStatus.unpaid,
                  subtotal: 1000,
                  discountAmount: 0,
                  taxAmount: 0,
                  total: 1000,
                  orderedAt: now,
                  updatedAt: now,
                  customerName: 'AKA WADOOD AND SONS',
                ),
                lines: const [
                  OrderLineItem(
                    id: 'line-1',
                    productId: 'product-1',
                    quantity: 124,
                    unitPrice: 8,
                    lineTotal: 992,
                    productName: 'Sunlight Bar',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final product = find.text('Sunlight Bar');
    expect(product, findsOneWidget);
    final top = tester.getTopLeft(product).dy;
    expect(top, greaterThan(0));
    expect(top, lessThan(900));
    expect(find.text('PRODUCTS'), findsOneWidget);
    expect(find.text('TOTALS'), findsOneWidget);
  });
}

class _QuietSession extends AuthSessionNotifier {
  @override
  AuthSessionState build() {
    return const AuthSessionState(status: AuthStatus.unauthenticated);
  }
}
