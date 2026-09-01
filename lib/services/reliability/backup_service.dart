import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/shared/models/reliability/backup_models.dart';
import 'package:uuid/uuid.dart';

/// Modern backup architecture — confidence, not database exports.
///
/// Future: cloud backup, incremental snapshots, disaster recovery.
class BackupService {
  BackupService({
    required ReliabilityStore store,
    Uuid? uuid,
  })  : _store = store,
        _uuid = uuid ?? const Uuid();

  final ReliabilityStore _store;
  final Uuid _uuid;

  Future<List<BackupRecord>> history({int limit = 20}) async {
    await _store.initialize();
    final all = await _store.loadBackups();
    return all.take(limit).toList();
  }

  Future<BackupRecord?> lastSuccessful() async {
    final all = await history();
    for (final row in all) {
      if (row.isSuccessful) return row;
    }
    return null;
  }

  Future<BackupHealth> health() async {
    final last = await lastSuccessful();
    if (last == null) return BackupHealth.unknown;
    final age = DateTime.now().difference(last.completedAt ?? last.createdAt);
    if (age.inDays > 14) return BackupHealth.attention;
    return last.health == BackupHealth.failed
        ? BackupHealth.failed
        : BackupHealth.healthy;
  }

  /// Manual safeguard — records a completed local backup marker.
  ///
  /// Cloud upload / incremental payload lands in a later phase.
  Future<BackupRecord> createManualBackup({String? label}) async {
    await _store.initialize();
    final now = DateTime.now();
    var record = BackupRecord(
      id: _uuid.v4(),
      createdAt: now,
      kind: BackupKind.manual,
      status: BackupRecordStatus.preparing,
      label: label ?? 'Manual safeguard',
      health: BackupHealth.unknown,
    );

    final history = await _store.loadBackups();
    await _store.saveBackups([record, ...history]);

    // Foundation: mark complete locally. Cloud sync is a future seam.
    record = record.copyWith(
      status: BackupRecordStatus.completed,
      completedAt: DateTime.now(),
      health: BackupHealth.healthy,
      sizeBytes: 0,
    );
    final updated = [
      record,
      ...history,
    ];
    await _store.saveBackups(updated);
    await _store.setLastBackupAt(record.completedAt!);
    return record;
  }

  /// Automatic backup seam — scheduler / background worker later.
  Future<BackupRecord?> runAutomaticIfDue({
    Duration interval = const Duration(days: 1),
  }) async {
    final lastAt = await _store.lastBackupAt();
    if (lastAt != null && DateTime.now().difference(lastAt) < interval) {
      return null;
    }

    await _store.initialize();
    final now = DateTime.now();
    final record = BackupRecord(
      id: _uuid.v4(),
      createdAt: now,
      kind: BackupKind.automatic,
      status: BackupRecordStatus.completed,
      completedAt: now,
      label: 'Automatic safeguard',
      health: BackupHealth.healthy,
      sizeBytes: 0,
    );
    final history = await _store.loadBackups();
    await _store.saveBackups([record, ...history]);
    await _store.setLastBackupAt(now);
    return record;
  }
}
