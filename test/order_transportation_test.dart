import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/transportation_payer.dart';

void main() {
  group('OrderCalculations transportation', () {
    test('seller-paid transport stays off the customer total', () {
      expect(
        OrderCalculations.grandTotal(
          subtotal: 1000,
          transportationCost: 250,
          customerPaysTransportation: false,
        ),
        1000,
      );
      expect(OrderCalculations.goodsTotal(subtotal: 1000), 1000);
    });

    test('customer-paid transport is added on top of the goods total', () {
      expect(
        OrderCalculations.grandTotal(
          subtotal: 1000,
          orderDiscount: 100,
          transportationCost: 200,
          customerPaysTransportation: true,
        ),
        1100,
      );
    });

    test('switching the payer changes only the customer total', () {
      const goods = 800;
      final seller = OrderCalculations.grandTotal(
        subtotal: goods,
        transportationCost: 150,
      );
      final customer = OrderCalculations.grandTotal(
        subtotal: goods,
        transportationCost: 150,
        customerPaysTransportation: true,
      );
      expect(seller, goods);
      expect(customer - seller, 150);
    });
  });

  test('a receivable remaining grows by customer-paid transportation', () {
    final before = ReceivableOrder(
      id: 'order',
      orderNumber: 'SO-1',
      total: 1000,
      amountPaid: 200,
      orderedAt: DateTime.utc(2026, 11, 2),
    );
    final after = ReceivableOrder(
      id: before.id,
      orderNumber: before.orderNumber,
      total: before.total + 180,
      amountPaid: before.amountPaid,
      orderedAt: before.orderedAt,
      transportationCost: 180,
      transportationPayer: TransportationPayer.receiver,
    );
    expect(after.remaining - before.remaining, 180);
  });

  test('migration stores transportation and does not add an SMS line', () {
    final sql = File(
      'supabase/migrations/20261102000129_129_order_transportation_cost.sql',
    ).readAsStringSync();
    expect(sql, contains('transportation_cost'));
    expect(sql, contains('transportation_payer'));
    expect(sql, contains('set_order_transportation'));
    expect(sql, contains("'transportation_cost'"));
    expect(sql, isNot(contains('{{transport')));

    final sms = File(
      'lib/services/notifications/outbound/outbound_message_template.dart',
    ).readAsStringSync();
    expect(sms, contains('{{order_total}}'));
    expect(sms, isNot(contains('transport')));
  });
}
