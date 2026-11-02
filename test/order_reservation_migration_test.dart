import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261102000130_130_order_stock_reservations.sql',
  ).readAsStringSync();

  test('placing an order reserves stock and does not sell it yet', () {
    expect(sql, contains('function public.place_sales_order'));
    expect(sql, contains('apply_order_stock_hold'));
    expect(
      sql,
      contains('Does not change on-hand quantity or payments.'),
    );
  });

  test('delivery consumes the hold and reduces on-hand stock', () {
    expect(sql, contains('function public.consume_reserved_stock'));
    expect(sql, contains("'Fulfilled'"));
    expect(sql, contains('function public.fulfill_order_items'));
    expect(sql, contains('function public.complete_sales_order'));
    expect(sql, contains('can_record_order_delivery'));
  });

  test('cancel, undo, and invoice edits move the hold', () {
    expect(sql, contains('function public.cancel_order_remaining'));
    expect(sql, contains('function public.cancel_sales_order'));
    expect(sql, contains('function public.mark_order_not_delivered'));
    expect(sql, contains('function public.restock_and_rehold'));
    expect(sql, contains('function public.correct_invoice'));
    expect(sql, contains('function public.cancel_order_return'));
    expect(sql, contains('transportation_payer'));
    expect(sql, contains('returned_quantity > 0'));
  });

  test('backfill reserves open orders without changing on-hand quantity', () {
    expect(sql, contains('set reserved_quantity = d.demand'));
    expect(sql, contains('set reserved_quantity = 0'));
    expect(sql, contains('drop table if exists _order_stock_demand'));
    expect(sql, contains('Wait for in-flight place'));
    expect(sql, isNot(contains('reserved_quantity + d.demand')));
    expect(sql, isNot(contains('reserved_quantity = reserved_quantity + d.demand')));
    expect(
      sql,
      contains('Stock reservation backfill changed on-hand quantity.'),
    );
    expect(sql, isNot(contains('set quantity =')));
  });

  test('delivery keeps physical stock for older orders at the same branch', () {
    expect(sql, contains('Older open orders still need'));
    expect(sql, contains('o.branch_id = p_branch_id'));
    expect(sql, contains('open_need - p_quantity'));
    expect(sql, contains("o.status in ('placed', 'partially_delivered')"));
  });
}
