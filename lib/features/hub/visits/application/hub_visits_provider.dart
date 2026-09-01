import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_visit.dart';

class HubVisitsState {
  const HubVisitsState({
    this.loading = true,
    this.error,
    this.stats = const CustomerVisitDayStats(),
    this.visits = const [],
    this.day,
  });

  final bool loading;
  final String? error;
  final CustomerVisitDayStats stats;
  final List<CustomerVisit> visits;
  final DateTime? day;

  HubVisitsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    CustomerVisitDayStats? stats,
    List<CustomerVisit>? visits,
    DateTime? day,
  }) {
    return HubVisitsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      stats: stats ?? this.stats,
      visits: visits ?? this.visits,
      day: day ?? this.day,
    );
  }
}

final hubVisitsProvider =
    NotifierProvider<HubVisitsNotifier, HubVisitsState>(HubVisitsNotifier.new);

class HubVisitsNotifier extends Notifier<HubVisitsState> {
  @override
  HubVisitsState build() {
    Future.microtask(refresh);
    return const HubVisitsState();
  }

  Future<void> refresh({DateTime? day}) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = const HubVisitsState(loading: false);
      return;
    }

    final focus = day ?? state.day ?? DateTime.now();
    final start = DateTime(focus.year, focus.month, focus.day);
    state = state.copyWith(loading: true, clearError: true, day: focus);

    try {
      final repo = ref.read(visitRepositoryProvider);
      final stats = await repo.fetchCustomerVisitDayStats(
        companyId: session.company.id,
        day: focus,
      );
      final visits = await repo.fetchCustomerVisits(
        companyId: session.company.id,
        from: start,
        to: start.add(const Duration(days: 1)),
        limit: 200,
      );
      state = HubVisitsState(
        loading: false,
        stats: stats,
        visits: visits,
        day: focus,
      );
    } on AppFailure catch (error) {
      state = state.copyWith(loading: false, error: error.message);
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'Unable to load visits.',
      );
    }
  }
}
