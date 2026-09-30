import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/company_settings.dart';

void main() {
  group('Sales Rep record-delivery setting', () {
    test('defaults on so existing tenants keep Sales delivery', () {
      expect(CompanySettings.defaults.salesRepsCanRecordDelivery, isTrue);
    });

    test('fromJson treats a missing flag as allowed', () {
      expect(
        CompanySettings.fromJson(_row()).salesRepsCanRecordDelivery,
        isTrue,
      );
    });

    test('fromJson reads an Owner/Manager restriction', () {
      final settings = CompanySettings.fromJson(
        _row({'sales_reps_can_record_delivery': false}),
      );
      expect(settings.salesRepsCanRecordDelivery, isFalse);
    });

    test('settings payload persists the delivery flag', () {
      final settings = CompanySettings.fromJson(
        _row({'sales_reps_can_record_delivery': false}),
      );
      final payload = settings.toUpdatePayload(employeeId: 'emp-1');
      expect(payload['sales_reps_can_record_delivery'], isFalse);
    });

    test('RPC gate lives in 087 and only blocks Sales Representatives', () {
      final sql = File(
        'supabase/migrations/20261001000087_087_sales_rep_record_delivery.sql',
      ).readAsStringSync();
      expect(sql, contains('sales_reps_can_record_delivery'));
      expect(sql, contains('can_record_order_delivery'));
      expect(sql, contains("'sales_representative'"));
      expect(sql, contains('if not public.can_record_order_delivery()'));
      expect(sql, contains('create or replace function public.fulfill_order_items'));
      expect(sql, contains('create or replace function public.complete_sales_order'));
      expect(sql, isNot(contains("'manager'")));
    });
  });
}

Map<String, dynamic> _row([Map<String, dynamic>? overrides]) {
  return {
    'id': 'settings-1',
    'company_id': 'company-1',
    'currency': 'USD',
    'currency_position': 'before',
    'financial_year_start_month': 1,
    'default_tax_mode': 'exclusive',
    'default_reorder_level': 10,
    'default_product_status': 'active',
    'allow_negative_stock': false,
    'enable_low_stock_alert': true,
    'sales_reps_can_view_outstanding_balances': true,
    ...?overrides,
  };
}
