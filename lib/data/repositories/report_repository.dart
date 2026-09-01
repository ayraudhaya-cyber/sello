import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/inventory_repository.dart';
import 'package:sello/data/repositories/order_repository.dart';
import 'package:sello/data/repositories/payment_repository.dart';
import 'package:sello/data/repositories/supplier_repository.dart';
import 'package:sello/data/repositories/visit_repository.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

num _asNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _asDate(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _asString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Shared reporting layer — composes domain repositories; no parallel math.
///
/// Sales / ranking queries live here so Inventory, Payments, and Orders keep
/// owning their source-of-truth dashboard stats.
class ReportRepository {
  ReportRepository({
    SupabaseClient? client,
    InventoryRepository? inventory,
    PaymentRepository? payments,
    OrderRepository? orders,
    SupplierRepository? suppliers,
    VisitRepository? visits,
  })  : _client = client ?? SupabaseService.client,
        _inventory = inventory ?? InventoryRepository(),
        _payments = payments ?? PaymentRepository(),
        _orders = orders ?? OrderRepository(),
        _suppliers = suppliers ?? SupplierRepository(),
        _visits = visits ?? VisitRepository();

  final SupabaseClient _client;
  final InventoryRepository _inventory;
  final PaymentRepository _payments;
  final OrderRepository _orders;
  final SupplierRepository _suppliers;
  final VisitRepository _visits;

  Future<ReportsOverview> fetchOverview({
    required String companyId,
    String? branchId,
    ReportDatePreset preset = ReportDatePreset.thisMonth,
    ReportQuery? query,
  }) async {
    final resolved = query ??
        ReportQuery(
          preset: preset,
          branchId: branchId,
        );
    final bounds = resolved.bounds();
    final todayBounds = ReportDatePreset.today.bounds();
    final effectiveBranch = resolved.branchId ?? branchId;

    try {
      final inventory =
          await _inventory.fetchDashboardStats(branchId: effectiveBranch);
      final payments = await _payments.fetchDashboardStats();
      final orderCounts = await _orders.fetchCounts();
      final suppliers =
          await _suppliers.fetchDashboardStats(companyId: companyId);

      final periodOrders = await _fetchCompletedOrders(
        from: bounds.from,
        to: bounds.to,
        branchId: effectiveBranch,
        employeeId: resolved.employeeId,
        customerId: resolved.customerId,
      );
      final todayOrders = resolved.preset == ReportDatePreset.today &&
              resolved.employeeId == null &&
              resolved.customerId == null
          ? periodOrders
          : await _fetchCompletedOrders(
              from: todayBounds.from,
              to: todayBounds.to,
              branchId: effectiveBranch,
              employeeId: resolved.employeeId,
              customerId: resolved.customerId,
            );

      final salesInPeriod = periodOrders.fold<num>(0, (sum, o) => sum + o.total);
      final salesToday = todayOrders.fold<num>(0, (sum, o) => sum + o.total);
      final orderCount = periodOrders.length;
      final aov = orderCount == 0 ? 0 : salesInPeriod / orderCount;

      final collectionsInPeriod = await _fetchCollectionsTotal(
        from: bounds.from,
        to: bounds.to,
      );

      var visitsCompleted = 0;
      var visitsMissed = 0;
      var visitsScheduled = 0;
      var visitsWithOrders = 0;
      var visitsWithPayments = 0;
      var visitOrdersLinked = 0;
      num visitCollectionsAmount = 0;
      var visitRepPerformance = <ReportNamedValue>[];
      try {
        final visitMetrics = await _visits.fetchVisitReportMetrics(
          companyId: companyId,
          from: bounds.from,
          to: bounds.to,
        );
        visitsCompleted = visitMetrics.completed;
        visitsMissed = visitMetrics.missed;
        visitsScheduled = visitMetrics.scheduled;
        visitsWithOrders = visitMetrics.withOrders;
        visitsWithPayments = visitMetrics.withPayments;
        visitOrdersLinked = visitMetrics.ordersLinked;
        visitCollectionsAmount = visitMetrics.collectionsAmount;
        visitRepPerformance = [
          for (final row in visitMetrics.byRepresentative)
            ReportNamedValue(
              id: row.employeeId,
              name: row.name,
              value: row.completed,
              subtitle: row.completed == 0
                  ? 'No visits'
                  : '${row.withOrders} with orders '
                      '(${((row.withOrders / row.completed) * 100).round()}%)',
              referenceType: 'employee',
            ),
        ];
      } catch (_) {
        // Visit metrics are additive — reports still load if migration pending.
      }

      final topProducts = await _fetchTopProducts(
        from: bounds.from,
        to: bounds.to,
        branchId: effectiveBranch,
      );
      final topCategories = await _fetchTopCategories(
        from: bounds.from,
        to: bounds.to,
        branchId: effectiveBranch,
      );

      // Comparison snapshot reserved — previous period / YoY later.
      ReportsOverview? comparison;
      if (resolved.comparison != ReportComparisonMode.none) {
        comparison = null;
      }

      return ReportsOverview(
        preset: resolved.preset,
        from: bounds.from,
        to: bounds.to,
        query: resolved,
        salesToday: salesToday,
        salesInPeriod: salesInPeriod,
        ordersInPeriod: orderCount,
        averageOrderValue: aov,
        collectionsInPeriod: collectionsInPeriod,
        inventory: inventory,
        payments: payments,
        orderCounts: orderCounts,
        suppliers: suppliers,
        salesTrend: _buildTrend(periodOrders, bounds.from, bounds.to),
        topProducts: topProducts,
        topCategories: topCategories,
        topCustomers: _rankBySales(
          periodOrders,
          byCustomer: true,
          referenceType: 'customer',
        ),
        topSalesReps: _rankBySales(
          periodOrders,
          byCustomer: false,
          referenceType: 'employee',
        ),
        outstandingCustomers: await _fetchOutstandingCustomers(),
        recentCustomers: await _fetchRecentCustomers(),
        inactiveCustomers: await _fetchInactiveCustomers(),
        paymentMethods: await _fetchPaymentMethodBreakdown(
          from: bounds.from,
          to: bounds.to,
        ),
        paymentStatusCounts: _paymentStatusCounts(periodOrders),
        productsBySupplier: await _fetchProductsBySupplier(companyId: companyId),
        recentSuppliers: suppliers.recentlyAdded,
        visitsCompleted: visitsCompleted,
        visitsMissed: visitsMissed,
        visitsScheduled: visitsScheduled,
        visitsWithOrders: visitsWithOrders,
        visitsWithPayments: visitsWithPayments,
        visitOrdersLinked: visitOrdersLinked,
        visitCollectionsAmount: visitCollectionsAmount,
        visitRepPerformance: visitRepPerformance,
        comparisonOverview: comparison,
      );
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load reports.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load reports.');
    }
  }

  /// Export seam — formats prepared; generation / scheduling ships later.
  Future<String?> prepareExport(ReportExportRequest request) async {
    final label = request.query?.preset.label ?? request.preset.label;
    if (request.scheduleCron != null) {
      return 'Scheduled delivery for ${request.reportId} ($label) is coming soon.';
    }
    return switch (request.format) {
      ReportExportFormat.pdf =>
        'PDF export for ${request.reportId} ($label) is coming soon.',
      ReportExportFormat.excel =>
        'Excel export for ${request.reportId} ($label) is coming soon.',
      ReportExportFormat.csv =>
        'CSV export for ${request.reportId} ($label) is coming soon.',
      ReportExportFormat.print =>
        'Print layout for ${request.reportId} ($label) is coming soon.',
    };
  }

  Future<List<_OrderAgg>> _fetchCompletedOrders({
    required DateTime from,
    required DateTime to,
    String? branchId,
    String? employeeId,
    String? customerId,
  }) async {
    var query = _client
        .from('orders')
        .select('''
          id,
          total,
          ordered_at,
          customer_id,
          employee_id,
          payment_status,
          payment_method,
          branch_id,
          customers!customer_id (id, name),
          employees!employee_id (id, full_name)
        ''')
        .eq('status', OrderStatus.completed.dbValue)
        .isFilter('deleted_at', null)
        .gte('ordered_at', from.toIso8601String())
        .lte('ordered_at', to.toIso8601String());

    if (branchId != null && branchId.isNotEmpty) {
      query = query.eq('branch_id', branchId);
    }
    if (employeeId != null && employeeId.isNotEmpty) {
      query = query.eq('employee_id', employeeId);
    }
    if (customerId != null && customerId.isNotEmpty) {
      query = query.eq('customer_id', customerId);
    }

    final rows = await query.order('ordered_at', ascending: true).limit(2000);
    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final customer = map['customers'];
      final employee = map['employees'];
      return _OrderAgg(
        id: map['id'] as String,
        total: _asNum(map['total']),
        orderedAt: _asDate(map['ordered_at']) ?? from,
        customerId: map['customer_id'] as String?,
        customerName: customer is Map ? _asString(customer['name']) : null,
        employeeId: map['employee_id'] as String?,
        employeeName:
            employee is Map ? _asString(employee['full_name']) : null,
        paymentStatus: PaymentStatus.fromDb(map['payment_status'] as String?),
        paymentMethod: map['payment_method'] as String?,
      );
    }).toList();
  }

  Future<num> _fetchCollectionsTotal({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from('payments')
        .select('amount')
        .isFilter('deleted_at', null)
        .eq('status', 'completed')
        .gte('received_at', from.toIso8601String())
        .lte('received_at', to.toIso8601String());

    num total = 0;
    for (final row in rows as List) {
      total += _asNum((row as Map)['amount']);
    }
    return total;
  }

  Future<List<ReportNamedValue>> _fetchTopProducts({
    required DateTime from,
    required DateTime to,
    String? branchId,
    int limit = 8,
  }) async {
    var query = _client.from('order_items').select('''
      product_id,
      quantity,
      line_total,
      products (id, name, sku, category_id, categories (name)),
      orders!inner (status, ordered_at, deleted_at, branch_id)
    ''').eq('orders.status', OrderStatus.completed.dbValue).isFilter(
          'orders.deleted_at',
          null,
        ).gte('orders.ordered_at', from.toIso8601String()).lte(
          'orders.ordered_at',
          to.toIso8601String(),
        );

    if (branchId != null && branchId.isNotEmpty) {
      query = query.eq('orders.branch_id', branchId);
    }

    final rows = await query.limit(5000);
    final totals = <String, _NamedAgg>{};

    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final product = map['products'];
      final productId = map['product_id'] as String? ??
          (product is Map ? product['id'] as String? : null);
      if (productId == null) continue;
      final name = product is Map
          ? (_asString(product['name']) ?? 'Product')
          : 'Product';
      final sku = product is Map ? _asString(product['sku']) : null;
      final agg = totals.putIfAbsent(
        productId,
        () => _NamedAgg(id: productId, name: name, subtitle: sku),
      );
      agg.value += _asNum(map['line_total']);
      agg.count += _asNum(map['quantity']).round();
    }

    final ranked = totals.values.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final item in ranked.take(limit))
        ReportNamedValue(
          id: item.id,
          name: item.name,
          value: item.value,
          subtitle: item.subtitle,
          count: item.count,
          referenceType: 'product',
        ),
    ];
  }

  Future<List<ReportNamedValue>> _fetchTopCategories({
    required DateTime from,
    required DateTime to,
    String? branchId,
    int limit = 6,
  }) async {
    var query = _client.from('order_items').select('''
      line_total,
      quantity,
      products (category_id, categories (id, name)),
      orders!inner (status, ordered_at, deleted_at, branch_id)
    ''').eq('orders.status', OrderStatus.completed.dbValue).isFilter(
          'orders.deleted_at',
          null,
        ).gte('orders.ordered_at', from.toIso8601String()).lte(
          'orders.ordered_at',
          to.toIso8601String(),
        );

    if (branchId != null && branchId.isNotEmpty) {
      query = query.eq('orders.branch_id', branchId);
    }

    final rows = await query.limit(5000);
    final totals = <String, _NamedAgg>{};

    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final product = map['products'];
      String? categoryId;
      String categoryName = 'Uncategorised';
      if (product is Map) {
        final categories = product['categories'];
        if (categories is Map) {
          categoryId = categories['id'] as String?;
          categoryName = _asString(categories['name']) ?? categoryName;
        }
        categoryId ??= product['category_id'] as String?;
      }
      final key = categoryId ?? '__none__';
      final agg = totals.putIfAbsent(
        key,
        () => _NamedAgg(id: key, name: categoryName),
      );
      agg.value += _asNum(map['line_total']);
      agg.count += _asNum(map['quantity']).round();
    }

    final ranked = totals.values.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final item in ranked.take(limit))
        ReportNamedValue(
          id: item.id,
          name: item.name,
          value: item.value,
          count: item.count,
        ),
    ];
  }

  List<ReportNamedValue> _rankBySales(
    List<_OrderAgg> orders, {
    required bool byCustomer,
    String? referenceType,
    int limit = 8,
  }) {
    final totals = <String, _NamedAgg>{};
    for (final order in orders) {
      final id = byCustomer ? order.customerId : order.employeeId;
      final name = byCustomer ? order.customerName : order.employeeName;
      if (id == null) continue;
      final agg = totals.putIfAbsent(
        id,
        () => _NamedAgg(id: id, name: name ?? (byCustomer ? 'Customer' : 'Rep')),
      );
      agg.value += order.total;
      agg.count += 1;
    }
    final ranked = totals.values.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final item in ranked.take(limit))
        ReportNamedValue(
          id: item.id,
          name: item.name,
          value: item.value,
          count: item.count,
          subtitle: item.count == 1 ? '1 order' : '${item.count} orders',
          referenceType: referenceType,
        ),
    ];
  }

  List<ReportTrendPoint> _buildTrend(
    List<_OrderAgg> orders,
    DateTime from,
    DateTime to,
  ) {
    final start = DateTime.utc(from.year, from.month, from.day);
    final end = DateTime.utc(to.year, to.month, to.day);
    final days = end.difference(start).inDays;
    final bucketCount = days < 0 ? 0 : days + 1;
    final sales = List<num>.filled(bucketCount, 0);
    final counts = List<int>.filled(bucketCount, 0);

    for (final order in orders) {
      final day = DateTime.utc(
        order.orderedAt.toUtc().year,
        order.orderedAt.toUtc().month,
        order.orderedAt.toUtc().day,
      );
      final index = day.difference(start).inDays;
      if (index < 0 || index >= bucketCount) continue;
      sales[index] += order.total;
      counts[index] += 1;
    }

    return [
      for (var i = 0; i < bucketCount; i++)
        ReportTrendPoint(
          day: start.add(Duration(days: i)),
          sales: sales[i],
          orders: counts[i],
        ),
    ];
  }

  List<ReportStatusCount> _paymentStatusCounts(List<_OrderAgg> orders) {
    final counts = <PaymentStatus, int>{
      for (final status in PaymentStatus.values) status: 0,
    };
    for (final order in orders) {
      counts[order.paymentStatus] = (counts[order.paymentStatus] ?? 0) + 1;
    }
    return [
      for (final entry in counts.entries)
        if (entry.value > 0)
          ReportStatusCount(
            key: entry.key.dbValue,
            label: entry.key.label,
            count: entry.value,
          ),
    ];
  }

  Future<List<ReportNamedValue>> _fetchPaymentMethodBreakdown({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _client
        .from('payments')
        .select('amount, method')
        .isFilter('deleted_at', null)
        .eq('status', 'completed')
        .gte('received_at', from.toIso8601String())
        .lte('received_at', to.toIso8601String());

    final totals = <String, num>{};
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final method = map['method'] as String? ?? 'other';
      totals[method] = (totals[method] ?? 0) + _asNum(map['amount']);
    }

    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in ranked)
        ReportNamedValue(
          id: entry.key,
          name: PaymentMethod.fromDb(entry.key)?.label ?? entry.key,
          value: entry.value,
        ),
    ];
  }

  /// Public for Intelligence / Action Center — same query as report overview.
  Future<List<ReportNamedValue>> fetchOutstandingCustomers({
    int limit = 8,
  }) =>
      _fetchOutstandingCustomers(limit: limit);

  /// Public for Intelligence — inactive / quiet customers (60d+).
  Future<List<ReportNamedValue>> fetchInactiveCustomers({
    int limit = 8,
  }) =>
      _fetchInactiveCustomers(limit: limit);

  Future<List<ReportNamedValue>> _fetchOutstandingCustomers({
    int limit = 8,
  }) async {
    final rows = await _client
        .from('customers')
        .select('id, name, current_balance, phone')
        .isFilter('deleted_at', null)
        .eq('is_active', true)
        .gt('current_balance', 0)
        .order('current_balance', ascending: false)
        .limit(limit);

    return [
      for (final row in rows as List)
        ReportNamedValue(
          id: (row as Map)['id'] as String,
          name: _asString(row['name']) ?? 'Customer',
          value: _asNum(row['current_balance']),
          subtitle: _asString(row['phone']),
          referenceType: 'customer',
        ),
    ];
  }

  Future<List<ReportNamedValue>> _fetchRecentCustomers({int limit = 8}) async {
    final cutoff =
        DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final rows = await _client
        .from('customers')
        .select('id, name, created_at, phone')
        .isFilter('deleted_at', null)
        .gte('created_at', cutoff)
        .order('created_at', ascending: false)
        .limit(limit);

    return [
      for (final row in rows as List)
        ReportNamedValue(
          id: (row as Map)['id'] as String,
          name: _asString(row['name']) ?? 'Customer',
          value: 1,
          subtitle: _asString(row['phone']) ?? 'New in last 30 days',
          referenceType: 'customer',
        ),
    ];
  }

  Future<List<ReportNamedValue>> _fetchInactiveCustomers({
    int limit = 8,
  }) async {
    final cutoff =
        DateTime.now().toUtc().subtract(const Duration(days: 60)).toIso8601String();
    final rows = await _client
        .from('customers')
        .select('id, name, last_purchase_at, phone, is_active')
        .isFilter('deleted_at', null)
        .eq('is_active', true)
        .or('last_purchase_at.is.null,last_purchase_at.lt.$cutoff')
        .order('last_purchase_at', ascending: true)
        .limit(limit);

    return [
      for (final row in rows as List)
        ReportNamedValue(
          id: (row as Map)['id'] as String,
          name: _asString(row['name']) ?? 'Customer',
          value: 0,
          subtitle: row['last_purchase_at'] == null
              ? 'No purchases yet'
              : 'Last purchase over 60 days ago',
          referenceType: 'customer',
        ),
    ];
  }

  Future<List<ReportNamedValue>> _fetchProductsBySupplier({
    required String companyId,
    int limit = 8,
  }) async {
    final rows = await _client
        .from('products')
        .select('id, preferred_supplier_id, suppliers!preferred_supplier_id (id, name)')
        .eq('company_id', companyId)
        .isFilter('deleted_at', null)
        .not('preferred_supplier_id', 'is', null);

    final totals = <String, _NamedAgg>{};
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final supplier = map['suppliers'];
      final supplierId = map['preferred_supplier_id'] as String?;
      if (supplierId == null) continue;
      final name = supplier is Map
          ? (_asString(supplier['name']) ?? 'Supplier')
          : 'Supplier';
      final agg = totals.putIfAbsent(
        supplierId,
        () => _NamedAgg(id: supplierId, name: name),
      );
      agg.count += 1;
      agg.value += 1;
    }

    final ranked = totals.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return [
      for (final item in ranked.take(limit))
        ReportNamedValue(
          id: item.id,
          name: item.name,
          value: item.count,
          subtitle: item.count == 1 ? '1 product' : '${item.count} products',
          count: item.count,
        ),
    ];
  }
}

class _OrderAgg {
  const _OrderAgg({
    required this.id,
    required this.total,
    required this.orderedAt,
    required this.paymentStatus,
    this.customerId,
    this.customerName,
    this.employeeId,
    this.employeeName,
    this.paymentMethod,
  });

  final String id;
  final num total;
  final DateTime orderedAt;
  final String? customerId;
  final String? customerName;
  final String? employeeId;
  final String? employeeName;
  final PaymentStatus paymentStatus;
  final String? paymentMethod;
}

class _NamedAgg {
  _NamedAgg({
    required this.id,
    required this.name,
    this.subtitle,
  });

  final String id;
  final String name;
  final String? subtitle;
  num value = 0;
  int count = 0;
}
