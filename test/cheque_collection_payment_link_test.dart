import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261001000083_083_cheque_collection_payment_var.sql',
  ).readAsStringSync();
  final collect = File(
    'supabase/migrations/20260914000066_066_cheque_collection_approval.sql',
  ).readAsStringSync();

  String functionBody(String sql, String name) {
    final start = sql.indexOf('function public.$name');
    expect(start, greaterThanOrEqualTo(0), reason: '$name missing');
    final end = sql.indexOf('\$\$;', start);
    expect(end, greaterThan(start));
    return sql.substring(start, end);
  }

  test('Collect writes the new payment onto the cheque without ambiguity', () {
    final body = functionBody(migration, '_create_cheque_collection_payment');

    expect(body, contains('payment_id = v_payment_id'));
    expect(
      body,
      isNot(contains('_create_cheque_collection_payment.payment_id')),
    );
    expect(body, isNot(contains('payment_id = payment_id,')));
    expect(body, contains('_insert_cheque_allocations'));
    expect(body, contains('apply_payment_financials(v_payment_id)'));
  });

  test('a cheque that already has a payment is not collected twice', () {
    final body = functionBody(migration, '_create_cheque_collection_payment');
    expect(body, contains('if ch.payment_id is not null'));
    expect(body, contains('return ch.payment_id'));

    final collectBody = functionBody(collect, 'collect_cheque');
    expect(
      collectBody,
      contains("if ch.status = 'collected' and ch.payment_id is not null"),
    );
    expect(collectBody, contains('status = \'collected\''));
    expect(collectBody, contains('_create_cheque_collection_payment'));
  });

  test('awaiting cheques are still created without a payment', () {
    final created = functionBody(collect, 'create_cheque');
    expect(created, contains("initial_status text := 'awaiting_collection'"));
    expect(created, contains('if mark_collected then'));
  });
}
