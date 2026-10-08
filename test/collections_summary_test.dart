import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/collections/application/collections_excel_exporter.dart';
import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

PaymentSummary _payment({
  required String id,
  required num amount,
  PaymentRecordStatus status = PaymentRecordStatus.completed,
  String employeeId = 'rep-1',
  String employeeName = 'Vyra',
  List<PaymentAllocation> allocations = const [],
}) {
  return PaymentSummary(
    id: id,
    companyId: 'c1',
    customerId: 'cust-1',
    employeeId: employeeId,
    paymentNumber: 'PAY-$id',
    amount: amount,
    method: PaymentMethod.cash,
    status: status,
    receivedAt: DateTime.utc(2026, 10, 8, 6, 30),
    customerName: 'Shop & Sons',
    employeeName: employeeName,
    allocations: allocations,
  );
}

const _orderAlloc = PaymentAllocation(
  id: 'a1',
  amount: 600,
  orderId: 'o1',
  orderNumber: 'SO-1001',
);
const _openingAlloc = PaymentAllocation(
  id: 'a2',
  amount: 400,
  receivableAdjustmentId: 'adj1',
  adjustmentNumber: 'OB-0003',
);

void main() {
  group('CollectionsPeriod', () {
    final now = DateTime(2026, 10, 8, 15); // Thursday

    test('today is one local day', () {
      final r = CollectionsPeriod.today.range(now);
      expect(r.from, DateTime(2026, 10, 8));
      expect(r.before, DateTime(2026, 10, 9));
    });

    test('week starts on Monday', () {
      final r = CollectionsPeriod.thisWeek.range(now);
      expect(r.from, DateTime(2026, 10, 5));
      expect(r.before, DateTime(2026, 10, 12));
    });

    test('this and last month', () {
      final cur = CollectionsPeriod.thisMonth.range(now);
      expect(cur.from, DateTime(2026, 10));
      expect(cur.before, DateTime(2026, 11));
      final last = CollectionsPeriod.lastMonth.range(now);
      expect(last.from, DateTime(2026, 9));
      expect(last.before, DateTime(2026, 10));
    });

    test('last month across a year boundary', () {
      final r = CollectionsPeriod.lastMonth.range(DateTime(2027, 1, 10));
      expect(r.from, DateTime(2026, 12));
      expect(r.before, DateTime(2027, 1));
    });
  });

  group('PaymentSummary type', () {
    test('order, opening balance, both, and on account', () {
      expect(
        _payment(id: '1', amount: 600, allocations: const [_orderAlloc])
            .collectionTypeLabel,
        'Order',
      );
      expect(
        _payment(id: '2', amount: 400, allocations: const [_openingAlloc])
            .collectionTypeLabel,
        'Opening balance',
      );
      final both = _payment(
        id: '3',
        amount: 1000,
        allocations: const [_orderAlloc, _openingAlloc],
      );
      expect(both.collectionTypeLabel, 'Order + Opening balance');
      expect(both.allocationSummary, 'SO-1001, Opening balance · OB-0003');
      expect(_payment(id: '4', amount: 50).collectionTypeLabel, 'On account');
    });
  });

  group('CollectionsSummary', () {
    test('collected excludes pending and rejected, and splits by type', () {
      final summary = CollectionsSummary.of([
        _payment(
          id: '1',
          amount: 1000,
          allocations: const [_orderAlloc, _openingAlloc],
        ),
        _payment(id: '2', amount: 200, employeeId: 'rep-2', employeeName: 'Udhaya'),
        _payment(
          id: '3',
          amount: 500,
          status: PaymentRecordStatus.pending,
        ),
        _payment(
          id: '4',
          amount: 900,
          status: PaymentRecordStatus.rejected,
        ),
      ]);

      expect(summary.collected, 1200);
      expect(summary.collectedCount, 2);
      expect(summary.pending, 500);
      expect(summary.pendingCount, 1);
      expect(summary.openingCollected, 400);
      expect(summary.orderCollected, 800); // 600 + unallocated 200
      expect(summary.byRep.map((r) => r.name), ['Vyra', 'Udhaya']);
      expect(summary.byRep.first.pending, 500);
    });
  });

  group('CollectionsExcelExporter', () {
    test('lists collected and pending, drops rejected, escapes text', () {
      final bytes = CollectionsExcelExporter.buildBytes(
        rows: [
          _payment(id: '1', amount: 600, allocations: const [_orderAlloc]),
          _payment(
            id: '2',
            amount: 500,
            status: PaymentRecordStatus.pending,
          ),
          _payment(
            id: '3',
            amount: 900,
            status: PaymentRecordStatus.rejected,
          ),
        ],
        from: DateTime(2026, 10),
        to: DateTime(2026, 10, 31),
      );
      final xml = utf8.decode(bytes);

      expect(xml, contains('ss:Name="Collections"'));
      expect(xml, contains('ss:Name="By sales rep"'));
      expect(xml, contains('Shop &amp; Sons'));
      expect(xml, contains('SO-1001'));
      expect(xml, contains('Awaiting approval'));
      expect(xml, isNot(contains('PAY-3')));
      expect(xml, contains('<Data ss:Type="Number">600</Data>'));
      expect(
        CollectionsExcelExporter.filename(
          from: DateTime(2026, 10),
          to: DateTime(2026, 10, 31),
        ),
        'sello-collections-20261001-20261031.xls',
      );
    });
  });
}
