import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/order_return.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderReturnPage {
  const OrderReturnPage({required this.items, required this.hasMore});

  final List<OrderReturnSummary> items;
  final bool hasMore;
}

class OrderReturnRepository {
  OrderReturnRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const _listSelect = '''
    id,
    return_number,
    order_id,
    order_number,
    customer_name,
    return_value,
    owed_reduction,
    paid_portion,
    paid_destination,
    restock,
    returned_at,
    status,
    order_return_lines (
      quantity,
      line_value,
      order_items (
        product_name,
        variant_label
      )
    )
  ''';

  Future<OrderReturnContext> fetchContext(String orderId) async {
    try {
      final raw = await _client.rpc(
        'return_order_context',
        params: {'p_order_id': orderId},
      );
      if (raw is Map<String, dynamic>) {
        return OrderReturnContext.fromJson(raw);
      }
      if (raw is Map) {
        return OrderReturnContext.fromJson(Map<String, dynamic>.from(raw));
      }
      throw const UnexpectedFailure('Unable to prepare this return.');
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<OrderReturnSummary> submit({
    required String orderId,
    required List<({String orderItemId, num quantity})> lines,
    required OrderReturnDestination destination,
    required bool restock,
  }) async {
    try {
      final raw = await _client.rpc(
        'return_order_items',
        params: {
          'p_order_id': orderId,
          'p_lines': [
            for (final line in lines)
              {'order_item_id': line.orderItemId, 'quantity': line.quantity},
          ],
          'p_destination': destination.dbValue,
          'p_restock': restock,
        },
      );
      final map = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      return OrderReturnSummary.fromResult(map);
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<List<OrderReturnSummary>> fetchForOrder(String orderId) async {
    try {
      final rows = await _client
          .from('order_returns')
          .select(_listSelect)
          .eq('order_id', orderId)
          .isFilter('deleted_at', null)
          .order('returned_at', ascending: false);
      return [
        for (final raw in rows as List)
          OrderReturnSummary.fromJson(Map<String, dynamic>.from(raw as Map)),
      ];
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<OrderReturnPage> fetchPage({
    String search = '',
    int page = 0,
    int pageSize = 50,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize;
      var query = _client
          .from('order_returns')
          .select(_listSelect)
          .isFilter('deleted_at', null);
      final term = search.trim().replaceAll('%', '').replaceAll(',', ' ');
      if (term.isNotEmpty) {
        query = query.or(
          'return_number.ilike.%$term%,order_number.ilike.%$term%,customer_name.ilike.%$term%',
        );
      }
      final rows = await query
          .order('returned_at', ascending: false)
          .range(from, to);
      final list = (rows as List)
          .map(
            (raw) => OrderReturnSummary.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList();
      final hasMore = list.length > pageSize;
      return OrderReturnPage(
        items: hasMore ? list.sublist(0, pageSize) : list,
        hasMore: hasMore,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> cancel(String returnId) async {
    try {
      await _client.rpc(
        'cancel_order_return',
        params: {'p_return_id': returnId},
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_message(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  static String _message(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('waiting for approval')) {
      return 'A payment on this order is still waiting for approval. '
          'Open Payments, approve or reject that payment, then record the return.';
    }
    if (lower.contains('has not cleared') || lower.contains('cheque')) {
      return 'A cheque on this order has not cleared yet. Clear it on '
          'Payments before giving money back or saving it. You can still '
          'return only what they have not paid.';
    }
    if (lower.contains('earlier day')) {
      return 'This return was recorded on an earlier day, so it cannot be '
          'cancelled. The goods, the balance, and the money stay as they are.';
    }
    if (lower.contains('already been used')) {
      return 'This return saved money for their next order, and some of it '
          'has already been used. Use or remove that wallet credit before '
          'cancelling the return.';
    }
    if (lower.contains('already been sold') ||
        lower.contains('insufficient stock')) {
      return 'These units have already been sold again, so the return cannot '
          'be cancelled. Adjust the stock, then try again.';
    }
    if (lower.contains('where the paid amount')) {
      return 'Choose where the paid amount goes.';
    }
    if (lower.contains('only delivered')) {
      return 'Only delivered items can be returned.';
    }
    if (lower.contains('can still come back') ||
        lower.contains('cannot return')) {
      return 'That quantity is more than the customer still has.';
    }
    return message;
  }
}
