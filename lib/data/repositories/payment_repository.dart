import 'dart:async';

import 'package:sello/core/error/app_failure.dart';
import 'package:sello/features/payments/application/receivable_fifo.dart';
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
    PaymentReceivedDispatcher? paymentReceived,
  }) : _client = client ?? SupabaseService.client,
       _events = events ?? BusinessEventBus(),
       _collectionAcknowledgements = collectionAcknowledgements,
       _paymentReceived = paymentReceived;

  final SupabaseClient _client;
  final BusinessEventBus _events;
  final CollectionAcknowledgementDispatcher? _collectionAcknowledgements;
  final PaymentReceivedDispatcher? _paymentReceived;

  final _changes = StreamController<void>.broadcast();

  /// Fires after this device writes to the ledger (receive, approve, reject,
  /// refund, correct) so dependent summaries can refresh.
  Stream<void> get changes => _changes.stream;

  void _notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

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
    corrects_payment_id,
    corrected_by_payment_id,
    correction_reason,
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
      receivable_adjustment_id,
      amount,
      orders (
        id,
        order_number
      ),
      customer_receivable_adjustments (
        id,
        adjustment_number,
        reference_number
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
    corrects_payment_id,
    corrected_by_payment_id,
    correction_reason,
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
      receivable_adjustment_id,
      amount,
      orders (
        id,
        order_number
      ),
      customer_receivable_adjustments (
        id,
        adjustment_number,
        reference_number
      )
    )
  ''';

  static const _correctionColumns = [
    'corrects_payment_id',
    'corrected_by_payment_id',
    'correction_reason',
  ];

  /// The select without the safe-corrections columns (migration 093), so
  /// Payments keeps loading on a database that has not been upgraded yet.
  static String _withoutCorrectionColumns(String select) {
    var out = select;
    for (final column in _correctionColumns) {
      out = out.replaceAll(RegExp('\\s*$column,'), '');
    }
    return out;
  }

  static bool _isMissingCorrectionColumn(PostgrestException error) {
    final text = '${error.message} ${error.details ?? ''}'.toLowerCase();
    final missing =
        error.code == '42703' ||
        text.contains('does not exist') ||
        text.contains('could not find');
    return missing && _correctionColumns.any(text.contains);
  }

  Future<PaymentPageResult> fetchPayments({
    String search = '',
    PaymentRecordStatus? status,
    PaymentMethod? method,
    String? employeeId,
    List<PaymentRecordStatus>? statuses,
    DateTime? receivedFrom,
    DateTime? receivedBefore,
    int page = 0,
    int pageSize = 20,
  }) async {
    Future<PaymentPageResult> run(String select) => _fetchPaymentsPage(
      select: select,
      search: search,
      status: status,
      method: method,
      employeeId: employeeId,
      statuses: statuses,
      receivedFrom: receivedFrom,
      receivedBefore: receivedBefore,
      page: page,
      pageSize: pageSize,
    );
    try {
      return await run(_listSelect);
    } on ProvisioningFailure catch (failure) {
      // `_fetchPaymentsPage` wraps Postgrest errors; retry for old databases.
      final text = failure.message.toLowerCase();
      final missing =
          (text.contains('does not exist') ||
              text.contains('could not find')) &&
          _correctionColumns.any(text.contains);
      if (!missing) rethrow;
      return run(_withoutCorrectionColumns(_listSelect));
    }
  }

  Future<PaymentPageResult> _fetchPaymentsPage({
    required String select,
    required String search,
    PaymentRecordStatus? status,
    PaymentMethod? method,
    String? employeeId,
    List<PaymentRecordStatus>? statuses,
    DateTime? receivedFrom,
    DateTime? receivedBefore,
    required int page,
    required int pageSize,
  }) async {
    try {
      var query = _client
          .from('payments')
          .select(select)
          .isFilter('deleted_at', null);

      if (status != null) {
        query = query.eq('status', status.dbValue);
      } else if (statuses != null && statuses.isNotEmpty) {
        query = query.inFilter('status', [for (final s in statuses) s.dbValue]);
      }
      if (method != null) {
        query = query.eq('method', method.dbValue);
      }
      if (employeeId != null && employeeId.isNotEmpty) {
        query = query.eq('employee_id', employeeId);
      }
      if (receivedFrom != null) {
        query = query.gte(
          'received_at',
          receivedFrom.toUtc().toIso8601String(),
        );
      }
      if (receivedBefore != null) {
        query = query.lt(
          'received_at',
          receivedBefore.toUtc().toIso8601String(),
        );
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

  /// Every collected (completed) and awaiting-approval (pending) payment in
  /// the date range, newest first. Used by the Payments export and the Sales
  /// Rep "My collections" list. Rejected, refunded and cancelled rows (which
  /// include the originals replaced by a correction) are left out.
  Future<List<PaymentSummary>> fetchCollections({
    String? employeeId,
    required DateTime from,
    required DateTime before,
    PaymentMethod? method,
    bool includeRejected = false,
    int maxRows = 5000,
  }) async {
    const chunk = 500;
    final rows = <PaymentSummary>[];
    var page = 0;
    while (rows.length < maxRows) {
      final result = await fetchPayments(
        employeeId: employeeId,
        method: method,
        statuses: [
          PaymentRecordStatus.completed,
          PaymentRecordStatus.pending,
          if (includeRejected) PaymentRecordStatus.rejected,
        ],
        receivedFrom: from,
        receivedBefore: before,
        page: page,
        pageSize: chunk,
      );
      rows.addAll(result.items);
      if (!result.hasMore) break;
      page += 1;
    }
    return rows;
  }

  Future<PaymentDashboardStats> fetchDashboardStats() async {
    try {
      // Business day starts at local midnight (e.g. Sri Lanka, UTC+5:30).
      final now = DateTime.now();
      final startIso = DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc().toIso8601String();

      final totals = await Future.wait([
        _sumPaymentsCollectedSince(startIso),
        _sumActiveCustomers('current_balance'),
        _sumActiveCustomers('wallet_balance'),
        _sumPendingCredit(),
      ]);

      return PaymentDashboardStats(
        collectedToday: totals[0],
        outstandingReceivables: totals[1],
        walletIssued: totals[2],
        pendingCredit: totals[3],
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<num> _sumPaymentsCollectedSince(String startIso) async {
    try {
      final rows = await _client
          .from('payments')
          .select('total:amount.sum()')
          .isFilter('deleted_at', null)
          .eq('status', PaymentRecordStatus.completed.dbValue)
          .gte('received_at', startIso);
      final summed = _readAggregate(rows, 'total');
      if (summed != null) return summed;
    } on PostgrestException {
      // Database aggregates unavailable — fall through to a row scan.
    }

    final todayRows = await _client
        .from('payments')
        .select('amount')
        .isFilter('deleted_at', null)
        .eq('status', PaymentRecordStatus.completed.dbValue)
        .gte('received_at', startIso);
    num collected = 0;
    for (final row in todayRows as List) {
      collected += _asNum((row as Map)['amount']);
    }
    return collected;
  }

  Future<num> _sumActiveCustomers(String column) async {
    try {
      final rows = await _client
          .from('customers')
          .select('total:$column.sum()')
          .isFilter('deleted_at', null)
          .eq('is_active', true);
      final summed = _readAggregate(rows, 'total');
      if (summed != null) return summed;
    } on PostgrestException {
      // Database aggregates unavailable — fall through to a row scan.
    }

    final customerRows = await _client
        .from('customers')
        .select(column)
        .isFilter('deleted_at', null)
        .eq('is_active', true);
    num total = 0;
    for (final row in customerRows as List) {
      total += _asNum((row as Map)[column]);
    }
    return total;
  }

  Future<num> _sumPendingCredit() async {
    try {
      final rows = await _client
          .from('customers')
          .select('total:current_balance.sum()')
          .isFilter('deleted_at', null)
          .eq('is_active', true)
          .eq('credit_allowed', true)
          .gt('current_balance', 0);
      final summed = _readAggregate(rows, 'total');
      if (summed != null) return summed;
    } on PostgrestException {
      // Database aggregates unavailable — fall through to a row scan.
    }

    final customerRows = await _client
        .from('customers')
        .select('current_balance, credit_allowed')
        .isFilter('deleted_at', null)
        .eq('is_active', true);
    num pendingCredit = 0;
    for (final row in customerRows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final balance = _asNum(map['current_balance']);
      if (map['credit_allowed'] == true && balance > 0) {
        pendingCredit += balance;
      }
    }
    return pendingCredit;
  }

  /// Aggregate select returns `[{alias: value}]`. Null means the response was
  /// not an aggregate, so the caller should scan rows instead.
  num? _readAggregate(dynamic response, String alias) {
    if (response is! List || response.isEmpty) return 0;
    final row = response.first;
    if (row is! Map || !row.containsKey(alias)) return null;
    return _asNum(row[alias]);
  }

  Future<PaymentDetail?> fetchById(String paymentId) async {
    try {
      Future<Map<String, dynamic>?> load(String select) => _client
          .from('payments')
          .select(select)
          .eq('id', paymentId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      Map<String, dynamic>? row;
      try {
        row = await load(_detailSelect);
      } on PostgrestException catch (error) {
        if (!_isMissingCorrectionColumn(error)) rethrow;
        row = await load(_withoutCorrectionColumns(_detailSelect));
      }
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
      final base = await Future.wait([
        _client
            .from('orders')
            .select(
              'id, order_number, total, ordered_at, payment_status, status',
            )
            .eq('customer_id', customerId)
            .inFilter('status', ['placed', 'partially_delivered', 'completed'])
            .isFilter('deleted_at', null)
            .inFilter('payment_status', ['unpaid', 'partial'])
            .order('ordered_at'),
        _client
            .from('customer_receivable_adjustments')
            .select(
              'id, adjustment_number, amount, recognized_at, reference_number',
            )
            .eq('customer_id', customerId)
            .eq('kind', 'opening_balance')
            .order('recognized_at'),
      ]);
      final rows = base[0] as List;
      final adjustmentRows = base[1] as List;

      final paidTotals = await Future.wait([
        _allocatedTotals('order_id', [
          for (final row in rows) (row as Map)['id'] as String,
        ]),
        _allocatedTotals('receivable_adjustment_id', [
          for (final row in adjustmentRows) (row as Map)['id'] as String,
        ]),
      ]);
      final paidByOrder = paidTotals[0];
      final paidByAdjustment = paidTotals[1];

      final orders = <ReceivableOrder>[];
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final orderId = map['id'] as String;
        final paid = paidByOrder[orderId] ?? 0;
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

      for (final row in adjustmentRows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'] as String;
        final paid = paidByAdjustment[id] ?? 0;
        final total = _asNum(map['amount']);
        if (paid + 0.001 >= total) continue;
        orders.add(
          ReceivableOrder(
            id: id,
            orderNumber: map['adjustment_number'] as String? ?? '',
            total: total,
            amountPaid: paid,
            orderedAt:
                DateTime.tryParse(map['recognized_at'] as String? ?? '') ??
                DateTime.now().toUtc(),
            kind: ReceivableKind.openingBalance,
            referenceNumber: () {
              final raw = map['reference_number'] as String?;
              final trimmed = raw?.trim();
              if (trimmed == null || trimmed.isEmpty) return null;
              return trimmed;
            }(),
          ),
        );
      }

      return sortReceivablesFifo(orders);
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
          acknowledgement = await _collectionAcknowledgements?.dispatch(
            paymentId,
          );
        } catch (_) {
          // Outbound share intents must not block the collection write.
        }
      } else if (status == PaymentRecordStatus.completed) {
        // SMS runs in the background so the save returns immediately.
        unawaited(_dispatchCompletedNotices(paymentId));
      }

      _notifyChanged();
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
      unawaited(_dispatchPaymentReceived(paymentId));
      _notifyChanged();
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
      _notifyChanged();
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> _dispatchCompletedNotices(String paymentId) async {
    try {
      // Tell the Owner / Manager (SMS only) what was just collected.
      await _collectionAcknowledgements?.dispatch(
        paymentId,
        pendingReview: false,
      );
    } catch (_) {
      // Team SMS must not block the collection write.
    }
    await _dispatchPaymentReceived(paymentId);
  }

  Future<void> _dispatchPaymentReceived(String paymentId) async {
    try {
      await _paymentReceived?.dispatch(paymentId);
    } catch (_) {
      // Applied SMS must not block the collection write.
    }
  }

  Future<int> countPendingReview() async {
    try {
      return await _client
          .from('payments')
          .count()
          .isFilter('deleted_at', null)
          .eq('status', PaymentRecordStatus.pending.dbValue);
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
      _notifyChanged();
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<OrderCollectionBalance> fetchOrderCollections(String orderId) async {
    try {
      final rows = await _client
          .from('payment_allocations')
          .select(
            'amount, payments!inner(id, payment_number, method, status, received_at, deleted_at)',
          )
          .eq('order_id', orderId);

      final entries = <OrderCollectionEntry>[];
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final rawPayment = map['payments'];
        final payment = rawPayment is List && rawPayment.isNotEmpty
            ? rawPayment.first
            : rawPayment;
        if (payment is! Map) continue;
        final pay = Map<String, dynamic>.from(payment);
        if (pay['deleted_at'] != null) continue;
        entries.add(
          OrderCollectionEntry(
            paymentId: pay['id'] as String,
            paymentNumber: pay['payment_number'] as String? ?? '',
            amount: _asNum(map['amount']),
            method:
                PaymentMethod.fromDb(pay['method'] as String?) ??
                PaymentMethod.cash,
            status: PaymentRecordStatus.fromDb(pay['status'] as String?),
            receivedAt:
                DateTime.tryParse(pay['received_at'] as String? ?? '') ??
                DateTime.now().toUtc(),
          ),
        );
      }
      entries.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      final paid = entries
          .where((entry) => entry.countsTowardPaid)
          .fold<num>(0, (sum, entry) => sum + entry.amount);
      final pending = entries
          .where((entry) => entry.status.isPendingReview)
          .fold<num>(0, (sum, entry) => sum + entry.amount);
      return OrderCollectionBalance(
        entries: entries,
        amountPaid: paid,
        amountPending: pending,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<Map<String, List<PaymentAllocation>>> fetchAllocationsForPayments(
    List<String> paymentIds,
  ) async {
    final ids = paymentIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return const {};
    try {
      final rows = await _client
          .from('payment_allocations')
          .select('id, payment_id, amount, order_id, receivable_adjustment_id')
          .inFilter('payment_id', ids);
      final mapped = <String, List<PaymentAllocation>>{};
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final paymentId = map['payment_id'] as String?;
        if (paymentId == null || paymentId.isEmpty) continue;
        mapped
            .putIfAbsent(paymentId, () => <PaymentAllocation>[])
            .add(PaymentAllocation.fromJson(map));
      }
      return mapped;
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Completed allocation totals keyed by [column] value, in one request
  /// (chunked so very long id lists stay within URL limits).
  Future<Map<String, num>> _allocatedTotals(
    String column,
    List<String> ids,
  ) async {
    final totals = <String, num>{};
    if (ids.isEmpty) return totals;
    const chunk = 150;
    final batches = [
      for (var i = 0; i < ids.length; i += chunk)
        ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk),
    ];
    final results = await Future.wait([
      for (final batch in batches)
        _client
            .from('payment_allocations')
            .select('$column, amount, payments!inner(status, deleted_at)')
            .inFilter(column, batch)
            .eq('payments.status', 'completed')
            .isFilter('payments.deleted_at', null),
    ]);
    for (final rows in results) {
      for (final row in rows as List) {
        final map = row as Map;
        final key = map[column] as String?;
        if (key == null) continue;
        totals[key] = (totals[key] ?? 0) + _asNum(map['amount']);
      }
    }
    return totals;
  }

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  Future<String> correctPayment({
    required String paymentId,
    required num amount,
    required PaymentMethod method,
    List<PaymentAllocationInput> allocations = const [],
    String? reference,
    String? notes,
    required String reason,
    String? customerId,
  }) async {
    if (!method.isSettlementMethod) {
      throw const ValidationFailure('Choose a valid collection method.');
    }
    if (amount <= 0) {
      throw const ValidationFailure(
        'Enter a payment amount greater than zero.',
      );
    }
    if (reason.trim().isEmpty) {
      throw const ValidationFailure(
        'Enter a short reason for this payment correction.',
      );
    }

    try {
      final result = await _client.rpc(
        'correct_completed_payment',
        params: {
          'p_payment_id': paymentId,
          'p_amount': amount,
          'p_method': method.dbValue,
          'p_allocations': [for (final alloc in allocations) alloc.toJson()],
          'p_reference': reference,
          'p_notes': notes,
          'p_reason': reason.trim(),
          'p_customer_id': customerId,
        },
      );
      _notifyChanged();
      return result is String ? result : result.toString();
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapPaymentError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
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
    if (lower.contains('only owner or manager')) {
      return 'Only Owner or Manager can correct a payment.';
    }
    if (lower.contains('already been corrected')) {
      return 'This payment has already been corrected.';
    }
    if (lower.contains('short reason')) {
      return 'Enter a short reason for this payment correction.';
    }
    return message;
  }
}
