import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/reliability/backup_service.dart';
import 'package:sello/services/reliability/conflict_detector.dart';
import 'package:sello/services/reliability/connectivity_service.dart';
import 'package:sello/services/reliability/integrity_guard.dart';
import 'package:sello/services/reliability/reliability_diagnostics_service.dart';
import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/services/reliability/restore_service.dart';
import 'package:sello/services/reliability/sync_engine.dart';
import 'package:sello/services/reliability/sync_outbox.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/visits/customer_visits_sync_handler.dart';
import 'package:sello/shared/models/reliability/connectivity_status.dart';
import 'package:sello/shared/models/reliability/reliability_diagnostics.dart';

final reliabilityStoreProvider = Provider<ReliabilityStore>((ref) {
  final store = ReliabilityStore();
  ref.onDispose(() {});
  return store;
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

final syncOutboxProvider = Provider<SyncOutbox>((ref) {
  return SyncOutbox(store: ref.watch(reliabilityStoreProvider));
});

final conflictDetectorProvider = Provider<ConflictDetector>((ref) {
  return ConflictDetector(store: ref.watch(reliabilityStoreProvider));
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    outbox: ref.watch(syncOutboxProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    conflicts: ref.watch(conflictDetectorProvider),
    store: ref.watch(reliabilityStoreProvider),
    events: ref.watch(businessEventBusProvider),
    companyId: () => ref.read(currentSessionProvider)?.company.id ?? '',
    actorEmployeeId: () => ref.read(currentSessionProvider)?.employee.id,
  );
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(store: ref.watch(reliabilityStoreProvider));
});

final restoreServiceProvider = Provider<RestoreService>((ref) {
  return RestoreService(store: ref.watch(reliabilityStoreProvider));
});

final integrityGuardProvider = Provider<IntegrityGuard>((ref) {
  return IntegrityGuard(outbox: ref.watch(syncOutboxProvider));
});

final reliabilityDiagnosticsServiceProvider =
    Provider<ReliabilityDiagnosticsService>((ref) {
  return ReliabilityDiagnosticsService(
    connectivity: ref.watch(connectivityServiceProvider),
    outbox: ref.watch(syncOutboxProvider),
    syncEngine: ref.watch(syncEngineProvider),
    conflicts: ref.watch(conflictDetectorProvider),
    backups: ref.watch(backupServiceProvider),
    restore: ref.watch(restoreServiceProvider),
    integrity: ref.watch(integrityGuardProvider),
    store: ref.watch(reliabilityStoreProvider),
  );
});

/// Live connectivity snapshot for banners / badges across the app.
final connectivitySnapshotProvider =
    StreamProvider<ConnectivitySnapshot>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  await service.start();
  yield service.snapshot;
  yield* service.changes;
});

/// Confidence dashboard for Settings → Reliability.
final reliabilityDiagnosticsProvider =
    FutureProvider.autoDispose<ReliabilityDiagnostics>((ref) async {
  // Refresh when connectivity changes.
  ref.watch(connectivitySnapshotProvider);
  return ref.read(reliabilityDiagnosticsServiceProvider).snapshot();
});

/// Bootstraps connectivity monitoring + auto-sync on app start.
final reliabilityBootstrapProvider = FutureProvider<void>((ref) async {
  final store = ref.read(reliabilityStoreProvider);
  await store.initialize();
  final engine = ref.read(syncEngineProvider);

  // Domain handlers — modules register here; no parallel sync engines.
  void registerVisitHandler() {
    final session = ref.read(currentSessionProvider);
    engine.registerHandler(
      CustomerVisitsSyncHandler(
        visits: ref.read(visitRepositoryProvider),
        companyId: () =>
            ref.read(currentSessionProvider)?.company.id ??
            session?.company.id ??
            '',
        actorEmployeeId: () =>
            ref.read(currentSessionProvider)?.employee.id ??
            session?.employee.id ??
            '',
      ),
    );
  }

  registerVisitHandler();
  ref.listen(currentSessionProvider, (previous, next) {
    if (next != null) registerVisitHandler();
  });

  await engine.start();
  // Automatic backup seam — no-op when recently backed up.
  unawaited(ref.read(backupServiceProvider).runAutomaticIfDue());
});
