import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/payment_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

enum PaymentStatusFilter {
  all,
  completed,
  pending,
  rejected,
  refunded,
  cancelled,
}

enum PaymentMethodFilter {
  all,
  cash,
  card,
  bankTransfer,
  wallet,
  creditSettlement,
}

class HubPaymentsState {
  const HubPaymentsState({
    this.items = const [],
    this.stats = const PaymentDashboardStats(
      collectedToday: 0,
      outstandingReceivables: 0,
      walletIssued: 0,
      pendingCredit: 0,
    ),
    this.pendingReviewCount = 0,
    this.search = '',
    this.statusFilter = PaymentStatusFilter.all,
    this.methodFilter = PaymentMethodFilter.all,
    this.page = 0,
    this.pageSize = 20,
    this.hasMore = false,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<PaymentSummary> items;
  final PaymentDashboardStats stats;
  final int pendingReviewCount;
  final String search;
  final PaymentStatusFilter statusFilter;
  final PaymentMethodFilter methodFilter;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubPaymentsState copyWith({
    List<PaymentSummary>? items,
    PaymentDashboardStats? stats,
    int? pendingReviewCount,
    String? search,
    PaymentStatusFilter? statusFilter,
    PaymentMethodFilter? methodFilter,
    int? page,
    int? pageSize,
    bool? hasMore,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubPaymentsState(
      items: items ?? this.items,
      stats: stats ?? this.stats,
      pendingReviewCount: pendingReviewCount ?? this.pendingReviewCount,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      methodFilter: methodFilter ?? this.methodFilter,
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

class HubPaymentsNotifier extends Notifier<HubPaymentsState> {
  PaymentRepository get _repo => ref.read(paymentRepositoryProvider);

  @override
  HubPaymentsState build() {
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

    Future.microtask(() => loadPayments(resetPage: true));
    return const HubPaymentsState(isLoading: true);
  }

  Future<void> refresh() => loadPayments(resetPage: true);

  Future<void> loadPayments({
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
      final result = await _repo.fetchPayments(
        search: state.search,
        status: switch (state.statusFilter) {
          PaymentStatusFilter.all => null,
          PaymentStatusFilter.completed => PaymentRecordStatus.completed,
          PaymentStatusFilter.pending => PaymentRecordStatus.pending,
          PaymentStatusFilter.rejected => PaymentRecordStatus.rejected,
          PaymentStatusFilter.refunded => PaymentRecordStatus.refunded,
          PaymentStatusFilter.cancelled => PaymentRecordStatus.cancelled,
        },
        method: switch (state.methodFilter) {
          PaymentMethodFilter.all => null,
          PaymentMethodFilter.cash => PaymentMethod.cash,
          PaymentMethodFilter.card => PaymentMethod.card,
          PaymentMethodFilter.bankTransfer => PaymentMethod.bankTransfer,
          PaymentMethodFilter.wallet => PaymentMethod.wallet,
          PaymentMethodFilter.creditSettlement =>
            PaymentMethod.creditSettlement,
        },
        page: page,
        pageSize: state.pageSize,
      );
      final stats = await _repo.fetchDashboardStats();
      final pendingReviewCount = await _repo.countPendingReview();

      state = state.copyWith(
        items: result.items,
        hasMore: result.hasMore,
        stats: stats,
        pendingReviewCount: pendingReviewCount,
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
    await loadPayments(resetPage: true);
  }

  Future<void> setStatusFilter(PaymentStatusFilter value) async {
    state = state.copyWith(statusFilter: value, page: 0);
    await loadPayments(resetPage: true);
  }

  Future<void> setMethodFilter(PaymentMethodFilter value) async {
    state = state.copyWith(methodFilter: value, page: 0);
    await loadPayments(resetPage: true);
  }

  Future<void> goToPage(int page) async {
    state = state.copyWith(page: page);
    await loadPayments();
  }

  Future<ReceivePaymentResult?> receivePayment(
    ReceivePaymentInput input,
  ) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final result = await _repo.receivePayment(input);
      await loadPayments(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return result;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return null;
    }
  }

  Future<String?> approveCollection(String paymentId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.approveCollection(paymentId);
      await loadPayments(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }

  Future<String?> rejectCollection(String paymentId, {String? reason}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.rejectCollection(paymentId, reason: reason);
      await loadPayments(showLoading: false);
      state = state.copyWith(isSaving: false, clearError: true);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false, errorMessage: failure.message);
      return failure.message;
    }
  }
}

final hubPaymentsProvider =
    NotifierProvider<HubPaymentsNotifier, HubPaymentsState>(
      HubPaymentsNotifier.new,
    );
