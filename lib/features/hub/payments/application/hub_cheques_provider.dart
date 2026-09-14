import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/cheque_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';

enum ChequeStatusFilter {
  all,
  awaitingCollection,
  pendingApproval,
  collected,
  deposited,
  cleared,
  bounced,
  cancelled,
}

class HubChequesState {
  const HubChequesState({
    this.items = const [],
    this.stats = const ChequeDashboardStats(),
    this.search = '',
    this.statusFilter = ChequeStatusFilter.all,
    this.bankFilter = '',
    this.dueToday = false,
    this.page = 0,
    this.pageSize = 20,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<ChequeSummary> items;
  final ChequeDashboardStats stats;
  final String search;
  final ChequeStatusFilter statusFilter;
  final String bankFilter;
  final bool dueToday;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubChequesState copyWith({
    List<ChequeSummary>? items,
    ChequeDashboardStats? stats,
    String? search,
    ChequeStatusFilter? statusFilter,
    String? bankFilter,
    bool? dueToday,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubChequesState(
      items: items ?? this.items,
      stats: stats ?? this.stats,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      bankFilter: bankFilter ?? this.bankFilter,
      dueToday: dueToday ?? this.dueToday,
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

class HubChequesNotifier extends Notifier<HubChequesState> {
  ChequeRepository get _repo => ref.read(chequeRepositoryProvider);

  @override
  HubChequesState build() {
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

    Future.microtask(() => loadCheques(resetPage: true));
    return const HubChequesState(isLoading: true);
  }

  Future<void> refresh() => loadCheques(resetPage: true);

  Future<void> loadCheques({
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
      final result = await _repo.fetchCheques(
        search: state.search,
        status: switch (state.statusFilter) {
          ChequeStatusFilter.all ||
          ChequeStatusFilter.pendingApproval =>
            null,
          ChequeStatusFilter.awaitingCollection =>
            ChequeStatus.awaitingCollection,
          ChequeStatusFilter.collected => null,
          ChequeStatusFilter.deposited => ChequeStatus.deposited,
          ChequeStatusFilter.cleared => ChequeStatus.cleared,
          ChequeStatusFilter.bounced => ChequeStatus.bounced,
          ChequeStatusFilter.cancelled => ChequeStatus.cancelled,
        },
        pendingApprovalOnly:
            state.statusFilter == ChequeStatusFilter.pendingApproval,
        appliedCollectedOnly:
            state.statusFilter == ChequeStatusFilter.collected,
        bankName: state.bankFilter.trim().isEmpty ? null : state.bankFilter,
        dueToday: state.dueToday,
        page: page,
        pageSize: state.pageSize,
      );
      final stats = await _repo.fetchDashboardStats();

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        stats: stats,
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
    await loadCheques(resetPage: true);
  }

  Future<void> setStatusFilter(ChequeStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0, dueToday: false);
    await loadCheques(resetPage: true);
  }

  Future<void> setBankFilter(String value) async {
    state = state.copyWith(bankFilter: value, page: 0);
    await loadCheques(resetPage: true);
  }

  Future<void> setDueToday(bool value) async {
    state = state.copyWith(
      dueToday: value,
      page: 0,
      statusFilter: value ? ChequeStatusFilter.all : state.statusFilter,
    );
    await loadCheques(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadCheques();
  }

  Future<ChequeSummary?> createCheque(CreateChequeInput input) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repo.createCheque(input);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return result;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return null;
    }
  }

  Future<ChequeSummary?> createExistingCheque(
    CreateExistingChequeInput input,
  ) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repo.createExistingCheque(input);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return result;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return null;
    }
  }

  Future<ChequeSummary?> collectCheque(CollectChequeInput input) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repo.collectCheque(input);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return result;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return null;
    }
  }

  Future<String?> approveChequeCollection(String chequeId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.approveChequeCollection(chequeId);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> depositCheque(String chequeId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.depositCheque(chequeId);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> clearCheque(String chequeId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.clearCheque(chequeId);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> bounceCheque(String chequeId, {String? reason}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.bounceCheque(chequeId, reason: reason);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> cancelCheque(String chequeId, {String? reason}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.cancelCheque(chequeId, reason: reason);
      await loadCheques(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }
}

final hubChequesProvider =
    NotifierProvider<HubChequesNotifier, HubChequesState>(
      HubChequesNotifier.new,
    );
