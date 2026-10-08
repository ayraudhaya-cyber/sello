import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/product_summary.dart';

/// Read-only catalog for sales-rep presentation (active products only).
///
/// Hub creates/edits products; this surface consumes the same
/// [ProductRepository] so updates flow without duplication.
class SelloCatalogState {
  const SelloCatalogState({
    this.items = const [],
    this.categories = const [],
    this.search = '',
    this.categoryId,
    this.page = 0,
    this.pageSize = 40,
    this.hasMore = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<ProductSummary> items;
  final List<ProductCategory> categories;
  final String search;
  final String? categoryId;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  SelloCatalogState copyWith({
    List<ProductSummary>? items,
    List<ProductCategory>? categories,
    String? search,
    String? categoryId,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearCategory = false,
    bool clearError = false,
    bool? initialized,
  }) {
    return SelloCatalogState(
      items: items ?? this.items,
      categories: categories ?? this.categories,
      search: search ?? this.search,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

class SelloCatalogNotifier extends Notifier<SelloCatalogState> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  SelloCatalogState build() {
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
    return const SelloCatalogState(isLoading: true);
  }

  Future<void> _initialize() async {
    await Future.wait([_loadCategories(), loadProducts(resetPage: true)]);
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _repo.fetchCategories();
      state = state.copyWith(
        categories: categories,
        clearError: true,
        initialized: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(errorMessage: failure.message, initialized: true);
    }
  }

  Future<void> refresh() async {
    await Future.wait([_loadCategories(), loadProducts(resetPage: true)]);
  }

  int _loadGeneration = 0;

  String? get _branchId {
    final session = ref.read(currentSessionProvider);
    return session?.branch?.id ?? session?.employee.branchId;
  }

  Future<void> loadProducts({bool resetPage = false}) async {
    final generation = ++_loadGeneration;
    final page = resetPage ? 0 : state.page;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      page: page,
      initialized: true,
    );

    try {
      final result = await _repo.fetchProducts(
        search: state.search,
        categoryId: state.categoryId,
        isActive: true,
        branchId: _branchId,
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

  /// Appends the next page (infinite scroll).
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading || state.isLoadingMore) return;
    final generation = _loadGeneration;
    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true);
    try {
      final result = await _repo.fetchProducts(
        search: state.search,
        categoryId: state.categoryId,
        isActive: true,
        branchId: _branchId,
        page: nextPage,
        pageSize: state.pageSize,
      );
      if (generation != _loadGeneration) return;
      final seen = {for (final p in state.items) p.id};
      state = state.copyWith(
        items: [
          ...state.items,
          for (final p in result.items)
            if (!seen.contains(p.id)) p,
        ],
        page: nextPage,
        hasMore: result.hasMore,
        isLoadingMore: false,
      );
    } on AppFailure {
      if (generation != _loadGeneration) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await loadProducts(resetPage: true);
  }

  Future<void> setCategoryFilter(String? value) async {
    state = state.copyWith(
      categoryId: value,
      page: 0,
      clearCategory: value == null,
    );
    await loadProducts(resetPage: true);
  }
}

final selloCatalogProvider =
    NotifierProvider<SelloCatalogNotifier, SelloCatalogState>(
      SelloCatalogNotifier.new,
    );
