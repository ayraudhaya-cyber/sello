import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/order_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/order_upsert_input.dart';

/// Field sales orders — same repository as Hub, scoped to the signed-in rep.
class SelloOrdersState {
  const SelloOrdersState({
    this.items = const [],
    this.search = '',
    this.statusFilter = OrderStatus.draft,
    this.page = 0,
    this.pageSize = 40,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
    this.showAllStatuses = false,
  });

  final List<OrderSummary> items;
  final String search;
  final OrderStatus statusFilter;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;
  final bool showAllStatuses;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  SelloOrdersState copyWith({
    List<OrderSummary>? items,
    String? search,
    OrderStatus? statusFilter,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
    bool? showAllStatuses,
  }) {
    return SelloOrdersState(
      items: items ?? this.items,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
      showAllStatuses: showAllStatuses ?? this.showAllStatuses,
    );
  }
}

class SelloOrdersNotifier extends Notifier<SelloOrdersState> {
  OrderRepository get _repo => ref.read(orderRepositoryProvider);

  @override
  SelloOrdersState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(() => loadOrders(resetPage: true));
    return const SelloOrdersState(isLoading: true);
  }

  Future<void> refresh() => loadOrders(resetPage: true);

  Future<void> loadOrders({
    bool resetPage = false,
    bool showLoading = true,
  }) async {
    final session = ref.read(currentSessionProvider);
    final page = resetPage ? 0 : state.page;
    state = state.copyWith(
      isLoading: showLoading ? true : state.isLoading,
      clearError: true,
      page: page,
      initialized: true,
    );

    try {
      final result = await _repo.fetchOrders(
        search: state.search,
        statuses: state.showAllStatuses
            ? null
            : switch (state.statusFilter) {
                OrderStatus.draft => const [
                    OrderStatus.draft,
                    OrderStatus.placed,
                    OrderStatus.partiallyDelivered,
                  ],
                _ => [state.statusFilter],
              },
        employeeId: session?.employee.id,
        page: page,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        isLoading: false,
        clearError: true,
        initialized: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        items: const [],
        hasMore: false,
        isLoading: false,
        errorMessage: failure.message,
        initialized: true,
      );
    }
  }

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await loadOrders(resetPage: true);
  }

  Future<void> setStatusFilter(OrderStatus? value, {bool all = false}) async {
    state = state.copyWith(
      statusFilter: value ?? OrderStatus.draft,
      showAllStatuses: all,
      page: 0,
    );
    await loadOrders(resetPage: true);
  }

  Future<OrderMutationResult> saveOrder(
    OrderUpsertInput input, {
    bool complete = false,
    bool place = false,
    /// Visit finish already navigates away — skip the orders-list round trip.
    bool reloadList = true,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      return const OrderMutationResult.fail('No active session found.');
    }
    final branchId = session.branch?.id ?? session.employee.branchId;
    if (branchId == null || branchId.isEmpty) {
      return const OrderMutationResult.fail(
        'Your account needs a branch before creating orders.',
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
      if (reloadList) {
        await loadOrders(showLoading: false);
      }
      state = state.copyWith(isSaving: false, clearError: true);
      return OrderMutationResult.ok(confirmation: saved.confirmation);
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return OrderMutationResult.fail(failure.message);
    }
  }

  Future<OrderMutationResult> placeExisting(OrderSummary order) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.placeOrder(order.id);
      await loadOrders(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return const OrderMutationResult.ok();
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
      state = state.copyWith(isSaving: false, clearError: true);
      return OrderMutationResult.ok(confirmation: confirmation);
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return OrderMutationResult.fail(failure.message);
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

final selloOrdersProvider =
    NotifierProvider<SelloOrdersNotifier, SelloOrdersState>(
  SelloOrdersNotifier.new,
);
