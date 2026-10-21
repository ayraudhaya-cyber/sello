import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/features/hub/inventory/application/inventory_cross_refresh.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/feedback/sello_activity.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/utils/hub_table_paging.dart';

enum ProductStatusFilter { all, active, inactive }

class HubProductsState implements SelloBusyState {
  const HubProductsState({
    this.items = const [],
    this.categories = const [],
    this.search = '',
    this.categoryId,
    this.statusFilter = ProductStatusFilter.active,
    this.page = 0,
    this.pageSize = kHubTablePageSize,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<ProductSummary> items;
  final List<ProductCategory> categories;
  final String search;
  final String? categoryId;
  final ProductStatusFilter statusFilter;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;

  @override
  bool get isBusy => isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  bool get hasActiveFilters =>
      search.trim().isNotEmpty ||
      categoryId != null ||
      statusFilter != ProductStatusFilter.active;

  HubProductsState copyWith({
    List<ProductSummary>? items,
    List<ProductCategory>? categories,
    String? search,
    String? categoryId,
    ProductStatusFilter? statusFilter,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearCategory = false,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubProductsState(
      items: items ?? this.items,
      categories: categories ?? this.categories,
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

class HubProductsNotifier extends Notifier<HubProductsState> {
  ProductRepository get _repo => ref.read(productRepositoryProvider);

  @override
  HubProductsState build() {
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
    return const HubProductsState(isLoading: true);
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

  Future<void> loadProducts({
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
      final result = await _repo.fetchProducts(
        search: state.search,
        categoryId: state.categoryId,
        branchId: ref.read(currentSessionProvider)?.branch?.id,
        isActive: switch (state.statusFilter) {
          ProductStatusFilter.all => null,
          ProductStatusFilter.active => true,
          ProductStatusFilter.inactive => false,
        },
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

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await loadProducts(resetPage: true);
  }

  Future<void> setStatusFilter(ProductStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0);
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

  Future<void> clearFilters() async {
    state = state.copyWith(
      search: '',
      statusFilter: ProductStatusFilter.active,
      clearCategory: true,
      page: 0,
    );
    await loadProducts(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadProducts();
  }

  /// Saves product + inventory, refreshes the table immediately, then uploads
  /// gallery images in the background so the list isn't blocked on media sync.
  Future<String?> saveProduct({
    required ProductUpsertInput input,
    List<MediaGalleryDraft> gallery = const [],
    void Function(MediaUploadProgress progress)? onMediaProgress,
  }) async {
    final session = ref.read(currentSessionProvider);
    final branchId = session?.branch?.id;
    if (session == null || branchId == null) {
      return 'Your session is missing branch information.';
    }
    if (state.isSaving) {
      return 'Another product is still saving. Wait for it to finish.';
    }

    state = state.copyWith(isSaving: true, clearError: true);
    late final String productId;
    try {
      productId = await _repo.upsertProductRecord(
        input: input,
        companyId: session.company.id,
        employeeId: session.employee.id,
        branchId: branchId,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(errorMessage: failure.message);
      return failure.message;
    } catch (_) {
      const message = 'Could not save this product. Please try again.';
      state = state.copyWith(errorMessage: message);
      return message;
    } finally {
      // Always release the lock. A dropped network call or a non-catalog
      // error used to leave isSaving true for the rest of the session, so
      // every later save showed "another product is still saving".
      state = state.copyWith(isSaving: false);
    }

    try {
      await _loadCategories();
      await loadProducts(showLoading: false);
    } catch (_) {
      // The product row is already saved. A slow catalog reload must not
      // look like a failed save or block the next one.
    }
    unawaited(refreshHubInventoryQuietly(ref));

    final needsMediaSync = gallery.any(
      (d) => d.dirty || d.removed || (d.isNew && d.localBytes != null),
    );
    if (needsMediaSync) {
      final photoError = await _syncGallery(
        companyId: session.company.id,
        employeeId: session.employee.id,
        productId: productId,
        gallery: gallery,
        onMediaProgress: onMediaProgress,
      );
      if (photoError != null) return photoError;
    }
    return null;
  }

  /// Uploads photos before the editor closes, so a slow connection shows
  /// progress instead of looking like a failed save.
  Future<String?> _syncGallery({
    required String companyId,
    required String employeeId,
    required String productId,
    required List<MediaGalleryDraft> gallery,
    void Function(MediaUploadProgress progress)? onMediaProgress,
  }) async {
    try {
      await _repo.syncProductGallery(
        companyId: companyId,
        employeeId: employeeId,
        productId: productId,
        gallery: gallery,
        onMediaProgress: onMediaProgress,
      );
      await loadProducts(showLoading: false);
      return null;
    } on AppFailure catch (failure) {
      return 'Product saved, but photos failed to upload: ${failure.message}';
    } catch (_) {
      return 'Product saved, but photos failed to upload. You can try again.';
    }
  }

  Future<String?> setArchived(
    ProductSummary product, {
    required bool archived,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.archiveProduct(
        productId: product.id,
        employeeId: session.employee.id,
        archived: archived,
      );
      await loadProducts(showLoading: false);
      state = state.copyWith(clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(errorMessage: failure.message);
      return failure.message;
    } catch (_) {
      const message = 'Could not update this product. Please try again.';
      state = state.copyWith(errorMessage: message);
      return message;
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }

  /// Permanently deletes an archived product (soft-delete + purge images).
  Future<String?> permanentlyDelete(ProductSummary product) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'No active session found.';
    if (product.isActive) {
      return 'Deactivate the product before permanently deleting it.';
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.permanentlyDeleteProduct(
        productId: product.id,
        employeeId: session.employee.id,
      );
      await loadProducts(showLoading: false);
      state = state.copyWith(clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(errorMessage: failure.message);
      return failure.message;
    } catch (_) {
      const message = 'Could not delete this product. Please try again.';
      state = state.copyWith(errorMessage: message);
      return message;
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }
}

final hubProductsProvider =
    NotifierProvider<HubProductsNotifier, HubProductsState>(
      HubProductsNotifier.new,
    );
