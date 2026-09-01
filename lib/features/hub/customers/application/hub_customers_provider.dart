import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/customer_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';

enum CustomerStatusFilter { all, active, archived }

enum CustomerTypeFilter { all, retail, wholesale }

class HubCustomersState {
  const HubCustomersState({
    this.items = const [],
    this.search = '',
    this.statusFilter = CustomerStatusFilter.active,
    this.typeFilter = CustomerTypeFilter.all,
    this.page = 0,
    this.pageSize = 20,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<CustomerSummary> items;
  final String search;
  final CustomerStatusFilter statusFilter;
  final CustomerTypeFilter typeFilter;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubCustomersState copyWith({
    List<CustomerSummary>? items,
    String? search,
    CustomerStatusFilter? statusFilter,
    CustomerTypeFilter? typeFilter,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubCustomersState(
      items: items ?? this.items,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      typeFilter: typeFilter ?? this.typeFilter,
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

class HubCustomersNotifier extends Notifier<HubCustomersState> {
  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  @override
  HubCustomersState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(() => loadCustomers(resetPage: true));
    return const HubCustomersState(isLoading: true);
  }

  Future<void> refresh() => loadCustomers(resetPage: true);

  Future<void> loadCustomers({
    bool resetPage = false,
    bool showLoading = true,
  }) async {
    final page = resetPage ? 0 : state.page;
    state = state.copyWith(
      isLoading: showLoading ? true : state.isLoading,
      clearError: true,
      page: page,
      initialized: true,
    );

    try {
      final result = await _repo.fetchCustomers(
        search: state.search,
        isActive: switch (state.statusFilter) {
          CustomerStatusFilter.all => null,
          CustomerStatusFilter.active => true,
          CustomerStatusFilter.archived => false,
        },
        customerType: switch (state.typeFilter) {
          CustomerTypeFilter.all => null,
          CustomerTypeFilter.retail => CustomerType.retail,
          CustomerTypeFilter.wholesale => CustomerType.wholesale,
        },
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
    await loadCustomers(resetPage: true);
  }

  Future<void> setStatusFilter(CustomerStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0);
    await loadCustomers(resetPage: true);
  }

  Future<void> setTypeFilter(CustomerTypeFilter value) async {
    state = state.copyWith(typeFilter: value, page: 0);
    await loadCustomers(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadCustomers();
  }

  Future<String?> saveCustomer(CustomerUpsertInput input) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.upsertCustomer(
        input: input,
        companyId: session.company.id,
        employeeId: session.employee.id,
        branchId: session.branch?.id,
      );
      await loadCustomers(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: failure.message,
      );
      return failure.message;
    }
  }

  Future<String?> setArchived(
    CustomerSummary customer, {
    required bool archived,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.archiveCustomer(
        customerId: customer.id,
        employeeId: session.employee.id,
        archived: archived,
      );
      await loadCustomers();
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: failure.message,
      );
      return failure.message;
    }
  }

  Future<String?> permanentlyDelete(CustomerSummary customer) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';
    if (customer.isActive) {
      return 'Archive the customer before permanently deleting them.';
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.permanentlyDeleteCustomer(
        customerId: customer.id,
        employeeId: session.employee.id,
      );
      await loadCustomers(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: failure.message,
      );
      return failure.message;
    }
  }
}

final hubCustomersProvider =
    NotifierProvider<HubCustomersNotifier, HubCustomersState>(
  HubCustomersNotifier.new,
);
