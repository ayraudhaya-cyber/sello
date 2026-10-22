import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/order_return_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/feedback/sello_activity.dart';
import 'package:sello/shared/models/order_return.dart';
import 'package:sello/shared/utils/hub_table_paging.dart';

class HubReturnsState implements SelloBusyState {
  const HubReturnsState({
    this.items = const [],
    this.search = '',
    this.page = 0,
    this.pageSize = kHubTablePageSize,
    this.hasMore = false,
    this.isLoading = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<OrderReturnSummary> items;
  final String search;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final String? errorMessage;
  final bool initialized;

  @override
  bool get isBusy => false;

  bool get isEmpty => initialized && !isLoading && items.isEmpty;

  HubReturnsState copyWith({
    List<OrderReturnSummary>? items,
    String? search,
    int? page,
    bool? hasMore,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubReturnsState(
      items: items ?? this.items,
      search: search ?? this.search,
      page: page ?? this.page,
      pageSize: pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      initialized: initialized ?? this.initialized,
    );
  }
}

class HubReturnsNotifier extends Notifier<HubReturnsState> {
  OrderReturnRepository get _repo => ref.read(orderReturnRepositoryProvider);

  @override
  HubReturnsState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey = next == null
          ? null
          : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      state = const HubReturnsState();
    });
    return const HubReturnsState();
  }

  Future<void> load({bool showLoading = true}) async {
    state = state.copyWith(
      isLoading: showLoading || !state.initialized,
      clearError: true,
    );
    try {
      final page = await _repo.fetchPage(
        search: state.search,
        page: state.page,
        pageSize: state.pageSize,
      );
      state = state.copyWith(
        items: page.items,
        hasMore: page.hasMore,
        isLoading: false,
        initialized: true,
        clearError: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value, page: 0);
    await load();
  }

  Future<void> goToPage(int page) async {
    if (page < 0) return;
    state = state.copyWith(page: page);
    await load();
  }
}

final hubReturnsProvider = NotifierProvider<HubReturnsNotifier, HubReturnsState>(
  HubReturnsNotifier.new,
);
