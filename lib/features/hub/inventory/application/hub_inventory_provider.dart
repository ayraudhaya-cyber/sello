import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/inventory_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/stock_movement_type.dart';

class HubInventoryState {
  const HubInventoryState({
    this.items = const [],
    this.categories = const [],
    this.recentMovements = const [],
    this.stats = const InventoryDashboardStats(
      totalItems: 0,
      lowStock: 0,
      outOfStock: 0,
      recentlyUpdated: 0,
    ),
    this.search = '',
    this.categoryId,
    this.statusFilter = StockStatusFilter.all,
    this.page = 0,
    this.pageSize = 20,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<InventoryItem> items;
  final List<ProductCategory> categories;
  final List<StockMovement> recentMovements;
  final InventoryDashboardStats stats;
  final String search;
  final String? categoryId;
  final StockStatusFilter statusFilter;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubInventoryState copyWith({
    List<InventoryItem>? items,
    List<ProductCategory>? categories,
    List<StockMovement>? recentMovements,
    InventoryDashboardStats? stats,
    String? search,
    String? categoryId,
    bool clearCategory = false,
    StockStatusFilter? statusFilter,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubInventoryState(
      items: items ?? this.items,
      categories: categories ?? this.categories,
      recentMovements: recentMovements ?? this.recentMovements,
      stats: stats ?? this.stats,
      search: search ?? this.search,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      statusFilter: statusFilter ?? this.statusFilter,
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

class HubInventoryNotifier extends Notifier<HubInventoryState> {
  InventoryRepository get _repo => ref.read(inventoryRepositoryProvider);

  @override
  HubInventoryState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(_initialize);
    return const HubInventoryState(isLoading: true);
  }

  String? get _branchId => ref.read(currentSessionProvider)?.branch?.id;

  Future<void> _initialize() async {
    await Future.wait([
      _loadCategories(),
      loadStock(resetPage: true),
    ]);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _repo.fetchCategories();
      state = state.copyWith(categories: categories);
    } on AppFailure {
      // Non-fatal.
    }
  }

  Future<void> refresh() async {
    await Future.wait([
      _loadCategories(),
      loadStock(resetPage: true),
    ]);
  }

  Future<void> loadStock({
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
      final result = await _repo.fetchStock(
        search: state.search,
        categoryId: state.categoryId,
        branchId: _branchId,
        status: state.statusFilter,
        page: page,
        pageSize: state.pageSize,
      );
      final stats = await _repo.fetchDashboardStats(branchId: _branchId);
      List<StockMovement> recent = state.recentMovements;
      try {
        recent = await _repo.fetchRecentMovements(branchId: _branchId);
      } catch (_) {
        // Non-fatal.
      }

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        stats: stats,
        recentMovements: recent,
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
    await loadStock(resetPage: true);
  }

  Future<void> setStatusFilter(StockStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0);
    await loadStock(resetPage: true);
  }

  Future<void> setCategoryFilter(String? categoryId) async {
    state = state.copyWith(
      categoryId: categoryId,
      clearCategory: categoryId == null,
      page: 0,
    );
    await loadStock(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadStock();
  }

  Future<String?> adjustStock(StockAdjustInput input) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.adjustStock(input);
      await loadStock(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<List<StockMovement>> loadMovements(InventoryItem item) {
    return _repo.fetchMovements(
      productId: item.productId,
      branchId: item.branchId,
    );
  }
}

final hubInventoryProvider =
    NotifierProvider<HubInventoryNotifier, HubInventoryState>(
  HubInventoryNotifier.new,
);
