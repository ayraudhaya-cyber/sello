import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/supplier_order_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/supplier_order.dart';

class HubSupplierOrdersState {
  const HubSupplierOrdersState({
    this.items = const [],
    this.search = '',
    this.page = 0,
    this.hasMore = false,
    this.isLoading = false,
    this.initialized = false,
    this.errorMessage,
  });

  final List<SupplierOrderSummary> items;
  final String search;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final bool initialized;
  final String? errorMessage;

  static const pageSize = 20;

  HubSupplierOrdersState copyWith({
    List<SupplierOrderSummary>? items,
    String? search,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? initialized,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HubSupplierOrdersState(
      items: items ?? this.items,
      search: search ?? this.search,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      initialized: initialized ?? this.initialized,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class HubSupplierOrdersNotifier extends Notifier<HubSupplierOrdersState> {
  SupplierOrderRepository get _repo =>
      ref.read(supplierOrderRepositoryProvider);

  @override
  HubSupplierOrdersState build() {
    ref.watch(currentSessionProvider);
    return const HubSupplierOrdersState();
  }

  Future<void> load({bool showLoading = true}) async {
    final session = ref.read(currentSessionProvider);
    final companyId = session?.company.id;
    if (companyId == null) return;
    if (showLoading) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final page = await _repo.fetchPage(
        companyId: companyId,
        search: state.search,
        page: state.page,
        pageSize: HubSupplierOrdersState.pageSize,
      );
      state = state.copyWith(
        items: page.items,
        hasMore: page.hasMore,
        isLoading: false,
        initialized: true,
        clearError: true,
      );
    } on AppFailure catch (error) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        errorMessage: error.message,
      );
    }
  }

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await load();
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page < 0 ? 0 : page);
    await load();
  }
}

final hubSupplierOrdersProvider =
    NotifierProvider<HubSupplierOrdersNotifier, HubSupplierOrdersState>(
      HubSupplierOrdersNotifier.new,
    );
