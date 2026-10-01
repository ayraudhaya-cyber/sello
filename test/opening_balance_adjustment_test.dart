import 'package:flutter_test/flutter_test.dart';
import 'package:sello/data/repositories/customer_repository.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/features/payments/application/receivable_fifo.dart';
import 'package:sello/features/payments/presentation/receivable_picker_copy.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/models/customer_receivable_adjustment.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

void main() {
  group('Opening balance adjustment permissions', () {
    PermissionService perms(String role) => PermissionService(
          profile: RolePermissionProfile.forRoleCode(role),
        );

    test('Owner can add', () {
      expect(perms('owner').canRecordOpeningBalanceAdjustment, isTrue);
    });

    test('Manager can add', () {
      expect(perms('manager').canRecordOpeningBalanceAdjustment, isTrue);
    });

    test('Administrator can add (same Hub money RPC set)', () {
      expect(
        perms('administrator').canRecordOpeningBalanceAdjustment,
        isTrue,
      );
    });

    test('Sales Rep rejected', () {
      expect(
        perms('sales_representative').canRecordOpeningBalanceAdjustment,
        isFalse,
      );
    });

    test('Sales In-charge rejected', () {
      expect(
        perms('sales_in_charge').canRecordOpeningBalanceAdjustment,
        isFalse,
      );
    });
  });

  group('Opening balance RPC error mapping', () {
    test('amount <= 0', () {
      expect(
        mapOpeningBalanceError('Opening balance amount must be greater than zero.'),
        'Enter an opening balance greater than zero.',
      );
    });

    test('inactive customer', () {
      expect(
        mapOpeningBalanceError('Customer is inactive.'),
        'This customer is inactive.',
      );
    });

    test('wrong-company / missing customer', () {
      expect(
        mapOpeningBalanceError('Customer not found.'),
        'Customer not found.',
      );
    });

    test('unauthorized role', () {
      expect(
        mapOpeningBalanceError('Only Owner or Manager can add an opening balance.'),
        'Only Owner or Manager can add an opening balance.',
      );
    });
  });

  group('FIFO: opening balances join chronological order', () {
    ReceivableOrder invoice({
      required String id,
      required DateTime at,
      num remaining = 100,
    }) {
      return ReceivableOrder(
        id: id,
        orderNumber: id,
        total: remaining,
        amountPaid: 0,
        orderedAt: at,
      );
    }

    ReceivableOrder opening({
      required String id,
      required DateTime at,
      num remaining = 50,
    }) {
      return ReceivableOrder(
        id: id,
        orderNumber: 'OB-$id',
        total: remaining,
        amountPaid: 0,
        orderedAt: at,
        kind: ReceivableKind.openingBalance,
      );
    }

    test('order-only list stays oldest ordered_at first', () {
      final older = invoice(id: 'o-old', at: DateTime.utc(2026, 1, 1));
      final newer = invoice(id: 'o-new', at: DateTime.utc(2026, 6, 1));
      final sorted = sortReceivablesFifo([newer, older]);
      expect(sorted.map((r) => r.id), ['o-old', 'o-new']);
    });

    test('older opening balance is allocated before later invoices', () {
      final openingRow = opening(
        id: 'ob1',
        at: DateTime.utc(2025, 12, 1),
        remaining: 40,
      );
      final invoiceRow = invoice(
        id: 'o1',
        at: DateTime.utc(2026, 3, 1),
        remaining: 80,
      );
      final sorted = sortReceivablesFifo([invoiceRow, openingRow]);
      final allocations = fifoChequeAllocations(
        amount: 50,
        orders: sorted,
      );
      expect(allocations, hasLength(2));
      expect(allocations.first.receivableAdjustmentId, 'ob1');
      expect(allocations.first.amount, 40);
      expect(allocations.last.orderId, 'o1');
      expect(allocations.last.amount, 10);
    });

    test('newer opening balance does not jump ahead of older invoices', () {
      final invoiceRow = invoice(
        id: 'o1',
        at: DateTime.utc(2025, 1, 1),
        remaining: 80,
      );
      final openingRow = opening(
        id: 'ob1',
        at: DateTime.utc(2026, 9, 1),
        remaining: 40,
      );
      final sorted = sortReceivablesFifo([openingRow, invoiceRow]);
      final allocations = fifoChequeAllocations(
        amount: 50,
        orders: sorted,
      );
      expect(allocations.single.orderId, 'o1');
      expect(allocations.single.amount, 50);
      expect(allocations.single.receivableAdjustmentId, isNull);
    });

    test('picker includes remaining opening balance', () {
      final sorted = sortReceivablesFifo([
        opening(id: 'ob1', at: DateTime.utc(2026, 1, 1), remaining: 25),
      ]);
      expect(sorted.single.isOpeningBalance, isTrue);
      expect(sorted.single.remaining, 25);
      expect(sorted.single.pickerTitle, 'Opening balance');
    });
  });

  group('Payment allocation JSON and labels', () {
    test('order allocation JSON is unchanged', () {
      const input = PaymentAllocationInput(orderId: 'ord-1', amount: 10);
      expect(input.toJson(), {'order_id': 'ord-1', 'amount': 10});
    });

    test('adjustment allocation JSON targets receivable_adjustment_id', () {
      const input = PaymentAllocationInput(
        receivableAdjustmentId: 'adj-1',
        amount: 20,
      );
      expect(input.toJson(), {
        'receivable_adjustment_id': 'adj-1',
        'amount': 20,
      });
      expect(input.toJson().containsKey('order_id'), isFalse);
    });

    test('payment details label for opening balance', () {
      const alloc = PaymentAllocation(
        id: 'a1',
        amount: 100,
        receivableAdjustmentId: 'adj-1',
        adjustmentNumber: 'OB-20261001-0001',
      );
      expect(alloc.displayLabel, 'Opening balance · OB-20261001-0001');
      expect(alloc.isOpeningBalance, isTrue);
    });

    test('payment details label for orders stays the invoice number', () {
      const alloc = PaymentAllocation(
        id: 'a1',
        amount: 100,
        orderId: 'o1',
        orderNumber: 'INV-9',
      );
      expect(alloc.displayLabel, 'INV-9');
    });
  });

  group('Collections Report opening-balance rows', () {
    final asOf = DateTime(2026, 10, 1);

    test('appears after recognized_at', () {
      final row = CollectionsReportMath.considerOpeningBalance(
        adjustmentId: 'adj-1',
        adjustmentNumber: 'OB-20260901-0001',
        recognizedAt: DateTime(2026, 9, 1, 10),
        amount: 500,
        customerId: 'c1',
        customerName: 'Namson',
        allocations: const [],
        asOfDate: asOf,
      );
      expect(row, isNotNull);
      expect(row!.documentType, kCollectionsOpeningBalanceDocumentType);
      expect(row.orderNumber, 'OB-20260901-0001');
      expect(row.openBalance, 500);
      expect(row.salesRepName, '—');
    });

    test('does not appear before recognized_at', () {
      expect(
        CollectionsReportMath.considerOpeningBalance(
          adjustmentId: 'adj-1',
          adjustmentNumber: 'OB-1',
          recognizedAt: DateTime(2026, 10, 2),
          amount: 500,
          customerId: 'c1',
          customerName: 'Namson',
          allocations: const [],
          asOfDate: asOf,
        ),
        isNull,
      );
    });

    test('later payment does not reduce as-of balance', () {
      final row = CollectionsReportMath.considerOpeningBalance(
        adjustmentId: 'adj-1',
        adjustmentNumber: 'OB-1',
        recognizedAt: DateTime(2026, 9, 1),
        amount: 500,
        customerId: 'c1',
        customerName: 'Namson',
        allocations: [
          CollectionsReportAllocation(
            amount: 200,
            receivedAt: DateTime(2026, 10, 2),
            completed: true,
          ),
        ],
        asOfDate: asOf,
      );
      expect(row!.openBalance, 500);
    });

    test('completed payment reduces as-of balance', () {
      final row = CollectionsReportMath.considerOpeningBalance(
        adjustmentId: 'adj-1',
        adjustmentNumber: 'OB-1',
        recognizedAt: DateTime(2026, 9, 1),
        amount: 500,
        customerId: 'c1',
        customerName: 'Namson',
        allocations: [
          CollectionsReportAllocation(
            amount: 200,
            receivedAt: DateTime(2026, 9, 15),
            completed: true,
          ),
        ],
        asOfDate: asOf,
      );
      expect(row!.openBalance, 300);
    });

    test('pending payment does not reduce remaining', () {
      final row = CollectionsReportMath.considerOpeningBalance(
        adjustmentId: 'adj-1',
        adjustmentNumber: 'OB-1',
        recognizedAt: DateTime(2026, 9, 1),
        amount: 500,
        customerId: 'c1',
        customerName: 'Namson',
        allocations: [
          CollectionsReportAllocation(
            amount: 200,
            receivedAt: DateTime(2026, 9, 15),
            completed: false,
          ),
        ],
        asOfDate: asOf,
      );
      expect(row!.openBalance, 500);
    });

    test('fully paid adjustment disappears', () {
      expect(
        CollectionsReportMath.considerOpeningBalance(
          adjustmentId: 'adj-1',
          adjustmentNumber: 'OB-1',
          recognizedAt: DateTime(2026, 9, 1),
          amount: 500,
          customerId: 'c1',
          customerName: 'Namson',
          allocations: [
            CollectionsReportAllocation(
              amount: 500,
              receivedAt: DateTime(2026, 9, 20),
              completed: true,
            ),
          ],
          asOfDate: asOf,
        ),
        isNull,
      );
    });

    test('All Sales Reps includes it', () {
      expect(
        CollectionsReportMath.includeOpeningBalanceForSalesReps(const []),
        isTrue,
      );
    });

    test('specific rep filter does not falsely attribute it', () {
      expect(
        CollectionsReportMath.considerOpeningBalance(
          adjustmentId: 'adj-1',
          adjustmentNumber: 'OB-1',
          recognizedAt: DateTime(2026, 9, 1),
          amount: 500,
          customerId: 'c1',
          customerName: 'Namson',
          allocations: const [],
          asOfDate: asOf,
          selectedEmployeeIds: const ['rep-a'],
        ),
        isNull,
      );
    });

    test('existing invoice rows remain Invoice', () {
      final invoice = CollectionsReportMath.considerOrder(
        orderId: 'o1',
        orderNumber: 'SO-1',
        orderedAt: DateTime(2026, 9, 1, 10),
        status: 'completed',
        archived: false,
        total: 100,
        customerId: 'c1',
        customerName: 'Alpha',
        salesRepId: 'rep-a',
        salesRepName: 'Nimal',
        allocations: const [],
        asOfDate: asOf,
      );
      expect(invoice, isNotNull);
      expect(invoice!.documentType, kCollectionsDocumentType);
    });

    test('old invoice / reference is extra and does not replace OB number', () {
      final row = CollectionsReportMath.considerOpeningBalance(
        adjustmentId: 'adj-1',
        adjustmentNumber: 'OB-20261001-0001',
        recognizedAt: DateTime(2026, 9, 1, 10),
        amount: 50000,
        customerId: 'c1',
        customerName: 'Namson',
        allocations: const [],
        asOfDate: asOf,
        referenceNumber: 'INV-4587',
      );
      expect(row, isNotNull);
      expect(row!.orderNumber, 'OB-20261001-0001');
      expect(row.referenceNumber, 'INV-4587');
      expect(row.documentType, kCollectionsOpeningBalanceDocumentType);
    });
  });

  group('Collection picker and allocation', () {
    test('Sales Rep picker shows opening balance remaining', () {
      final receivable = ReceivableOrder(
        id: 'adj-1',
        orderNumber: 'OB-20261001-0001',
        total: 50000,
        amountPaid: 0,
        orderedAt: DateTime.utc(2026, 10, 1),
        kind: ReceivableKind.openingBalance,
        referenceNumber: 'INV-4587',
      );
      expect(receivable.pickerTitle, 'Opening balance');
      expect(
        ReceivablePickerCopy.subtitleLines(
          receivable,
          currencySymbol: 'Rs ',
        ),
        [
          'OB-20261001-0001',
          'Due Rs 50,000.00',
          'Old invoice / reference: INV-4587',
        ],
      );
      final allocation = PaymentAllocationInput.fromReceivable(receivable, 50000);
      expect(allocation.receivableAdjustmentId, 'adj-1');
      expect(allocation.orderId, isNull);
      expect(allocation.toJson(), {
        'receivable_adjustment_id': 'adj-1',
        'amount': 50000,
      });
    });

    test('cheque FIFO against opening AR does not invent an order id', () {
      final opening = ReceivableOrder(
        id: 'adj-1',
        orderNumber: 'OB-1',
        total: 200,
        amountPaid: 0,
        orderedAt: DateTime.utc(2026, 1, 1),
        kind: ReceivableKind.openingBalance,
      );
      final allocations = fifoChequeAllocations(amount: 200, orders: [opening]);
      expect(allocations, hasLength(1));
      expect(allocations.single.receivableAdjustmentId, 'adj-1');
      expect(allocations.single.orderId, isNull);
    });

    test('allocated opening collection is not wallet overpayment', () {
      num overpay(num paymentAmount, num allocatedTotal) =>
          (paymentAmount - allocatedTotal).clamp(0, double.infinity);
      expect(overpay(50000, 50000), 0);
      expect(overpay(60000, 50000), 10000);
    });

    test('pending allocation does not reduce remaining until completed', () {
      final remaining = CollectionsReportMath.openBalanceAsOf(
        total: 50000,
        allocations: [
          CollectionsReportAllocation(
            amount: 10000,
            receivedAt: DateTime(2026, 9, 20),
            completed: false,
          ),
        ],
        asOfEndUtc: CollectionsReportMath.asOfEndUtc(DateTime(2026, 10, 1)),
      );
      expect(remaining, 50000);
    });

    test('completed allocation reduces remaining', () {
      final remaining = CollectionsReportMath.openBalanceAsOf(
        total: 50000,
        allocations: [
          CollectionsReportAllocation(
            amount: 10000,
            receivedAt: DateTime(2026, 9, 20),
            completed: true,
          ),
        ],
        asOfEndUtc: CollectionsReportMath.asOfEndUtc(DateTime(2026, 10, 1)),
      );
      expect(remaining, 40000);
    });
  });

  group('Old invoice / reference', () {
    test('optional and persisted on the adjustment model', () {
      final withRef = CustomerReceivableAdjustment.fromJson({
        'id': 'adj-1',
        'adjustment_number': 'OB-1',
        'amount': 50,
        'recognized_at': '2026-10-01T00:00:00Z',
        'reference_number': 'INV-4587',
      }, remaining: 50);
      expect(withRef.referenceNumber, 'INV-4587');

      final without = CustomerReceivableAdjustment.fromJson({
        'id': 'adj-2',
        'adjustment_number': 'OB-2',
        'amount': 50,
        'recognized_at': '2026-10-01T00:00:00Z',
      }, remaining: 50);
      expect(without.referenceNumber, isNull);
    });

    test('payment details keep the OB number and show the old reference', () {
      const alloc = PaymentAllocation(
        id: 'a1',
        amount: 100,
        receivableAdjustmentId: 'adj-1',
        adjustmentNumber: 'OB-20261001-0001',
        adjustmentReferenceNumber: 'INV-4587',
      );
      expect(alloc.displayLabel, 'Opening balance · OB-20261001-0001');
      expect(alloc.displayLabel, isNot(contains('INV-4587')));
      expect(alloc.adjustmentReferenceNumber, 'INV-4587');
    });
  });

  group('Opening-balance payment SMS copy', () {
    test('contains paid amount', () {
      final body = OutboundMessageTemplate.openingBalancePaymentReceived(
        amountLabel: 'Rs 50,000.00',
        businessName: 'Acme',
      );
      expect(body, contains('Payment received: Rs 50,000.00'));
      expect(body, contains('Acme'));
      expect(body.toLowerCase(), isNot(contains('aging')));
      expect(body, isNot(contains('OB-')));
      expect(body.toLowerCase(), isNot(contains('sales rep')));
    });

    test('includes old invoice / reference when available', () {
      final body = OutboundMessageTemplate.openingBalancePaymentReceived(
        amountLabel: 'Rs 50,000.00',
        oldInvoiceReference: 'INV-4587',
        businessName: 'Acme',
      );
      expect(body, contains('Reference: INV-4587'));
    });

    test('omits reference line when empty', () {
      final body = OutboundMessageTemplate.openingBalancePaymentReceived(
        amountLabel: 'Rs 10.00',
      );
      expect(body, isNot(contains('Reference:')));
    });

    test('order collection acknowledgement copy is unchanged', () {
      final body = OutboundMessageTemplate.render(
        OutboundMessageTemplate.collectionAcknowledgementDefault,
        values: {
          'business_name': 'Acme',
          'customer_name': 'City Mart',
          'collection_amount': 'Rs 1,000.00',
          'collection_number': 'PAY-1',
        },
      );
      expect(body, contains('pending owner/manager review'));
      expect(body, isNot(contains('Payment received:')));
    });
  });
}
