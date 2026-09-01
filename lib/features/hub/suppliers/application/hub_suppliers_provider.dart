import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/supplier_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/supplier_summary.dart';
import 'package:sello/shared/models/supplier_upsert_input.dart';

enum SupplierStatusFilter { all, active, archived }

class HubSuppliersState {
  const HubSuppliersState({
    this.items = const [],
    this.stats = const SupplierDashboardStats(),
    this.search = '',
    this.statusFilter = SupplierStatusFilter.active,
    this.category,
    this.page = 0,
    this.pageSize = 20,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<SupplierSummary> items;
  final SupplierDashboardStats stats;
  final String search;
  final SupplierStatusFilter statusFilter;

  /// Future-ready category filter (null = all).
  final String? category;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubSuppliersState copyWith({
    List<SupplierSummary>? items,
    SupplierDashboardStats? stats,
    String? search,
    SupplierStatusFilter? statusFilter,
    String? category,
    bool clearCategory = false,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubSuppliersState(
      items: items ?? this.items,
      stats: stats ?? this.stats,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      category: clearCategory ? null : (category ?? this.category),
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

class HubSuppliersNotifier extends Notifier<HubSuppliersState> {
  SupplierRepository get _repo => ref.read(supplierRepositoryProvider);

  @override
  HubSuppliersState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(() => loadSuppliers(resetPage: true));
    return const HubSuppliersState(isLoading: true);
  }

  Future<void> refresh() => loadSuppliers(resetPage: true);

  Future<void> loadSuppliers({
    bool resetPage = false,
    bool showLoading = true,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = state.copyWith(
        items: const [],
        isLoading: false,
        initialized: true,
        errorMessage: 'Sign in required.',
      );
      return;
    }

    final page = resetPage ? 0 : state.page;
    state = state.copyWith(
      isLoading: showLoading ? true : state.isLoading,
      page: page,
      clearError: true,
      initialized: true,
    );

    try {
      final companyId = session.company.id;
      final result = await _repo.fetchSuppliers(
        companyId: companyId,
        search: state.search,
        isActive: switch (state.statusFilter) {
          SupplierStatusFilter.all => null,
          SupplierStatusFilter.active => true,
          SupplierStatusFilter.archived => false,
        },
        category: state.category,
        page: page,
        pageSize: state.pageSize,
      );
      final stats = await _repo.fetchDashboardStats(companyId: companyId);

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        stats: stats,
        isLoading: false,
        clearError: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        items: const [],
        hasMore: false,
        isLoading: false,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await loadSuppliers(resetPage: true, showLoading: false);
  }

  Future<void> setStatusFilter(SupplierStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0);
    await loadSuppliers(resetPage: true);
  }

  Future<void> setCategoryFilter(String? category) async {
    state = state.copyWith(
      category: category,
      clearCategory: category == null || category.isEmpty,
      page: 0,
    );
    await loadSuppliers(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadSuppliers();
  }

  Future<String?> saveSupplier(SupplierUpsertInput input) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.upsertSupplier(
        input: input,
        companyId: session.company.id,
        employeeId: session.employee.id,
        branchId: session.branch?.id,
      );
      await loadSuppliers(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> setArchived(
    SupplierSummary supplier, {
    required bool archived,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.archiveSupplier(
        companyId: session.company.id,
        supplierId: supplier.id,
        employeeId: session.employee.id,
        archived: archived,
      );
      await loadSuppliers(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> permanentlyDelete(SupplierSummary supplier) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';
    if (supplier.isActive) {
      return 'Archive the supplier before permanently deleting them.';
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.permanentlyDeleteSupplier(
        companyId: session.company.id,
        supplierId: supplier.id,
        employeeId: session.employee.id,
      );
      await loadSuppliers(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }
}

final hubSuppliersProvider =
    NotifierProvider<HubSuppliersNotifier, HubSuppliersState>(
  HubSuppliersNotifier.new,
);
