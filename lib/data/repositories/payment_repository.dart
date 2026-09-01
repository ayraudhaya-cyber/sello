import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentPageResult {
  const PaymentPageResult({required this.items, required this.hasMore});

  final List<PaymentSummary> items;
  final bool hasMore;
}

class PaymentRepository {
  PaymentRepository({
    SupabaseClient? client,
    BusinessEventBus? events,
    CollectionAcknowledgementDispatcher? collectionAcknowledgements,
  })  : _client = client ?? SupabaseService.client,
        _events = events ?? BusinessEventBus(),
        _collectionAcknowledgements = collectionAcknowledgements;

  final SupabaseClient _client;
  final BusinessEventBus _events;
  final CollectionAcknowledgementDispatcher? _collectionAcknowledgements;

  static const _listSelect = '''
    id,
    company_id,
    customer_id,
    employee_id,
    payment_number,
    amount,
    method,
    status,
    reference,
    notes,
    received_at,
    refunded_at,
    cancelled_at,
    reviewed_by,
    reviewed_at,
    rejection_reason,
    customers!customer_id (
      id,
      name,
      phone
    ),
    employees!employee_id (
      id,
      full_name
    ),
    reviewed_by_employee:employees!reviewed_by (
      id,
      full_name
    ),
    payment_allocations (
      id,
      order_id,
      amount,
      orders (
        id,
        order_number
      )
    )
  ''';

  static const _detailSelect = '''
    id,
    company_id,
    customer_id,
    employee_id,
    payment_number,
    amount,
    method,
    status,
    reference,
    notes,
    received_at,
    refunded_at,
    cancelled_at,
    reviewed_by,
    reviewed_at,
    rejection_reason,
    customers!customer_id (
      id,
      name,
      phone,
      current_balance,
      wallet_balance,
      credit_allowed,
      credit_limit
    ),
    employees!employee_id (
      id,
      full_name
    ),
    reviewed_by_employee:employees!reviewed_by (
      id,
      full_name
    ),
    payment_allocations (
      id,
      order_id,
      amount,
      orders (
        id,
        order_number
      )
    )
  ''';

  Future<PaymentPageResult> fetchPayments({
    String search = '',
    PaymentRecordStatus? status,
    PaymentMethod? method,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('payments')
          .select(_listSelect)
          .isFilter('deleted_at', null);

      if (status != null) {
        query = query.eq('status', status.dbValue);
      }
      if (method != null) {
        query = query.eq('method', method.dbValue);
      }

      final needle = search.trim();
      if (needle.isNotEmpty) {
        final customerRows = await _client
            .from('customers')
            .select('id')
            .isFilter('deleted_at', null)
            .or(
              'name.ilike.%$needle%,phone.ilike.%$needle%,code.ilike.%$needle%',
            )
            .limit(50);
        final customerIds = (customerRows as List)
            .map((row) => row['id'] as String)
            .toList();

        final orderRows = await _client
            .from('orders')
            .select('id')
            .isFilter('deleted_at', null)
            .ilike('order_number', '%$needle%')
            .limit(50);
        final orderIds = (orderRows as List)
            .map((row) => row['id'] as String)
            .toList();

        List<String> paymentIdsFromOrders = const [];
        if (orderIds.isNotEmpty) {
          final allocRows = await _client
              .from('payment_allocations')
              .select('payment_id')
              .inFilter('order_id', orderIds)
              .limit(100);
          paymentIdsFromOrders = (allocRows as List)
              .map((row) => row['payment_id'] as String)
              .toSet()
              .toList();
        }

        final parts = <String>[
          'payment_number.ilike.%$needle%',
          'reference.ilike.%$needle%',
        ];
        if (customerIds.isNotEmpty) {
          parts.add('customer_id.in.(${customerIds.join(',')})');
        }
        if (paymentIdsFromOrders.isNotEmpty) {
          parts.add('id.in.(${paymentIdsFromOrders.join(',')})');
        }
        query = query.or(parts.join(','));
      }

      final response = await query
          .order('received_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final list = response as List;
      return PaymentPageResult(
        items: list
            .map(
              (row) => PaymentSummary.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList(),
        hasMore: list.length >= pageSize,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<PaymentDashboardStats> fetchDashboardStats() async {
    try {
      final now = DateTime.now().toUtc();
      final startOfDay = DateTime.utc(now.year, now.month, now.day);

      final todayRows = await _client
          .from('payments')
          .select('amount')
          .isFilter('deleted_at', null)
          .eq('status', PaymentRecordStatus.completed.dbValue)
          .gte('received_at', startOfDay.toIso8601String());

      num collectedToday = 0;
      for (final row in todayRows as List) {
        collectedToday += _asNum((row as Map)['amount']);
      }

      final customerRows = await _client
          .from('customers')
          .select(
            'current_balance, wallet_balance, credit_allowed, credit_limit',
          )
          .isFilter('deleted_at', null)
          .eq('is_active', true);

      num outstanding = 0;
      num wallet = 0;
      num pendingCredit = 0;
      for (final row in customerRows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final balance = _asNum(map['current_balance']);
        outstanding += balance;
        wallet += _asNum(map['wallet_balance']);
        if (map['credit_allowed'] == true && balance > 0) {
          pendingCredit += balance;
        }
      }

      return PaymentDashboardStats(
        collectedToday: collectedToday,
        outstandingReceivables: outstanding,
        walletIssued: wallet,
        pendingCredit: pendingCredit,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<PaymentDetail?> fetchById(String paymentId) async {
    try {
      final row = await _client
          .from('payments')
          .select(_detailSelect)
          .eq('id', paymentId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;

      final summary = PaymentSummary.fromJson(Map<String, dynamic>.from(row));
      final raw = row['payment_allocations'];
      final allocations = <PaymentAllocation>[];
      if (raw is List) {
        for (final item in raw) {
          allocations.add(
            PaymentAllocation.fromJson(Map<String, dynamic>.from(item as Map)),
          );
        }
      }

      final customer = row['customers'];
      num? outstanding;
      num? wallet;
      bool? creditAllowed;
      num? creditLimit;
      if (customer is Map) {
        outstanding = _asNum(customer['current_balance']);
        wallet = _asNum(customer['wallet_balance']);
        creditAllowed = customer['credit_allowed'] as bool?;
        creditLimit = _asNum(customer['credit_limit']);
      }

      return PaymentDetail(
        summary: summary,
        allocations: allocations,
        customerOutstanding: outstanding,
        customerWallet: wallet,
        customerCreditAllowed: creditAllowed,
        customerCreditLimit: creditLimit,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<List<ReceivableOrder>> fetchReceivableOrders(String customerId) async {
    try {
      final rows = await _client
          .from('orders')
          .select('id, order_number, total, ordered_at, payment_status')
          .eq('customer_id', customerId)
          .eq('status', 'completed')
          .isFilter('deleted_at', null)
          .inFilter('payment_status', ['unpaid', 'partial'])
          .order('ordered_at');

      final orders = <ReceivableOrder>[];
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final orderId = map['id'] as String;
        final paid = await _allocatedForOrder(orderId);
        final total = _asNum(map['total']);
        if (paid + 0.001 >= total) continue;
        orders.add(
          ReceivableOrder(
            id: orderId,
            orderNumber: map['order_number'] as String? ?? '',
            total: total,
            amountPaid: paid,
            orderedAt:
                DateTime.tryParse(map['ordered_at'] as String? ?? '') ??
                DateTime.now().toUtc(),
          ),
        );
      }
      return orders;
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<ReceivePaymentResult> receivePayment(ReceivePaymentInput input) async {
    if (!input.method.isSettlementMethod) {
      throw const ValidationFailure('Choose a valid collection method.');
    }
    if (input.amount <= 0) {
      throw const ValidationFailure(
        'Enter a payment amount greater than zero.',
      );
    }

    try {
      final result = await _client.rpc(
        'receive_payment',
        params: {
          'p_customer_id': input.customerId,
          'p_amount': input.amount,
          'p_method': input.method.dbValue,
          'p_allocations': [
            for (final alloc in input.allocations) alloc.toJson(),
          ],
          'p_reference': input.reference,
          'p_notes': input.notes,
          'p_visit_id': input.visitId,
        },
      );
      final paymentId = result is String ? result : result.toString();
      final detail = await fetchById(paymentId);
      final status = detail?.summary.status ?? PaymentRecordStatus.completed;
      final customerName = detail?.summary.customerName ?? 'a customer';
      final companyId = detail?.summary.companyId;
      final salesRepName = detail?.summary.employeeName;
      final amountLabel = detail == null
          ? input.amount.toString()
          : detail.summary.amount.toString();

      try {
        if (companyId != null) {
          if (status.isPendingReview) {
            await _events.publish(
              companyId: companyId,
              event: BusinessEvents.collectionPendingReview(
                paymentId: paymentId,
                customerName: customerName,
                amountLabel: amountLabel,
                salesRepName: salesRepName,
              ),
              actorEmployeeId: detail?.summary.employeeId,
              actorName: salesRepName,
            );
          } else {
            await _events.publish(
              companyId: companyId,
              event: BusinessEvents.paymentReceived(
                paymentId: paymentId,
                customerName: customerName,
              ),
            );
          }
        }
      } catch (_) {
        // Never block payment on notification failure.
      }

      OrderConfirmationOutcome? acknowledgement;
      if (status.isPendingReview) {
        try {
          acknowledgement =
              await _collectionAcknowledgements?.dispatch(paymentId);
        } catch (_) {
          // Outbound share intents must not block the collection write.
        }
      }

      return ReceivePaymentResult(
        paymentId: paymentId,
        status: status,
        acknowledgement: acknowledgement,
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> approveCollection(String paymentId) async {
    try {
      await _client.rpc(
        'approve_collection',
        params: {'p_payment_id': paymentId},
      );
      try {
        final detail = await fetchById(paymentId);
        final companyId = detail?.summary.companyId;
        final customerName = detail?.summary.customerName ?? 'a customer';
        if (companyId != null) {
          await _events.publish(
            companyId: companyId,
            event: BusinessEvents.collectionApproved(
              paymentId: paymentId,
              customerName: customerName,
            ),
            actorEmployeeId: detail?.summary.reviewedBy,
            actorName: detail?.summary.reviewerName,
          );
        }
      } catch (_) {}
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> rejectCollection(String paymentId, {String? reason}) async {
    try {
      await _client.rpc(
        'reject_collection',
        params: {'p_payment_id': paymentId, 'p_reason': reason},
      );
      try {
        final detail = await fetchById(paymentId);
        final companyId = detail?.summary.companyId;
        final customerName = detail?.summary.customerName ?? 'a customer';
        if (companyId != null) {
          await _events.publish(
            companyId: companyId,
            event: BusinessEvents.collectionRejected(
              paymentId: paymentId,
              customerName: customerName,
            ),
            actorEmployeeId: detail?.summary.reviewedBy,
            actorName: detail?.summary.reviewerName,
          );
        }
      } catch (_) {}
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<int> countPendingReview() async {
    try {
      final rows = await _client
          .from('payments')
          .select('id')
          .isFilter('deleted_at', null)
          .eq('status', PaymentRecordStatus.pending.dbValue);
      return (rows as List).length;
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Architecture seam for refunds — marks status only; no balance reverse yet.
  Future<void> markRefunded(String paymentId) async {
    try {
      await _client.rpc(
        'mark_payment_refunded',
        params: {'p_payment_id': paymentId},
      );
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<num> _allocatedForOrder(String orderId) async {
    final rows = await _client
        .from('payment_allocations')
        .select('amount, payments!inner(status, deleted_at)')
        .eq('order_id', orderId)
        .eq('payments.status', 'completed')
        .isFilter('payments.deleted_at', null);

    num total = 0;
    for (final row in rows as List) {
      total += _asNum((row as Map)['amount']);
    }
    return total;
  }

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static String _mapPaymentError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('wallet')) {
      return 'Not enough wallet balance for this payment.';
    }
    if (lower.contains('allocation exceeds')) {
      return message;
    }
    if (lower.contains('amount must')) {
      return message;
    }
    return message;
  }
}
