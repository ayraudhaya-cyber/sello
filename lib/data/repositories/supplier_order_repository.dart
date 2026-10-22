import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/supplier_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupplierOrderPage {
  const SupplierOrderPage({required this.items, required this.hasMore});

  final List<SupplierOrderSummary> items;
  final bool hasMore;
}

class SupplierOrderRepository {
  SupplierOrderRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const _listSelect = '''
    id,
    company_id,
    branch_id,
    supplier_id,
    order_number,
    supplier_name,
    status,
    payment_method,
    total,
    recognized_payable,
    notes,
    ordered_at,
    created_at,
    suppliers!supplier_id ( name, phone, whatsapp ),
    supplier_payments ( id, payment_number, amount, method, status, paid_at )
  ''';

  static const _detailSelect = '''
    id,
    company_id,
    branch_id,
    supplier_id,
    order_number,
    supplier_name,
    status,
    payment_method,
    total,
    recognized_payable,
    notes,
    ordered_at,
    created_at,
    suppliers!supplier_id ( name, phone, whatsapp ),
    supplier_order_lines (
      id,
      product_id,
      variant_id,
      product_name,
      variant_label,
      sku,
      quantity,
      received_quantity,
      cancelled_quantity,
      unit_cost,
      line_total
    ),
    supplier_receipts (
      id,
      receipt_number,
      received_at,
      supplier_receipt_lines ( line_value )
    ),
    supplier_payments (
      id,
      payment_number,
      amount,
      method,
      status,
      reference,
      paid_at
    )
  ''';

  Future<SupplierOrderPage> fetchPage({
    required String companyId,
    String search = '',
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('supplier_orders')
          .select(_listSelect)
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);
      final needle = search.trim();
      if (needle.isNotEmpty) {
        query = query.or(
          'order_number.ilike.%$needle%,supplier_name.ilike.%$needle%',
        );
      }
      final rows = await query
          .order('created_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize);
      final list = rows as List;
      final hasMore = list.length > pageSize;
      final pageRows = hasMore ? list.sublist(0, pageSize) : list;
      return SupplierOrderPage(
        items: [
          for (final raw in pageRows)
            SupplierOrderSummary.fromJson(Map<String, dynamic>.from(raw as Map)),
        ],
        hasMore: hasMore,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(_message(error.message));
    }
  }

  Future<SupplierOrderSummary> fetchById(String orderId) async {
    try {
      final row = await _client
          .from('supplier_orders')
          .select(_detailSelect)
          .eq('id', orderId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) {
        throw const ValidationFailure('Supplier order not found.');
      }
      return SupplierOrderSummary.fromJson(Map<String, dynamic>.from(row));
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(_message(error.message));
    }
  }

  Future<String> save({
    String? orderId,
    required String supplierId,
    required String branchId,
    required List<
      ({String productId, String? variantId, num quantity, num unitCost})
    >
    lines,
    String? paymentMethod,
    String? notes,
    required bool place,
  }) async {
    try {
      final result = await _client.rpc(
        'save_supplier_order',
        params: {
          'p_order_id': orderId,
          'p_payload': {
            'supplier_id': supplierId,
            'branch_id': branchId,
            'payment_method': paymentMethod,
            'notes': notes,
            'place': place,
            'lines': [
              for (final line in lines)
                {
                  'product_id': line.productId,
                  if (line.variantId != null) 'variant_id': line.variantId,
                  'quantity': line.quantity,
                  'unit_cost': line.unitCost,
                },
            ],
          },
        },
      );
      final map = Map<String, dynamic>.from(result as Map);
      return map['id'] as String;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    }
  }

  Future<String> receive({
    required String orderId,
    required List<({String orderLineId, num quantity})> lines,
  }) async {
    try {
      final result = await _client.rpc(
        'receive_supplier_order',
        params: {
          'p_order_id': orderId,
          'p_lines': [
            for (final line in lines)
              {'order_line_id': line.orderLineId, 'quantity': line.quantity},
          ],
        },
      );
      final map = Map<String, dynamic>.from(result as Map);
      return map['receipt_number'] as String? ?? 'Goods received';
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    }
  }

  Future<void> closeRemaining(String orderId) async {
    try {
      await _client.rpc(
        'close_supplier_order_remaining',
        params: {'p_order_id': orderId},
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    }
  }

  Future<void> cancel(String orderId) async {
    try {
      await _client.rpc(
        'cancel_supplier_order',
        params: {'p_order_id': orderId},
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    }
  }

  Future<void> recordPayment({
    required String orderId,
    required num amount,
    required String method,
    String? reference,
    String? notes,
  }) async {
    try {
      await _client.rpc(
        'record_supplier_payment',
        params: {
          'p_order_id': orderId,
          'p_amount': amount,
          'p_method': method,
          'p_reference': reference,
          'p_notes': notes,
        },
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    }
  }

  Future<void> clearCheque(String paymentId) async {
    try {
      await _client.rpc(
        'clear_supplier_cheque',
        params: {'p_payment_id': paymentId},
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    }
  }

  String _message(String raw) {
    final text = raw.trim();
    final marker = text.indexOf('ERROR:');
    if (marker >= 0) {
      return text.substring(marker + 6).split('\n').first.trim();
    }
    return text;
  }
}
