import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/order_timeline.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderPageResult {
  const OrderPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<OrderSummary> items;
  final bool hasMore;
}

class OrderSaveResult {
  const OrderSaveResult({
    required this.orderId,
    this.confirmation,
  });

  final String orderId;
  final OrderConfirmationOutcome? confirmation;
}

class OrderRepository {
  OrderRepository({
    SupabaseClient? client,
    BusinessEventBus? events,
    this.confirmations,
  })  : _client = client ?? SupabaseService.client,
        _events = events ?? BusinessEventBus();

  final SupabaseClient _client;
  final BusinessEventBus _events;
  final OrderConfirmationDispatcher? confirmations;

  static const _listSelect = '''
    id,
    company_id,
    branch_id,
    customer_id,
    employee_id,
    order_number,
    status,
    payment_status,
    payment_method,
    subtotal,
    discount_amount,
    tax_amount,
    total,
    notes,
    ordered_at,
    completed_at,
    cancelled_at,
    created_at,
    updated_at,
    customers!customer_id (
      id,
      name,
      phone
    ),
    employees!employee_id (
      id,
      full_name
    )
  ''';

  static const _detailSelect = '''
    id,
    company_id,
    branch_id,
    customer_id,
    employee_id,
    order_number,
    status,
    payment_status,
    payment_method,
    subtotal,
    discount_amount,
    tax_amount,
    total,
    notes,
    ordered_at,
    completed_at,
    cancelled_at,
    created_at,
    updated_at,
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
    order_items (
      id,
      product_id,
      quantity,
      delivered_quantity,
      cancelled_quantity,
      unit_price,
      discount,
      discount_type,
      line_total,
      products (
        id,
        name,
        sku,
        attributes,
        brand,
        unit_label
      )
    )
  ''';

  Future<OrderPageResult> fetchOrders({
    String search = '',
    OrderStatus? status,
    List<OrderStatus>? statuses,
    PaymentStatus? paymentStatus,
    List<PaymentStatus>? paymentStatuses,
    String? customerId,
    String? employeeId,
    DateTime? orderedFrom,
    DateTime? orderedTo,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('orders')
          .select(_listSelect)
          .isFilter('deleted_at', null);

      if (statuses != null && statuses.isNotEmpty) {
        query = query.inFilter(
          'status',
          statuses.map((item) => item.dbValue).toList(),
        );
      } else if (status != null) {
        query = query.eq('status', status.dbValue);
      }
      if (paymentStatuses != null && paymentStatuses.isNotEmpty) {
        query = query.inFilter(
          'payment_status',
          paymentStatuses.map((item) => item.dbValue).toList(),
        );
      } else if (paymentStatus != null) {
        query = query.eq('payment_status', paymentStatus.dbValue);
      }
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      if (employeeId != null && employeeId.isNotEmpty) {
        query = query.eq('employee_id', employeeId);
      }
      if (orderedFrom != null) {
        query = query.gte('ordered_at', orderedFrom.toUtc().toIso8601String());
      }
      if (orderedTo != null) {
        query = query.lte('ordered_at', orderedTo.toUtc().toIso8601String());
      }

      final needle = search.trim();
      List<String>? customerIds;
      List<String>? employeeIds;
      if (needle.isNotEmpty) {
        final customerRows = await _client
            .from('customers')
            .select('id')
            .isFilter('deleted_at', null)
            .or(
              'name.ilike.%$needle%,phone.ilike.%$needle%,code.ilike.%$needle%',
            )
            .limit(50);
        customerIds = (customerRows as List)
            .map((row) => row['id'] as String)
            .toList();

        final employeeRows = await _client
            .from('employees')
            .select('id')
            .isFilter('deleted_at', null)
            .ilike('full_name', '%$needle%')
            .limit(50);
        employeeIds = (employeeRows as List)
            .map((row) => row['id'] as String)
            .toList();

        final productRows = await _client
            .from('products')
            .select('id')
            .isFilter('deleted_at', null)
            .or('name.ilike.%$needle%,sku.ilike.%$needle%')
            .limit(50);
        final productIds = (productRows as List)
            .map((row) => row['id'] as String)
            .toList();
        List<String> orderIdsFromProducts = const [];
        if (productIds.isNotEmpty) {
          final itemRows = await _client
              .from('order_items')
              .select('order_id')
              .inFilter('product_id', productIds)
              .limit(100);
          orderIdsFromProducts = (itemRows as List)
              .map((row) => row['order_id'] as String)
              .toSet()
              .toList();
        }

        final parts = <String>['order_number.ilike.%$needle%'];
        if (customerIds.isNotEmpty) {
          parts.add('customer_id.in.(${customerIds.join(',')})');
        }
        if (employeeIds.isNotEmpty) {
          parts.add('employee_id.in.(${employeeIds.join(',')})');
        }
        if (orderIdsFromProducts.isNotEmpty) {
          parts.add('id.in.(${orderIdsFromProducts.join(',')})');
        }
        query = query.or(parts.join(','));
      }

      final response = await query
          .order('ordered_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final list = response as List;
      final items = list
          .map((row) => OrderSummary.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      return OrderPageResult(
        items: items,
        hasMore: list.length >= pageSize,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<OrderCounts> fetchCounts() async {
    try {
      final rows = await _client
          .from('orders')
          .select('status')
          .isFilter('deleted_at', null);

      var draft = 0;
      var completed = 0;
      var cancelled = 0;
      final list = rows as List;
      for (final row in list) {
        final status = OrderStatus.fromDb(
          (row as Map)['status'] as String?,
        );
        switch (status) {
          case OrderStatus.draft:
          case OrderStatus.placed:
          case OrderStatus.partiallyDelivered:
            draft++;
          case OrderStatus.completed:
            completed++;
          case OrderStatus.cancelled:
            cancelled++;
        }
      }
      return OrderCounts(
        total: list.length,
        draft: draft,
        completed: completed,
        cancelled: cancelled,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Open fulfillment demand + orders currently blocked by available stock.
  ///
  /// "Waiting for stock" uses **current** available qty vs remaining demand —
  /// not a historical snapshot of stock at order time.
  Future<FulfillmentAttentionCounts> fetchFulfillmentAttention() async {
    try {
      final orderRows = await _client
          .from('orders')
          .select('id, branch_id, status')
          .inFilter('status', [
            OrderStatus.placed.dbValue,
            OrderStatus.partiallyDelivered.dbValue,
          ])
          .isFilter('deleted_at', null);

      var placed = 0;
      var partiallyDelivered = 0;
      final orderMeta = <String, ({String branchId, OrderStatus status})>{};

      for (final raw in orderRows as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        final id = map['id'] as String?;
        final branchId = map['branch_id'] as String?;
        if (id == null || branchId == null) continue;
        final status = OrderStatus.fromDb(map['status'] as String?);
        orderMeta[id] = (branchId: branchId, status: status);
        switch (status) {
          case OrderStatus.placed:
            placed++;
          case OrderStatus.partiallyDelivered:
            partiallyDelivered++;
          case OrderStatus.draft:
          case OrderStatus.completed:
          case OrderStatus.cancelled:
            break;
        }
      }

      if (orderMeta.isEmpty) {
        return const FulfillmentAttentionCounts();
      }

      final itemRows = await _client
          .from('order_items')
          .select(
            'order_id, product_id, quantity, delivered_quantity, cancelled_quantity',
          )
          .inFilter('order_id', orderMeta.keys.toList());

      final productIds = <String>{};
      final remainingByOrder =
          <String, List<({String productId, num remaining})>>{};

      for (final raw in itemRows as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        final orderId = map['order_id'] as String?;
        final productId = map['product_id'] as String?;
        if (orderId == null || productId == null) continue;
        if (!orderMeta.containsKey(orderId)) continue;

        final ordered = _asNum(map['quantity']);
        final delivered = _asNum(map['delivered_quantity']);
        final cancelled = _asNum(map['cancelled_quantity']);
        final remaining = ordered - delivered - cancelled;
        if (remaining <= 0) continue;

        productIds.add(productId);
        remainingByOrder
            .putIfAbsent(orderId, () => [])
            .add((productId: productId, remaining: remaining));
      }

      if (productIds.isEmpty) {
        return FulfillmentAttentionCounts(
          placed: placed,
          partiallyDelivered: partiallyDelivered,
        );
      }

      final invRows = await _client
          .from('inventory')
          .select('branch_id, product_id, quantity, reserved_quantity')
          .inFilter('product_id', productIds.toList());

      final available = <String, num>{};
      for (final raw in invRows as List) {
        final map = Map<String, dynamic>.from(raw as Map);
        final branchId = map['branch_id'] as String?;
        final productId = map['product_id'] as String?;
        if (branchId == null || productId == null) continue;
        final qty = _asNum(map['quantity']);
        final reserved = _asNum(map['reserved_quantity']);
        final avail = qty - reserved;
        available['$branchId|$productId'] = avail < 0 ? 0 : avail;
      }

      var waitingPlaced = 0;
      var waitingPartial = 0;
      for (final entry in orderMeta.entries) {
        final lines = remainingByOrder[entry.key];
        if (lines == null || lines.isEmpty) continue;
        final branchId = entry.value.branchId;
        var blocked = false;
        for (final line in lines) {
          final avail = available['$branchId|${line.productId}'] ?? 0;
          if (line.remaining > avail) {
            blocked = true;
            break;
          }
        }
        if (!blocked) continue;
        switch (entry.value.status) {
          case OrderStatus.placed:
            waitingPlaced++;
          case OrderStatus.partiallyDelivered:
            waitingPartial++;
          case OrderStatus.draft:
          case OrderStatus.completed:
          case OrderStatus.cancelled:
            break;
        }
      }

      return FulfillmentAttentionCounts(
        placed: placed,
        partiallyDelivered: partiallyDelivered,
        waitingPlaced: waitingPlaced,
        waitingPartial: waitingPartial,
      );
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('reserved_quantity')) {
        return _fetchFulfillmentAttentionWithoutReserved();
      }
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<FulfillmentAttentionCounts>
      _fetchFulfillmentAttentionWithoutReserved() async {
    final orderRows = await _client
        .from('orders')
        .select('id, branch_id, status')
        .inFilter('status', [
          OrderStatus.placed.dbValue,
          OrderStatus.partiallyDelivered.dbValue,
        ])
        .isFilter('deleted_at', null);

    var placed = 0;
    var partiallyDelivered = 0;
    final orderMeta = <String, ({String branchId, OrderStatus status})>{};

    for (final raw in orderRows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = map['id'] as String?;
      final branchId = map['branch_id'] as String?;
      if (id == null || branchId == null) continue;
      final status = OrderStatus.fromDb(map['status'] as String?);
      orderMeta[id] = (branchId: branchId, status: status);
      switch (status) {
        case OrderStatus.placed:
          placed++;
        case OrderStatus.partiallyDelivered:
          partiallyDelivered++;
        case OrderStatus.draft:
        case OrderStatus.completed:
        case OrderStatus.cancelled:
          break;
      }
    }

    if (orderMeta.isEmpty) {
      return const FulfillmentAttentionCounts();
    }

    final itemRows = await _client
        .from('order_items')
        .select(
          'order_id, product_id, quantity, delivered_quantity, cancelled_quantity',
        )
        .inFilter('order_id', orderMeta.keys.toList());

    final productIds = <String>{};
    final remainingByOrder =
        <String, List<({String productId, num remaining})>>{};

    for (final raw in itemRows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      final orderId = map['order_id'] as String?;
      final productId = map['product_id'] as String?;
      if (orderId == null || productId == null) continue;
      if (!orderMeta.containsKey(orderId)) continue;
      final ordered = _asNum(map['quantity']);
      final delivered = _asNum(map['delivered_quantity']);
      final cancelled = _asNum(map['cancelled_quantity']);
      final remaining = ordered - delivered - cancelled;
      if (remaining <= 0) continue;
      productIds.add(productId);
      remainingByOrder
          .putIfAbsent(orderId, () => [])
          .add((productId: productId, remaining: remaining));
    }

    if (productIds.isEmpty) {
      return FulfillmentAttentionCounts(
        placed: placed,
        partiallyDelivered: partiallyDelivered,
      );
    }

    final invRows = await _client
        .from('inventory')
        .select('branch_id, product_id, quantity')
        .inFilter('product_id', productIds.toList());

    final available = <String, num>{};
    for (final raw in invRows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      final branchId = map['branch_id'] as String?;
      final productId = map['product_id'] as String?;
      if (branchId == null || productId == null) continue;
      final qty = _asNum(map['quantity']);
      available['$branchId|$productId'] = qty < 0 ? 0 : qty;
    }

    var waitingPlaced = 0;
    var waitingPartial = 0;
    for (final entry in orderMeta.entries) {
      final lines = remainingByOrder[entry.key];
      if (lines == null || lines.isEmpty) continue;
      final branchId = entry.value.branchId;
      var blocked = false;
      for (final line in lines) {
        final avail = available['$branchId|${line.productId}'] ?? 0;
        if (line.remaining > avail) {
          blocked = true;
          break;
        }
      }
      if (!blocked) continue;
      switch (entry.value.status) {
        case OrderStatus.placed:
          waitingPlaced++;
        case OrderStatus.partiallyDelivered:
          waitingPartial++;
        case OrderStatus.draft:
        case OrderStatus.completed:
        case OrderStatus.cancelled:
          break;
      }
    }

    return FulfillmentAttentionCounts(
      placed: placed,
      partiallyDelivered: partiallyDelivered,
      waitingPlaced: waitingPlaced,
      waitingPartial: waitingPartial,
    );
  }

  Future<List<SalesRepOption>> fetchSalesReps() async {
    try {
      final rows = await _client
          .from('employees')
          .select(
            'id, full_name, roles!employees_role_id_fkey (code)',
          )
          .isFilter('deleted_at', null)
          .eq('is_active', true)
          .order('full_name');
      return (rows as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final roles = row['roles'];
        final roleCode = roles is Map
            ? roles['code'] as String?
            : null;
        return SalesRepOption(
          id: row['id'] as String,
          name: (row['full_name'] as String?)?.trim().isNotEmpty == true
              ? row['full_name'] as String
              : 'Unknown',
          roleCode: roleCode,
        );
      }).toList();
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Employees eligible to execute field visits (IAM [canPerformFieldVisits]).
  Future<List<SalesRepOption>> fetchFieldVisitAssignees() async {
    final all = await fetchSalesReps();
    return [
      for (final option in all)
        if (option.canPerformFieldVisits) option,
    ];
  }

  Future<OrderDetail?> fetchById(String orderId) async {
    try {
      final row = await _client
          .from('orders')
          .select(_detailSelect)
          .eq('id', orderId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;

      final summary = OrderSummary.fromJson(Map<String, dynamic>.from(row));
      final rawItems = row['order_items'];
      final lines = <OrderLineItem>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          lines.add(
            OrderLineItem.fromJson(Map<String, dynamic>.from(item as Map)),
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

      return OrderDetail(
        summary: summary,
        lines: lines,
        customerOutstanding: outstanding,
        customerWallet: wallet,
        customerCreditAllowed: creditAllowed,
        customerCreditLimit: creditLimit,
        timeline: await _buildTimeline(summary),
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> archiveOrder(String orderId) async {
    try {
      await _client.rpc('archive_order', params: {'p_order_id': orderId});
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapOrderError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<List<OrderTimelineEvent>> _buildTimeline(OrderSummary order) async {
    final events = <OrderTimelineEvent>[
      OrderTimelineEvent(
        kind: OrderTimelineKind.created,
        title: 'Order created',
        at: order.orderedAt,
        detail: order.employeeName == null
            ? null
            : 'Opened by ${order.employeeName}',
      ),
    ];

    if (order.completedAt != null) {
      events.add(
        OrderTimelineEvent(
          kind: OrderTimelineKind.completed,
          title: 'Order completed',
          at: order.completedAt!,
          detail: 'Inventory reduced · '
              '${order.paymentStatus.label}'
              '${order.paymentMethod == null ? '' : ' · ${order.paymentMethod!.label}'}',
        ),
      );
    }

    if (order.cancelledAt != null) {
      events.add(
        OrderTimelineEvent(
          kind: OrderTimelineKind.cancelled,
          title: 'Order cancelled',
          at: order.cancelledAt!,
          detail: 'No inventory movement',
        ),
      );
    }

    try {
      final paymentRows = await _client
          .from('payment_allocations')
          .select('''
            amount,
            created_at,
            payments (
              payment_number,
              method,
              received_at,
              status,
              deleted_at
            )
          ''')
          .eq('order_id', order.id);

      final paymentList = paymentRows as List;
      for (final raw in paymentList) {
          final row = Map<String, dynamic>.from(raw as Map);
          final payment = row['payments'];
          if (payment is! Map) continue;
          if (payment['deleted_at'] != null) continue;
          if ((payment['status'] as String?) == 'cancelled') continue;
          final method = PaymentMethod.fromDb(payment['method'] as String?);
          final amount = _asNum(row['amount']);
          final at = DateTime.tryParse(
                (payment['received_at'] as String?) ??
                    (row['created_at'] as String?) ??
                    '',
              ) ??
              order.updatedAt;
          events.add(
            OrderTimelineEvent(
              kind: OrderTimelineKind.paymentReceived,
              title: 'Payment recorded',
              at: at,
              detail:
                  '${payment['payment_number'] ?? 'Payment'} · '
                  '${method?.label ?? 'Payment'} · $amount',
            ),
          );
        }
    } catch (_) {
      // Timeline enrichment is best-effort when migrations lag.
    }

    try {
      final stockRows = await _client
          .from('stock_movements')
          .select('quantity_delta, created_at, reason')
          .eq('reference_type', 'order')
          .eq('reference_id', order.id)
          .order('created_at');

      final stockList = stockRows as List;
      if (stockList.isNotEmpty) {
        num totalUnits = 0;
        DateTime? at;
        for (final raw in stockList) {
          final row = Map<String, dynamic>.from(raw as Map);
          totalUnits += _asNum(row['quantity_delta']).abs();
          at ??= DateTime.tryParse(row['created_at'] as String? ?? '');
        }
        events.add(
          OrderTimelineEvent(
            kind: OrderTimelineKind.stockMoved,
            title: 'Stock movement',
            at: at ?? order.completedAt ?? order.updatedAt,
            detail: '${stockList.length} line'
                '${stockList.length == 1 ? '' : 's'} · '
                '$totalUnits units adjusted',
          ),
        );
      }
    } catch (_) {
      // Best-effort.
    }

    if (order.notes != null && order.notes!.trim().isNotEmpty) {
      events.add(
        OrderTimelineEvent(
          kind: OrderTimelineKind.note,
          title: 'Notes added',
          at: order.updatedAt,
          detail: order.notes!.trim(),
        ),
      );
    }

    events.sort((a, b) => a.at.compareTo(b.at));
    return events;
  }

  Future<OrderSaveResult> saveOrder({
    required OrderUpsertInput input,
    required String companyId,
    required String branchId,
    required String employeeId,
    bool complete = false,
    bool place = false,
  }) async {
    if (input.lines.isEmpty) {
      throw const ValidationFailure('Add at least one product to the order.');
    }

    try {
      final subtotal = input.subtotal;
      final total = input.total;
      final isNew = input.orderId == null;

      String orderId;
      if (isNew) {
        final orderNumber = await _allocateOrderNumber(companyId);
        final inserted = await _client
            .from('orders')
            .insert({
              'company_id': companyId,
              'branch_id': branchId,
              'customer_id': input.customerId,
              'employee_id': employeeId,
              'order_number': orderNumber,
              'status': OrderStatus.draft.dbValue,
              'payment_status': input.paymentStatus.dbValue,
              'payment_method': input.paymentMethod?.dbValue,
              'subtotal': subtotal,
              'discount_amount': input.orderDiscount,
              'tax_amount': input.taxAmount,
              'total': total,
              'notes': _nullIfBlank(input.notes),
              if (input.visitId != null) 'visit_id': input.visitId,
              if (input.offlineClientId != null)
                'offline_client_id': input.offlineClientId,
              'created_by': employeeId,
              'updated_by': employeeId,
            })
            .select('id')
            .single();
        orderId = inserted['id'] as String;
      } else {
        orderId = input.orderId!;
        final existing = await _client
            .from('orders')
            .select('id, status, deleted_at')
            .eq('id', orderId)
            .maybeSingle();
        if (existing == null || existing['deleted_at'] != null) {
          throw const ValidationFailure('Order not found.');
        }
        final status = OrderStatus.fromDb(existing['status'] as String?);
        if (status != OrderStatus.draft) {
          throw const ValidationFailure(
            'Only draft orders can be edited. Place or cancel remaining to change delivery.',
          );
        }

        await _client.from('orders').update({
          'customer_id': input.customerId,
          'payment_status': input.paymentStatus.dbValue,
          'payment_method': input.paymentMethod?.dbValue,
          'subtotal': subtotal,
          'discount_amount': input.orderDiscount,
          'tax_amount': input.taxAmount,
          'total': total,
          'notes': _nullIfBlank(input.notes),
          'updated_by': employeeId,
        }).eq('id', orderId);

        await _client.from('order_items').delete().eq('order_id', orderId);
      }

      final lineRows = [
        for (final line in input.lines)
          {
            'company_id': companyId,
            'order_id': orderId,
            'product_id': line.productId,
            'quantity': line.quantity,
            'unit_price': line.unitPrice,
            'discount': line.discount,
            'discount_type': line.discountType,
            'line_total': line.lineTotal,
            'created_by': employeeId,
            'updated_by': employeeId,
          },
      ];
      await _client.from('order_items').insert(lineRows);

      OrderConfirmationOutcome? confirmation;
      if (place) {
        await placeOrder(orderId);
      } else if (complete) {
        confirmation = await completeOrder(
          orderId,
          companyId: companyId,
          employeeId: employeeId,
        );
      }

      if (isNew && !place && !complete) {
        final detail = await fetchById(orderId);
        final orderNumber = detail?.summary.orderNumber ?? orderId;
        final customerName = detail?.summary.customerName ?? 'a customer';
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: employeeId,
          event: BusinessEvents.orderCreated(
            orderId: orderId,
            orderNumber: orderNumber,
            customerName: customerName,
            excludeEmployeeId: employeeId,
          ),
        );
      }
      // place_sales_order emits order_placed (+ insufficient-stock) transactionally.

      return OrderSaveResult(orderId: orderId, confirmation: confirmation);
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapOrderError(error.message));
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<OrderConfirmationOutcome?> completeOrder(
    String orderId, {
    String? companyId,
    String? employeeId,
  }) async {
    var publishedCompletion = false;
    try {
      await _client.rpc('complete_sales_order', params: {
        'p_order_id': orderId,
      });
      publishedCompletion = true;
    } on PostgrestException catch (error) {
      final existing = await fetchById(orderId);
      if (existing?.summary.status != OrderStatus.completed) {
        throw ValidationFailure(_mapOrderError(error.message));
      }
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }

    final detail = await fetchById(orderId);
    final resolvedCompanyId = companyId ?? detail?.summary.companyId;
    if (publishedCompletion && resolvedCompanyId != null) {
      await _events.publish(
        companyId: resolvedCompanyId,
        actorEmployeeId: employeeId,
        event: BusinessEvents.orderCompleted(
          orderId: orderId,
          orderNumber: detail?.summary.orderNumber ?? orderId,
          customerName: detail?.summary.customerName ?? 'a customer',
          excludeEmployeeId: employeeId,
        ),
      );
    }

    final dispatcher = confirmations;
    if (dispatcher == null) return null;
    if (detail != null &&
        !OrderConfirmationDispatcher.shouldDispatch(detail.summary.status)) {
      return null;
    }
    try {
      return await dispatcher.dispatch(orderId);
    } catch (_) {
      return null;
    }
  }

  /// Record demand without inventory movement or payment settlement.
  Future<void> placeOrder(String orderId) async {
    try {
      await _client.rpc('place_sales_order', params: {
        'p_order_id': orderId,
      });
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapOrderError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Deliver line quantities and deduct inventory for those quantities only.
  Future<void> fulfillOrderItems({
    required String orderId,
    required List<({String orderItemId, num quantity})> lines,
  }) async {
    if (lines.isEmpty) {
      throw const ValidationFailure('Provide at least one delivery line.');
    }
    try {
      await _client.rpc('fulfill_order_items', params: {
        'p_order_id': orderId,
        'p_lines': [
          for (final line in lines)
            {
              'order_item_id': line.orderItemId,
              'quantity': line.quantity,
            },
        ],
      });
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapOrderError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Cancel outstanding remaining quantity (no inventory impact).
  ///
  /// When [lines] is null, cancels all remaining on the order.
  Future<void> cancelOrderRemaining({
    required String orderId,
    List<({String orderItemId, num quantity})>? lines,
  }) async {
    try {
      await _client.rpc('cancel_order_remaining', params: {
        'p_order_id': orderId,
        'p_lines': lines == null
            ? null
            : [
                for (final line in lines)
                  {
                    'order_item_id': line.orderItemId,
                    'quantity': line.quantity,
                  },
              ],
      });
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapOrderError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> cancelOrder({
    required String orderId,
    required String employeeId,
    String? companyId,
  }) async {
    try {
      final existing = await _client
          .from('orders')
          .select('id, company_id, order_number, status, deleted_at')
          .eq('id', orderId)
          .maybeSingle();
      if (existing == null || existing['deleted_at'] != null) {
        throw const ValidationFailure('Order not found.');
      }
      final status = OrderStatus.fromDb(existing['status'] as String?);
      if (status == OrderStatus.completed) {
        throw const ValidationFailure(
          'Completed orders cannot be cancelled. Use returns later.',
        );
      }
      if (status == OrderStatus.cancelled) return;

      if (status == OrderStatus.placed ||
          status == OrderStatus.partiallyDelivered) {
        await cancelOrderRemaining(orderId: orderId);
        final after = await fetchById(orderId);
        // Only emit cancelled when demand was closed with no deliveries.
        if (after?.summary.status != OrderStatus.cancelled) {
          return;
        }
      } else {
        await _client.from('orders').update({
          'status': OrderStatus.cancelled.dbValue,
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': employeeId,
        }).eq('id', orderId);
      }

      final resolvedCompanyId =
          companyId ?? existing['company_id'] as String?;
      final orderNumber = existing['order_number'] as String? ?? orderId;
      if (resolvedCompanyId != null) {
        await _events.publish(
          companyId: resolvedCompanyId,
          actorEmployeeId: employeeId,
          event: BusinessEvents.orderCancelled(
            orderId: orderId,
            orderNumber: orderNumber,
            excludeEmployeeId: employeeId,
          ),
        );
      }
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapOrderError(error.message));
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<String> _allocateOrderNumber(String companyId) async {
    try {
      final result = await _client.rpc(
        'next_order_number',
        params: {'p_company_id': companyId},
      );
      if (result is String && result.trim().isNotEmpty) return result.trim();
    } catch (_) {
      // Fallback when RPC not yet applied.
    }
    final stamp = DateTime.now().toUtc();
    final suffix = stamp.millisecondsSinceEpoch.toString().substring(7);
    return 'SO-${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}-$suffix';
  }

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String _mapOrderError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('not enough stock for')) {
      return message;
    }
    if (lower.contains('inventory_quantity_non_negative') ||
        lower.contains('not enough stock') ||
        lower.contains('insufficient stock')) {
      return 'Not enough stock at this branch to complete the order.';
    }
    if (lower.contains('insufficient wallet')) {
      return 'Insufficient wallet balance for this customer.';
    }
    if (lower.contains('not allowed to buy on credit')) {
      return 'This customer is not allowed to buy on credit.';
    }
    if (lower.contains('archive completed')) {
      return message;
    }
    if (lower.contains('orders_company_order_number')) {
      return 'Order number conflict. Try saving again.';
    }
    if (lower.contains('only draft')) {
      return message;
    }
    return message;
  }
}
