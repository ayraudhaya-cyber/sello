import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/visit_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/scheduled_visit.dart';

enum ScheduleViewMode { day, week, list, calendar }

enum VisitStatusFilter { all, scheduled, completed, missed, cancelled, unplanned }

class HubScheduleState {
  const HubScheduleState({
    this.items = const [],
    this.reps = const [],
    this.stats = const VisitDashboardStats(),
    this.focusDate,
    this.viewMode = ScheduleViewMode.day,
    this.search = '',
    this.statusFilter = VisitStatusFilter.all,
    this.employeeId,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<ScheduledVisit> items;
  final List<SalesRepOption> reps;
  final VisitDashboardStats stats;
  final DateTime? focusDate;
  final ScheduleViewMode viewMode;
  final String search;
  final VisitStatusFilter statusFilter;
  final String? employeeId;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final bool initialized;

  DateTime get day => focusDate ?? DateTime.now();

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  HubScheduleState copyWith({
    List<ScheduledVisit>? items,
    List<SalesRepOption>? reps,
    VisitDashboardStats? stats,
    DateTime? focusDate,
    ScheduleViewMode? viewMode,
    String? search,
    VisitStatusFilter? statusFilter,
    String? employeeId,
    bool clearEmployee = false,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return HubScheduleState(
      items: items ?? this.items,
      reps: reps ?? this.reps,
      stats: stats ?? this.stats,
      focusDate: focusDate ?? this.focusDate,
      viewMode: viewMode ?? this.viewMode,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

final hubScheduleProvider =
    NotifierProvider<HubScheduleNotifier, HubScheduleState>(
  HubScheduleNotifier.new,
);

class HubScheduleNotifier extends Notifier<HubScheduleState> {
  VisitRepository get _repo => ref.read(visitRepositoryProvider);

  @override
  HubScheduleState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    final today = DateTime.now();
    Future.microtask(_initialize);
    return HubScheduleState(
      isLoading: true,
      focusDate: DateTime(today.year, today.month, today.day),
    );
  }

  Future<void> _initialize() async {
    await Future.wait([
      loadReps(),
      loadVisits(),
    ]);
  }

  Future<void> refresh() => Future.wait([
        loadReps(),
        loadVisits(),
      ]);

  Future<void> loadReps() async {
    try {
      // Field-visit assignees only — IAM canPerformFieldVisits (not Hub roles).
      final reps =
          await ref.read(orderRepositoryProvider).fetchFieldVisitAssignees();
      state = state.copyWith(reps: reps);
    } catch (_) {
      // Rep filter stays empty; visit load still works.
    }
  }

  ({DateTime from, DateTime to}) _rangeForView(DateTime focus) {
    final day = DateTime(focus.year, focus.month, focus.day);
    switch (state.viewMode) {
      case ScheduleViewMode.day:
        return (from: day, to: day);
      case ScheduleViewMode.week:
        final monday = day.subtract(Duration(days: day.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return (from: monday, to: sunday);
      case ScheduleViewMode.calendar:
        final first = DateTime(day.year, day.month, 1);
        final last = DateTime(day.year, day.month + 1, 0);
        return (from: first, to: last);
      case ScheduleViewMode.list:
        final from = day.subtract(const Duration(days: 7));
        final to = day.add(const Duration(days: 30));
        return (from: from, to: to);
    }
  }

  VisitStatus? get _statusDb {
    return switch (state.statusFilter) {
      VisitStatusFilter.all => null,
      VisitStatusFilter.scheduled => VisitStatus.scheduled,
      VisitStatusFilter.completed => VisitStatus.completed,
      VisitStatusFilter.missed => VisitStatus.missed,
      VisitStatusFilter.cancelled => VisitStatus.cancelled,
      VisitStatusFilter.unplanned => VisitStatus.unplanned,
    };
  }

  Future<void> loadVisits({bool showLoading = true}) async {
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

    state = state.copyWith(
      isLoading: showLoading ? true : state.isLoading,
      clearError: true,
      initialized: true,
    );

    try {
      final range = _rangeForView(state.day);
      final companyId = session.company.id;
      final result = await _repo.fetchVisits(
        companyId: companyId,
        from: range.from,
        to: range.to,
        employeeId: state.employeeId,
        status: _statusDb,
        search: state.search,
        pageSize: 500,
      );
      final stats = await _repo.fetchDashboardStats(
        companyId: companyId,
        day: state.day,
      );

      state = state.copyWith(
        items: result.items,
        stats: stats,
        isLoading: false,
        clearError: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        items: const [],
        isLoading: false,
        errorMessage: failure.message,
      );
    } catch (_) {
      state = state.copyWith(
        items: const [],
        isLoading: false,
        errorMessage: 'Unable to load schedule.',
      );
    }
  }

  void setViewMode(ScheduleViewMode mode) {
    if (state.viewMode == mode) return;
    state = state.copyWith(viewMode: mode);
    loadVisits();
  }

  void setFocusDate(DateTime date) {
    final next = DateTime(date.year, date.month, date.day);
    state = state.copyWith(focusDate: next);
    loadVisits();
  }

  void shiftFocus(int days) {
    setFocusDate(state.day.add(Duration(days: days)));
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
    loadVisits(showLoading: false);
  }

  void setStatusFilter(VisitStatusFilter filter) {
    if (state.statusFilter == filter) return;
    state = state.copyWith(statusFilter: filter);
    loadVisits();
  }

  void setEmployeeFilter(String? employeeId) {
    state = state.copyWith(
      employeeId: employeeId,
      clearEmployee: employeeId == null,
    );
    loadVisits();
  }

  Future<String?> saveVisit(VisitUpsertInput input) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.upsertVisit(
        input: input,
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        branchId: session.branch?.id ?? input.branchId,
      );
      await loadVisits(showLoading: false);
      state = state.copyWith(isSaving: false);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false);
      return failure.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to save this visit.';
    }
  }

  /// Plan a day scope — customer stops, an area assignment, or both.
  Future<String?> saveVisits(List<VisitUpsertInput> inputs) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';
    if (inputs.isEmpty) {
      return 'Add customers or choose an area to plan this visit.';
    }

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.upsertVisits(
        inputs: inputs,
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        branchId: session.branch?.id ?? inputs.first.branchId,
      );
      await loadVisits(showLoading: false);
      state = state.copyWith(isSaving: false);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false);
      return failure.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to plan these visits.';
    }
  }

  Future<String?> setStatus({
    required String visitId,
    required VisitStatus status,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.setVisitStatus(
        companyId: session.company.id,
        visitId: visitId,
        actorEmployeeId: session.employee.id,
        status: status,
      );
      await loadVisits(showLoading: false);
      state = state.copyWith(isSaving: false);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false);
      return failure.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to update visit status.';
    }
  }

  Future<String?> removeVisit(String visitId) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Sign in required.';

    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.softDeleteVisit(
        companyId: session.company.id,
        visitId: visitId,
        actorEmployeeId: session.employee.id,
      );
      await loadVisits(showLoading: false);
      state = state.copyWith(isSaving: false);
      return null;
    } on AppFailure catch (failure) {
      state = state.copyWith(isSaving: false);
      return failure.message;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return 'Unable to remove this visit.';
    }
  }
}
