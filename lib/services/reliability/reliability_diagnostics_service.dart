import 'package:sello/services/reliability/backup_service.dart';
import 'package:sello/services/reliability/conflict_detector.dart';
import 'package:sello/services/reliability/connectivity_service.dart';
import 'package:sello/services/reliability/integrity_guard.dart';
import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/services/reliability/restore_service.dart';
import 'package:sello/services/reliability/sync_engine.dart';
import 'package:sello/services/reliability/sync_outbox.dart';
import 'package:sello/shared/models/reliability/reliability_diagnostics.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// Aggregates sync health, backup status, and recovery for the Reliability page.
class ReliabilityDiagnosticsService {
  ReliabilityDiagnosticsService({
    required ConnectivityService connectivity,
    required SyncOutbox outbox,
    required SyncEngine syncEngine,
    required ConflictDetector conflicts,
    required BackupService backups,
    required RestoreService restore,
    required IntegrityGuard integrity,
    required ReliabilityStore store,
  })  : _connectivity = connectivity,
        _outbox = outbox,
        _syncEngine = syncEngine,
        _conflicts = conflicts,
        _backups = backups,
        _restore = restore,
        _integrity = integrity,
        _store = store;

  final ConnectivityService _connectivity;
  final SyncOutbox _outbox;
  final SyncEngine _syncEngine;
  final ConflictDetector _conflicts;
  final BackupService _backups;
  final RestoreService _restore;
  final IntegrityGuard _integrity;
  final ReliabilityStore _store;

  SyncEngine get syncEngine => _syncEngine;
  BackupService get backups => _backups;
  RestoreService get restore => _restore;
  IntegrityGuard get integrity => _integrity;
  ConnectivityService get connectivity => _connectivity;

  Future<ReliabilityDiagnostics> snapshot({String? deviceLabel}) async {
    await _store.initialize();
    await _integrity.dedupeOpenItems();

    final open = await _outbox.openItems();
    final conflictList = await _conflicts.openConflicts();
    final history = await _backups.history();
    final lastBackup = await _backups.lastSuccessful();
    final backupHealth = await _backups.health();
    final lastSync = await _store.lastSyncAt();
    final activeRestore = await _restore.activeSession();

    final failed = open
        .where((i) =>
            i.status == SyncItemStatus.failed ||
            i.status == SyncItemStatus.conflicted)
        .length;

    return ReliabilityDiagnostics(
      connectivity: _connectivity.snapshot,
      pendingSyncCount: open.length,
      failedSyncCount: failed,
      conflictCount: conflictList.length,
      lastSyncAt: lastSync,
      lastSuccessfulBackup: lastBackup,
      backupHealth: backupHealth,
      deviceLabel: deviceLabel ?? 'This device',
      openSyncItems: open.take(5).toList(),
      recentBackups: history.take(5).toList(),
      activeRestore: activeRestore,
    );
  }
}
