import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/hub/reports/application/collections_report_excel.dart';
import 'package:sello/features/hub/reports/application/collections_report_pdf.dart';
import 'package:sello/features/hub/reports/application/report_catalog.dart';
import 'package:sello/shared/models/collections_report.dart';

CollectionsReportInvoice? _consider({
  required DateTime asOf,
  DateTime? orderedAt,
  String status = 'completed',
  bool archived = false,
  num total = 100,
  String customerId = 'c1',
  String customerName = 'Alpha Traders',
  String? customerPhone = '0771234567',
  String salesRepId = 'rep-a',
  String salesRepName = 'Nimal',
  String orderId = 'o1',
  String orderNumber = 'SO-1',
  List<CollectionsReportAllocation> allocations = const [],
  List<String> selectedEmployeeIds = const [],
}) {
  return CollectionsReportMath.considerOrder(
    orderId: orderId,
    orderNumber: orderNumber,
    orderedAt: orderedAt ?? DateTime(2026, 9, 1, 10),
    status: status,
    archived: archived,
    total: total,
    customerId: customerId,
    customerName: customerName,
    customerPhone: customerPhone,
    salesRepId: salesRepId,
    salesRepName: salesRepName,
    allocations: allocations,
    asOfDate: asOf,
    selectedEmployeeIds: selectedEmployeeIds,
  );
}

void main() {
  test('catalog exposes the collections report under Payments', () {
    final definition = ReportCatalog.definitions.singleWhere(
      (item) => item.id == kCollectionsReportId,
    );
    expect(definition.title, kCollectionsReportTitle);
    expect(definition.category.name, 'payments');
    expect(definition.available, isTrue);
  });

  final asOf = DateTime(2026, 9, 15);

  group('as-of eligibility', () {
    test('orders after the as-of date are excluded', () {
      expect(
        _consider(asOf: asOf, orderedAt: DateTime(2026, 9, 16, 8)),
        isNull,
      );
      expect(
        _consider(asOf: asOf, orderedAt: DateTime(2026, 9, 15, 18)),
        isNotNull,
      );
    });

    test('payments received after the as-of date do not reduce the balance', () {
      final invoice = _consider(
        asOf: asOf,
        allocations: [
          CollectionsReportAllocation(
            amount: 100,
            receivedAt: DateTime(2026, 9, 16, 9),
            completed: true,
          ),
        ],
      );
      expect(invoice, isNotNull);
      expect(invoice!.openBalance, 100);
    });

    test('completed payments on or before as-of reduce the balance', () {
      final invoice = _consider(
        asOf: asOf,
        allocations: [
          CollectionsReportAllocation(
            amount: 40,
            receivedAt: DateTime(2026, 9, 15, 12),
            completed: true,
          ),
        ],
      );
      expect(invoice, isNotNull);
      expect(invoice!.openBalance, 60);
    });

    test('pending collections do not reduce the balance', () {
      final invoice = _consider(
        asOf: asOf,
        allocations: [
          CollectionsReportAllocation(
            amount: 80,
            receivedAt: DateTime(2026, 9, 10),
            completed: false,
          ),
        ],
      );
      expect(invoice, isNotNull);
      expect(invoice!.openBalance, 100);
    });

    test('unapplied cheques do not reduce the balance', () {
      expect(
        _consider(asOf: asOf, allocations: const [])!.openBalance,
        100,
      );
    });

    test('fully paid orders as of the date are excluded', () {
      expect(
        _consider(
          asOf: asOf,
          allocations: [
            CollectionsReportAllocation(
              amount: 100,
              receivedAt: DateTime(2026, 9, 2),
              completed: true,
            ),
          ],
        ),
        isNull,
      );
    });

    test('cancelled, draft, and archived orders are excluded', () {
      expect(_consider(asOf: asOf, status: 'cancelled'), isNull);
      expect(_consider(asOf: asOf, status: 'draft'), isNull);
      expect(_consider(asOf: asOf, archived: true), isNull);
      expect(_consider(asOf: asOf, status: 'placed'), isNotNull);
    });
  });

  group('sales-rep filter', () {
    test('all reps includes every seller', () {
      expect(
        _consider(asOf: asOf, salesRepId: 'rep-a', selectedEmployeeIds: const []),
        isNotNull,
      );
      expect(
        _consider(asOf: asOf, salesRepId: 'rep-b', selectedEmployeeIds: const []),
        isNotNull,
      );
    });

    test('one rep keeps only that seller', () {
      expect(
        _consider(
          asOf: asOf,
          salesRepId: 'rep-a',
          selectedEmployeeIds: const ['rep-a'],
        ),
        isNotNull,
      );
      expect(
        _consider(
          asOf: asOf,
          salesRepId: 'rep-b',
          selectedEmployeeIds: const ['rep-a'],
        ),
        isNull,
      );
    });

    test('multiple reps keep each selected seller', () {
      expect(
        _consider(
          asOf: asOf,
          salesRepId: 'rep-a',
          selectedEmployeeIds: const ['rep-a', 'rep-c'],
        ),
        isNotNull,
      );
      expect(
        _consider(
          asOf: asOf,
          salesRepId: 'rep-c',
          selectedEmployeeIds: const ['rep-a', 'rep-c'],
        ),
        isNotNull,
      );
      expect(
        _consider(
          asOf: asOf,
          salesRepId: 'rep-b',
          selectedEmployeeIds: const ['rep-a', 'rep-c'],
        ),
        isNull,
      );
    });
  });

  group('grouping and totals', () {
    late CollectionsReportSnapshot snapshot;

    setUp(() {
      snapshot = CollectionsReportMath.assemble(
        asOfDate: asOf,
        salesRepsLabel: 'All Sales Reps',
        currencySymbol: 'Rs ',
        invoices: [
          _consider(
            asOf: asOf,
            orderId: 'o2',
            orderNumber: 'SO-2',
            customerId: 'c2',
            customerName: 'Beta Hardware',
            total: 50,
          )!,
          _consider(
            asOf: asOf,
            orderId: 'o1',
            orderNumber: 'SO-1',
            customerId: 'c1',
            customerName: 'Alpha Traders',
            total: 100,
            allocations: [
              CollectionsReportAllocation(
                amount: 25,
                receivedAt: DateTime(2026, 9, 5),
                completed: true,
              ),
            ],
          )!,
          _consider(
            asOf: asOf,
            orderId: 'o3',
            orderNumber: 'SO-3',
            orderedAt: DateTime(2026, 9, 3, 10),
            customerId: 'c1',
            customerName: 'Alpha Traders',
            total: 20,
          )!,
        ],
      );
    });

    test('orders are grouped by customer in name order', () {
      expect(snapshot.groups.map((g) => g.customerName), [
        'Alpha Traders',
        'Beta Hardware',
      ]);
      expect(
        snapshot.groups.first.invoices.map((i) => i.orderNumber),
        ['SO-1', 'SO-3'],
      );
    });

    test('customer subtotals are the sum of open invoices', () {
      expect(snapshot.groups.first.subtotal, 95);
      expect(snapshot.groups.last.subtotal, 50);
    });

    test('grand total is the sum of customer subtotals', () {
      expect(snapshot.grandTotal, 145);
    });

    test('aging is days from ordered_at to the as-of date', () {
      expect(
        CollectionsReportMath.agingDays(
          orderedAt: DateTime(2026, 9, 1, 10),
          asOfDate: asOf,
        ),
        14,
      );
      expect(snapshot.groups.first.invoices.first.agingDays, 14);
      expect(snapshot.groups.first.invoices.last.agingDays, 12);
    });
  });

  group('exports', () {
    final snapshot = CollectionsReportMath.assemble(
      asOfDate: DateTime(2026, 9, 15),
      salesRepsLabel: 'Nimal',
      currencySymbol: 'Rs ',
      invoices: [
        CollectionsReportInvoice(
          orderId: 'o1',
          orderNumber: 'SO-1',
          orderedAt: DateTime(2026, 9, 1),
          customerId: 'c1',
          customerName: 'Alpha Traders',
          customerPhone: '0771234567',
          salesRepId: 'rep-a',
          salesRepName: 'Nimal',
          openBalance: 75.5,
          agingDays: 14,
        ),
      ],
    );

    test('Excel contains exactly the agreed columns and snapshot values', () {
      expect(CollectionsReportExcelExporter.headers, [
        'Customer',
        'Customer Contact',
        'Sales Rep',
        'Document Type',
        'Document No.',
        'Old invoice / reference',
        'Date',
        'Aging (days)',
        'Open Balance',
      ]);
      final xml = utf8.decode(
        CollectionsReportExcelExporter.buildBytes(snapshot),
      );
      expect(xml, contains('Customer</Data>'));
      expect(xml, contains('Customer Contact'));
      expect(xml, contains('Sales Rep'));
      expect(xml, contains('Document Type'));
      expect(xml, contains('Document No.'));
      expect(xml, contains('Old invoice / reference'));
      expect(xml, contains('Aging (days)'));
      expect(xml, contains('Open Balance'));
      expect(xml, isNot(contains('P.O.')));
      expect(xml, isNot(contains('Due Date')));
      expect(xml, contains('Alpha Traders'));
      expect(xml, contains('0771234567'));
      expect(xml, contains('Nimal'));
      expect(xml, contains('Invoice'));
      expect(xml, contains('SO-1'));
      expect(xml, contains('75.5'));
      expect(xml, contains('14'));
    });

    test('PDF is built from the same snapshot as the preview', () async {
      expect(snapshot.invoices.single.openBalance, 75.5);
      expect(snapshot.grandTotal, 75.5);
      expect(snapshot.groups.single.subtotal, snapshot.grandTotal);

      final excelXml = utf8.decode(
        CollectionsReportExcelExporter.buildBytes(snapshot),
      );
      expect(excelXml, contains('75.5'));

      final pdf = await CollectionsReportPdf.buildBytes(snapshot);
      expect(pdf.length, greaterThan(100));
      expect(ascii.decode(pdf.take(4).toList()), '%PDF');
    });
  });
}
