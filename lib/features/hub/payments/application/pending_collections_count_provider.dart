import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';

/// Collections waiting for Owner / Manager approval. Drives the Payments nav
/// badge and the dashboard "Needs attention" row so approvals are never
/// missed. Refreshes on sign-in, every few minutes, and whenever Payments
/// reloads or a collection is approved / rejected.
class PendingCollectionsCountNotifier extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous?.employee.id == next?.employee.id) return;
      Future.microtask(refresh);
    });
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => refresh());
    final ledgerChanges = ref
        .watch(paymentRepositoryProvider)
        .changes
        .listen((_) => refresh());
    ref.onDispose(() {
      _timer?.cancel();
      ledgerChanges.cancel();
    });
    Future.microtask(refresh);
    return 0;
  }

  void set(int value) {
    if (state != value) state = value;
  }

  Future<void> refresh() async {
    if (ref.read(currentSessionProvider) == null) {
      set(0);
      return;
    }
    try {
      set(await ref.read(paymentRepositoryProvider).countPendingReview());
    } catch (_) {
      // Badge is a hint only; keep the last known value.
    }
  }
}

final pendingCollectionsCountProvider =
    NotifierProvider<PendingCollectionsCountNotifier, int>(
      PendingCollectionsCountNotifier.new,
    );
