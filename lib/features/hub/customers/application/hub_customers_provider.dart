import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/customer_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:sello/shared/utils/hub_table_paging.dart';

enum CustomerStatusFilter { all, active, inactive }

enum CustomerTypeFilter { all, retail, wholesale }

/// Server-side table order. [recent] keeps the default (latest updated, or
/// largest balance when filtering to customers who owe).
enum CustomerSort {
  recent(null),
  name('name'),
  outstanding('current_balance'),
  wallet('wallet_balance'),
  lastPurchase('last_purchase_at'),
  updated('updated_at');

  const CustomerSort(this.column);
  final String? column;
}

class HubCustomersState {
  const HubCustomersState({
    this.items = const [],
    this.search = '',
    this.statusFilter = CustomerStatusFilter.active,
    this.typeFilter = CustomerTypeFilter.all,
    this.owingOnly = false,
    this.sort = CustomerSort.recent,
    this.sortAscending = false,
    this.page = 0,
    this.pageSize = kHubTablePageSize,
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

  /// Only customers with an outstanding balance, largest first.
  final bool owingOnly;
  final CustomerSort sort;
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
      statusFilter != CustomerStatusFilter.active ||
      typeFilter != CustomerTypeFilter.all ||
      owingOnly;

  HubCustomersState copyWith({
    List<CustomerSummary>? items,
    String? search,
    CustomerStatusFilter? statusFilter,
    CustomerTypeFilter? typeFilter,
    bool? owingOnly,
    CustomerSort? sort,
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
    return HubCustomersState(
      items: items ?? this.items,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      typeFilter: typeFilter ?? this.typeFilter,
      owingOnly: owingOnly ?? this.owingOnly,
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

class HubCustomersNotifier extends Notifier<HubCustomersState> {
  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  @override
  HubCustomersState build() {
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
    final ledgerChanges = ref
        .watch(paymentRepositoryProvider)
        .changes
        .listen(
          (_) => Future.microtask(() => loadCustomers(showLoading: false)),
        );
    ref.onDispose(ledgerChanges.cancel);

    Future.microtask(() => loadCustomers(resetPage: true));
    return const HubCustomersState(isLoading: true);
  }

  Future<void> refresh() => loadCustomers(resetPage: true);

  int _loadGeneration = 0;

  Future<void> loadCustomers({
    bool resetPage = false,
    bool showLoading = true,
  }) async {
    final generation = ++_loadGeneration;
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
          CustomerStatusFilter.inactive => false,
        },
        customerType: switch (state.typeFilter) {
          CustomerTypeFilter.all => null,
          CustomerTypeFilter.retail => CustomerType.retail,
          CustomerTypeFilter.wholesale => CustomerType.wholesale,
        },
        owingOnly: state.owingOnly,
        orderBy: state.sort.column,
        ascending: state.sortAscending,
        page: page,
        pageSize: state.pageSize,
      );
      if (generation != _loadGeneration) return;

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        isLoading: false,
        clearError: true,
        initialized: true,
      );
    } on AppFailure catch (failure) {
      if (generation != _loadGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
        initialized: true,
      );
    }
  }

  /// Every customer matching the current filters (for Excel export).
  Future<List<CustomerSummary>> fetchAllForExport({int maxRows = 20000}) async {
    const pageSize = 500;
    final rows = <CustomerSummary>[];
    for (var page = 0; rows.length < maxRows; page++) {
      final result = await _repo.fetchCustomers(
        search: state.search,
        isActive: switch (state.statusFilter) {
          CustomerStatusFilter.all => null,
          CustomerStatusFilter.active => true,
          CustomerStatusFilter.inactive => false,
        },
        customerType: switch (state.typeFilter) {
          CustomerTypeFilter.all => null,
          CustomerTypeFilter.retail => CustomerType.retail,
          CustomerTypeFilter.wholesale => CustomerType.wholesale,
        },
        owingOnly: state.owingOnly,
        orderBy: state.sort.column,
        ascending: state.sortAscending,
        page: page,
        pageSize: pageSize,
      );
      rows.addAll(result.items);
      if (!result.hasMore) break;
    }
    return rows;
  }

  /// Tapping the active column flips direction; a new column starts with the
  /// most useful direction (A–Z for names, largest/latest first otherwise).
  Future<void> setSort(CustomerSort sort) async {
    final ascending = state.sort == sort
        ? !state.sortAscending
        : sort == CustomerSort.name;
    state = state.copyWith(sort: sort, sortAscending: ascending, page: 0);
    await loadCustomers(resetPage: true);
  }

  Future<void> setOwingOnly(bool value) async {
    state = state.copyWith(owingOnly: value, page: 0);
    await loadCustomers(resetPage: true);
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

  Future<void> clearFilters() async {
    state = state.copyWith(
      search: '',
      statusFilter: CustomerStatusFilter.active,
      typeFilter: CustomerTypeFilter.all,
      owingOnly: false,
      page: 0,
    );
    await loadCustomers(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadCustomers();
  }

  Future<HubCustomerSaveResult> saveCustomer(CustomerUpsertInput input) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      return const HubCustomerSaveResult.fail('No active session found.');
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final customerId = await _repo.upsertCustomer(
        input: input,
        companyId: session.company.id,
        employeeId: session.employee.id,
        branchId: session.branch?.id,
      );
      await loadCustomers(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return HubCustomerSaveResult.ok(
        customerId: customerId,
        isNew: input.customerId == null,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return HubCustomerSaveResult.fail(failure.message);
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
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> permanentlyDelete(CustomerSummary customer) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';
    if (customer.isActive) {
      return 'Deactivate the customer before permanently deleting them.';
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
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }
}

class HubCustomerSaveResult {
  const HubCustomerSaveResult.ok({
    required this.customerId,
    required this.isNew,
  }) : error = null;

  const HubCustomerSaveResult.fail(this.error)
    : customerId = null,
      isNew = false;

  final String? customerId;
  final String? error;
  final bool isNew;

  bool get isOk => error == null && customerId != null;
}

final hubCustomersProvider =
    NotifierProvider<HubCustomersNotifier, HubCustomersState>(
      HubCustomersNotifier.new,
    );
