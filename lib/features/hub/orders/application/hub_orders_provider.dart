import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/order_repository.dart';
import 'package:sello/features/hub/inventory/application/inventory_cross_refresh.dart';
import 'package:sello/features/hub/products/application/products_cross_refresh.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/utils/hub_table_paging.dart';

enum OrderStatusFilter {
  all,
  draft,
  openFulfillment,
  placed,
  partiallyDelivered,
  completed,
  cancelled,
}

enum OrderPaymentFilter { all, unpaid, partial, paid }

enum OrderDateFilter { all, today, last7Days, thisMonth }

enum OrderSort {
  orderedAt('ordered_at'),
  orderNumber('order_number'),
  total('total');

  const OrderSort(this.column);
  final String column;
}

class HubOrdersState {
  const HubOrdersState({
    this.items = const [],
    this.reps = const [],
    this.counts = const OrderCounts(
      total: 0,
      draft: 0,
      completed: 0,
      cancelled: 0,
    ),
    this.search = '',
    this.statusFilter = OrderStatusFilter.all,
    this.paymentFilter = OrderPaymentFilter.all,
    this.dateFilter = OrderDateFilter.all,
    this.employeeId,
    this.sort = OrderSort.orderedAt,
    this.sortAscending = false,
    this.page = 0,
    this.pageSize = kHubTablePageSize,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<OrderSummary> items;
  final List<SalesRepOption> reps;
  final OrderCounts counts;
  final String search;
  final OrderStatusFilter statusFilter;
  final OrderPaymentFilter paymentFilter;
  final OrderDateFilter dateFilter;
  final String? employeeId;
  final OrderSort sort;
  final bool sortAscending;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  bool get hasActiveFilters =>
      search.trim().isNotEmpty ||
      statusFilter != OrderStatusFilter.all ||
      paymentFilter != OrderPaymentFilter.all ||
      dateFilter != OrderDateFilter.all ||
      employeeId != null;

  HubOrdersState copyWith({
    List<OrderSummary>? items,
    List<SalesRepOption>? reps,
    OrderCounts? counts,
    String? search,
    OrderStatusFilter? statusFilter,
    OrderPaymentFilter? paymentFilter,
    OrderDateFilter? dateFilter,
    String? employeeId,
    bool clearEmployee = false,
    OrderSort? sort,
    bool? sortAscending,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubOrdersState(
      items: items ?? this.items,
      reps: reps ?? this.reps,
      counts: counts ?? this.counts,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      paymentFilter: paymentFilter ?? this.paymentFilter,
      dateFilter: dateFilter ?? this.dateFilter,
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      sort: sort ?? this.sort,
      sortAscending: sortAscending ?? this.sortAscending,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

class HubOrdersNotifier extends Notifier<HubOrdersState> {
  OrderRepository get _repo => ref.read(orderRepositoryProvider);

  @override
  HubOrdersState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey = next == null
          ? null
          : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(_initialize);
    return const HubOrdersState(isLoading: true);
  }

  Future<void> _initialize() async {
    await Future.wait([_loadReps(), loadOrders(resetPage: true)]);
  }

  Future<void> _loadReps() async {
    try {
      final reps = await _repo.fetchSalesReps();
      state = state.copyWith(reps: reps);
    } on AppFailure {
      // Non-fatal — filter still works without labels.
    }
  }

  Future<void> refresh() async {
    await Future.wait([_loadReps(), loadOrders(resetPage: true)]);
  }

  Future<void> loadOrders({
    bool resetPage = false,
    bool showLoading = true,
  }) async {
    final page = resetPage ? 0 : state.page;
    final generation = ++_loadGeneration;
    state = state.copyWith(
      isLoading: showLoading ? true : state.isLoading,
      clearError: true,
      page: page,
      initialized: true,
    );

    try {
      final ordersFuture = _fetchFiltered(page: page, pageSize: state.pageSize);
      final countsFuture = _repo.fetchCounts();
      countsFuture.ignore();
      final result = await ordersFuture;
      final counts = await countsFuture;
      if (generation != _loadGeneration) return;

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        counts: counts,
        isLoading: false,
        clearError: true,
        initialized: true,
      );
    } on AppFailure catch (failure) {
      if (generation != _loadGeneration) return;
      // Keep the rows already on screen; the error banner explains the rest.
      state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
        initialized: true,
      );
    }
  }

  /// Every order matching the current filters (for Excel export).
  Future<List<OrderSummary>> fetchAllForExport({int maxRows = 20000}) async {
    const pageSize = 500;
    final rows = <OrderSummary>[];
    for (var page = 0; rows.length < maxRows; page++) {
      final result = await _fetchFiltered(page: page, pageSize: pageSize);
      rows.addAll(result.items);
      if (!result.hasMore) break;
    }
    return rows;
  }

  Future<OrderPageResult> _fetchFiltered({
    required int page,
    required int pageSize,
  }) {
    final now = DateTime.now();
    final orderedFrom = switch (state.dateFilter) {
      OrderDateFilter.all => null,
      OrderDateFilter.today => DateTime(now.year, now.month, now.day),
      OrderDateFilter.last7Days => now.subtract(const Duration(days: 7)),
      OrderDateFilter.thisMonth => DateTime(now.year, now.month, 1),
    };

    return _repo.fetchOrders(
      search: state.search,
      statuses: switch (state.statusFilter) {
        OrderStatusFilter.all => null,
        OrderStatusFilter.draft => const [
          OrderStatus.draft,
          OrderStatus.placed,
          OrderStatus.partiallyDelivered,
        ],
        OrderStatusFilter.openFulfillment => const [
          OrderStatus.placed,
          OrderStatus.partiallyDelivered,
        ],
        OrderStatusFilter.placed => const [OrderStatus.placed],
        OrderStatusFilter.partiallyDelivered => const [
          OrderStatus.partiallyDelivered,
        ],
        OrderStatusFilter.completed => const [OrderStatus.completed],
        OrderStatusFilter.cancelled => const [OrderStatus.cancelled],
      },
      paymentStatus: switch (state.paymentFilter) {
        OrderPaymentFilter.all => null,
        OrderPaymentFilter.unpaid => PaymentStatus.unpaid,
        OrderPaymentFilter.partial => PaymentStatus.partial,
        OrderPaymentFilter.paid => PaymentStatus.paid,
      },
      employeeId: state.employeeId,
      orderedFrom: orderedFrom,
      orderBy: state.sort.column,
      ascending: state.sortAscending,
      page: page,
      pageSize: pageSize,
    );
  }

  int _loadGeneration = 0;

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await loadOrders(resetPage: true);
  }

  /// Tapping the active column flips direction; a new column starts newest /
  /// largest first.
  Future<void> setSort(OrderSort sort) async {
    final ascending = state.sort == sort ? !state.sortAscending : false;
    state = state.copyWith(sort: sort, sortAscending: ascending, page: 0);
    await loadOrders(resetPage: true);
  }

  Future<void> setStatusFilter(OrderStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0);
    await loadOrders(resetPage: true);
  }

  Future<void> setPaymentFilter(OrderPaymentFilter value) async {
    state = state.copyWith(paymentFilter: value, page: 0);
    await loadOrders(resetPage: true);
  }

  Future<void> setDateFilter(OrderDateFilter value) async {
    state = state.copyWith(dateFilter: value, page: 0);
    await loadOrders(resetPage: true);
  }

  Future<void> setEmployeeFilter(String? employeeId) async {
    state = state.copyWith(
      employeeId: employeeId,
      clearEmployee: employeeId == null,
      page: 0,
    );
    await loadOrders(resetPage: true);
  }

  Future<void> clearFilters() async {
    state = state.copyWith(
      search: '',
      statusFilter: OrderStatusFilter.all,
      paymentFilter: OrderPaymentFilter.all,
      dateFilter: OrderDateFilter.all,
      clearEmployee: true,
      page: 0,
    );
    await loadOrders(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadOrders();
  }

  Future<OrderMutationResult> saveOrder(
    OrderUpsertInput input, {
    bool complete = false,
    bool place = false,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      return const OrderMutationResult.fail('No active session found.');
    }
    final branchId = session.branch?.id;
    if (branchId == null || branchId.isEmpty) {
      return const OrderMutationResult.fail(
        'Select a branch before creating orders.',
      );
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final saved = await _repo.saveOrder(
        input: input,
        companyId: session.company.id,
        branchId: branchId,
        employeeId: session.employee.id,
        complete: complete,
        place: place,
      );
      await loadOrders(showLoading: false);
      if (complete || place) {
        unawaited(refreshHubInventoryQuietly(ref));
        unawaited(refreshHubProductsQuietly(ref));
      }
      state = state.copyWith(isSaving: false, clearError: true);
      return OrderMutationResult.ok(
        confirmation: saved.confirmation,
        orderId: saved.orderId,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return OrderMutationResult.fail(failure.message);
    }
  }

  Future<String?> cancelOrder(OrderSummary order) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.cancelOrder(
        orderId: order.id,
        employeeId: session.employee.id,
      );
      await loadOrders(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<OrderMutationResult> completeExisting(OrderSummary order) async {
    final session = ref.read(currentSessionProvider);
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final confirmation = await _repo.completeOrder(
        order.id,
        companyId: session?.company.id,
        employeeId: session?.employee.id,
      );
      await loadOrders(showLoading: false);
      unawaited(refreshHubInventoryQuietly(ref));
      unawaited(refreshHubProductsQuietly(ref));
      state = state.copyWith(isSaving: false, clearError: true);
      return OrderMutationResult.ok(confirmation: confirmation);
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return OrderMutationResult.fail(failure.message);
    }
  }

  Future<String?> fulfillOrderItems({
    required String orderId,
    required List<({String orderItemId, num quantity})> lines,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.fulfillOrderItems(orderId: orderId, lines: lines);
      await loadOrders(showLoading: false);
      unawaited(refreshHubInventoryQuietly(ref));
      unawaited(refreshHubProductsQuietly(ref));
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  /// Deliver every remaining unit (fulfillment finish; does not settle payment).
  Future<OrderMutationResult> fulfillAllRemaining(OrderSummary order) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final confirmation = await _repo.completeOrder(order.id);
      await loadOrders(showLoading: false);
      unawaited(refreshHubInventoryQuietly(ref));
      unawaited(refreshHubProductsQuietly(ref));
      state = state.copyWith(isSaving: false, clearError: true);
      return OrderMutationResult.ok(confirmation: confirmation);
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return OrderMutationResult.fail(failure.message);
    }
  }

  Future<String?> cancelOrderRemaining(String orderId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.cancelOrderRemaining(orderId: orderId);
      await loadOrders(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> archiveOrder(OrderSummary order) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.archiveOrder(order.id);
      await loadOrders(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }
}

final hubOrdersProvider = NotifierProvider<HubOrdersNotifier, HubOrdersState>(
  HubOrdersNotifier.new,
);
