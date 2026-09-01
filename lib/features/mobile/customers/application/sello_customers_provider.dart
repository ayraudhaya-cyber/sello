import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/customer_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';

/// Read-only customer lookup for Sales Reps (active customers only).
///
/// Hub owns create/edit/archive. Sales consumes the same [CustomerRepository].
class SelloCustomersState {
  const SelloCustomersState({
    this.items = const [],
    this.search = '',
    this.page = 0,
    this.pageSize = 40,
    this.hasMore = false,
    this.isLoading = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<CustomerSummary> items;
  final String search;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  SelloCustomersState copyWith({
    List<CustomerSummary>? items,
    String? search,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return SelloCustomersState(
      items: items ?? this.items,
      search: search ?? this.search,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

class SelloCustomersNotifier extends Notifier<SelloCustomersState> {
  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  @override
  SelloCustomersState build() {
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
    return const SelloCustomersState(isLoading: true);
  }

  Future<void> refresh() => loadCustomers(resetPage: true);

  Future<void> loadCustomers({bool resetPage = false}) async {
    final page = resetPage ? 0 : state.page;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      page: page,
      initialized: true,
    );

    try {
      final result = await _repo.fetchCustomers(
        search: state.search,
        isActive: true,
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
}

final selloCustomersProvider =
    NotifierProvider<SelloCustomersNotifier, SelloCustomersState>(
  SelloCustomersNotifier.new,
);
