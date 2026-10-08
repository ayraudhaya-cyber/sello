import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/payment_summary.dart';

/// A Sales Rep's own collections (money they recorded), from the shared
/// payments ledger. Same repository as Hub; scoped to the signed-in employee.
class SelloCollectionsState {
  const SelloCollectionsState({
    this.period = CollectionsPeriod.thisMonth,
    this.items = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  final CollectionsPeriod period;
  final List<PaymentSummary> items;
  final bool isLoading;
  final String? errorMessage;

  CollectionsSummary get summary => CollectionsSummary.of(items);

  SelloCollectionsState copyWith({
    CollectionsPeriod? period,
    List<PaymentSummary>? items,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SelloCollectionsState(
      period: period ?? this.period,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class SelloCollectionsNotifier extends Notifier<SelloCollectionsState> {
  @override
  SelloCollectionsState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous?.employee.id == next?.employee.id) return;
      Future.microtask(refresh);
    });
    final ledgerChanges = ref
        .watch(paymentRepositoryProvider)
        .changes
        .listen((_) => Future.microtask(refresh));
    ref.onDispose(ledgerChanges.cancel);
    Future.microtask(refresh);
    return const SelloCollectionsState();
  }

  Future<void> refresh() => _load();

  Future<void> setPeriod(CollectionsPeriod period) async {
    state = state.copyWith(period: period);
    await _load();
  }

  int _loadGeneration = 0;

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = state.copyWith(items: const [], isLoading: false);
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final range = state.period.range();
      final rows = await ref
          .read(paymentRepositoryProvider)
          .fetchCollections(
            employeeId: session.employee.id,
            from: range.from,
            before: range.before,
            includeRejected: true,
          );
      if (generation != _loadGeneration) return;
      state = state.copyWith(items: rows, isLoading: false, clearError: true);
    } on AppFailure catch (failure) {
      if (generation != _loadGeneration) return;
      state = state.copyWith(isLoading: false, errorMessage: failure.message);
    }
  }
}

final selloCollectionsProvider =
    NotifierProvider<SelloCollectionsNotifier, SelloCollectionsState>(
      SelloCollectionsNotifier.new,
    );
