import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/analytics/analytics_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/report_models.dart';

class HubReportsState {
  const HubReportsState({
    this.overview,
    this.query = const ReportQuery(),
    this.categoryFilter,
    this.isLoading = false,
    this.isExporting = false,
    this.errorMessage,
    this.exportMessage,
    this.initialized = false,
  });

  final ReportsOverview? overview;
  final ReportQuery query;

  /// null = all available categories on the catalog strip.
  final ReportCategory? categoryFilter;
  final bool isLoading;
  final bool isExporting;
  final String? errorMessage;
  final String? exportMessage;
  final bool initialized;

  ReportDatePreset get preset => query.preset;

  HubReportsState copyWith({
    ReportsOverview? overview,
    ReportQuery? query,
    ReportCategory? categoryFilter,
    bool clearCategory = false,
    bool? isLoading,
    bool? isExporting,
    String? errorMessage,
    bool clearError = false,
    String? exportMessage,
    bool clearExport = false,
    bool? initialized,
  }) {
    return HubReportsState(
      overview: overview ?? this.overview,
      query: query ?? this.query,
      categoryFilter:
          clearCategory ? null : (categoryFilter ?? this.categoryFilter),
      isLoading: isLoading ?? this.isLoading,
      isExporting: isExporting ?? this.isExporting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      exportMessage: clearExport ? null : exportMessage ?? this.exportMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

class HubReportsNotifier extends Notifier<HubReportsState> {
  AnalyticsService get _analytics => ref.read(analyticsServiceProvider);

  @override
  HubReportsState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.branch?.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.branch?.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(refresh);
    return const HubReportsState(isLoading: true);
  }

  Future<void> refresh() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = state.copyWith(
        isLoading: false,
        initialized: true,
        errorMessage: 'Sign in required.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true, initialized: true);
    try {
      final query = state.query.copyWith(
        branchId: session.branch?.id ?? state.query.branchId,
      );
      final overview = await _analytics.fetchOverview(
        companyId: session.company.id,
        query: query,
      );
      state = state.copyWith(
        overview: overview,
        query: query,
        isLoading: false,
        clearError: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      );
    }
  }

  Future<void> setQuery(ReportQuery query) async {
    if (state.query == query) return;
    final prev = state.query;
    final needsReload = prev.preset != query.preset ||
        prev.customFrom != query.customFrom ||
        prev.customTo != query.customTo ||
        prev.branchId != query.branchId ||
        prev.employeeId != query.employeeId ||
        prev.customerId != query.customerId ||
        prev.supplierId != query.supplierId ||
        prev.categoryId != query.categoryId ||
        prev.status != query.status ||
        prev.comparison != query.comparison;
    state = state.copyWith(query: query);
    if (needsReload) await refresh();
  }

  Future<void> setPreset(ReportDatePreset preset) async {
    await setQuery(state.query.copyWith(preset: preset, clearCustom: true));
  }

  void setCategoryFilter(ReportCategory? category) {
    state = state.copyWith(
      categoryFilter: category,
      clearCategory: category == null,
    );
  }

  Future<String?> requestExport({
    required String reportId,
    required ReportExportFormat format,
  }) async {
    state = state.copyWith(isExporting: true, clearExport: true);
    try {
      final message = await _analytics.prepareExport(
        ReportExportRequest(
          reportId: reportId,
          format: format,
          preset: state.query.preset,
          branchId: state.query.branchId,
          query: state.query,
        ),
      );
      state = state.copyWith(isExporting: false, exportMessage: message);
      return message;
    } on AppFailure catch (failure) {
      state = state.copyWith(isExporting: false, errorMessage: failure.message);
      return failure.message;
    }
  }
}

final hubReportsProvider =
    NotifierProvider<HubReportsNotifier, HubReportsState>(
  HubReportsNotifier.new,
);

final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => AnalyticsService(reports: ref.watch(reportRepositoryProvider)),
);
