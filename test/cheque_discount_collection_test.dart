import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/features/payments/application/receive_payment_allocation.dart';
import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261026000127_127_cheque_collection_discount.sql',
  ).readAsStringSync();

  String functionBody(String name) {
    final start = migration.indexOf('function public.$name');
    expect(start, greaterThanOrEqualTo(0), reason: '$name missing');
    final end = migration.indexOf('\$\$;', start);
    expect(end, greaterThan(start));
    return migration.substring(start, end);
  }

  ReceivableOrder opening(num remaining) {
    return ReceivableOrder(
      id: 'ob-1',
      orderNumber: 'OB-20261006-0044',
      total: remaining,
      amountPaid: 0,
      orderedAt: DateTime.utc(2026, 10, 6),
      kind: ReceivableKind.openingBalance,
    );
  }

  group('partial, full, and discounted cheque cover', () {
    test('a partial cheque covers only the allocated face value', () {
      final row = opening(55502);
      final allocations = {'ob-1': 25000};
      expect(
        ReceivePaymentAllocation.validate(
          paymentAmount: 25000,
          allocations: allocations,
          receivables: [row],
        ),
        isNull,
      );
      expect(
        chequeOutstandingReduction(
          status: ChequeStatus.collected,
          netPaid: 25000,
          discount: 0,
          balanceApplied: true,
        ),
        25000,
      );
      expect(55502 - 25000, 30502);
    });

    test('a full cheque covers the whole opening balance once', () {
      expect(
        chequeOutstandingReduction(
          status: ChequeStatus.collected,
          netPaid: 55502,
          discount: 0,
          balanceApplied: true,
        ),
        55502,
      );
    });

    test('discount and the cheque face reduce outstanding once', () {
      final row = opening(30000);
      expect(
        ReceivePaymentAllocation.validate(
          paymentAmount: 25000,
          discountAmount: 5000,
          allocations: {'ob-1': 30000},
          receivables: [row],
        ),
        isNull,
      );
      expect(
        chequeOutstandingReduction(
          status: ChequeStatus.collected,
          netPaid: 25000,
          discount: 5000,
          balanceApplied: true,
        ),
        30000,
      );
      expect(
        chequeOutstandingReduction(
          status: ChequeStatus.cleared,
          netPaid: 25000,
          discount: 5000,
          balanceApplied: true,
        ),
        30000,
      );
    });

    test('an unreceived cheque does not reduce outstanding', () {
      expect(
        chequeOutstandingReduction(
          status: ChequeStatus.awaitingCollection,
          netPaid: 25000,
          discount: 5000,
          balanceApplied: false,
        ),
        0,
      );
      expect(
        chequeOutstandingReduction(
          status: ChequeStatus.bounced,
          netPaid: 25000,
          discount: 5000,
          balanceApplied: false,
        ),
        0,
      );
    });
  });

  group('cheque ledger migration', () {
    test('stores discount on the cheque and pays it as a cheque', () {
      final created = functionBody('create_cheque');
      expect(created, contains('v_discount'));
      expect(created, contains("initial_status text := 'awaiting_collection'"));
      expect(created, contains('if mark_collected then'));
      expect(created, isNot(contains("status := 'cleared'")));

      final payment = functionBody('_create_cheque_collection_payment');
      expect(payment, contains("'cheque'"));
      expect(payment, contains('v_discount'));
      expect(payment, contains('ch.amount'));
      expect(payment, contains('settlement'));
      expect(payment, contains('apply_payment_financials(v_payment_id)'));
      expect(
        payment,
        contains(
          'Allocate the full payment and discount to the order or opening balance.',
        ),
      );
      expect(payment, isNot(contains("status := 'cleared'")));
      expect(payment, contains('if ch.payment_id is not null'));
    });
  });

  test('collection SMS lists original, discount, and net paid separately', () {
    final body = OutboundMessageTemplate.render(
      OutboundMessageTemplate.receiptDefault,
      values: {
        'business_name': 'Namson',
        'customer_name': 'Mirissa Trading',
        'collection_number': 'PAY-9',
        'collection_amount': 'Rs 25,000.00',
        'original_amount': 'Rs 30,000.00',
        'discount_amount': 'Rs 5,000.00',
        'net_amount': 'Rs 25,000.00',
      },
    );

    expect(body, contains('Original amount: Rs 30,000.00'));
    expect(body, contains('Discount granted: Rs 5,000.00'));
    expect(body, contains('Net amount paid: Rs 25,000.00'));
  });
}
