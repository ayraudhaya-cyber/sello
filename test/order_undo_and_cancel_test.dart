import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261029000128_128_undo_delivery_and_cancel_order.sql',
  ).readAsStringSync();

  final undo = sql.split('create or replace function public.cancel_sales_order').first;
  final cancel = sql.split('create or replace function public.cancel_sales_order').last;

  test('marking not delivered returns the order to placed and keeps payments', () {
    expect(undo, contains('mark_order_not_delivered'));
    expect(undo, contains("'correction'"));
    expect(undo, contains('apply_order_fulfillment_receivable'));
    expect(undo, contains('refresh_order_fulfillment_status'));
    expect(undo, contains('This order has returned items'));
    expect(undo, isNot(contains("status = 'cancelled'")));
    expect(undo, isNot(contains('order_returns')));
  });

  test('cancel settles stock and asks where paid money goes', () {
    expect(cancel, contains("status = 'cancelled'"));
    expect(cancel, contains("destination not in ('cash', 'wallet')"));
    expect(cancel, contains('wallet_balance = wallet_balance + paid_part'));
    expect(cancel, contains("'refunded'"));
    expect(cancel, contains('recognized_receivable_value = 0'));
    expect(cancel, contains('A cheque on this order has not cleared yet'));
    expect(cancel, isNot(contains('insert into public.order_returns')));
  });
}
