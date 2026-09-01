import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/reliability/backup_models.dart';
import 'package:sello/shared/models/reliability/connectivity_status.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// Confidence-oriented Reliability page model — not a debug console.
class ReliabilityDiagnostics extends Equatable {
  const ReliabilityDiagnostics({
    required this.connectivity,
    required this.pendingSyncCount,
    required this.failedSyncCount,
    required this.conflictCount,
    this.lastSyncAt,
    this.lastSuccessfulBackup,
    this.backupHealth = BackupHealth.unknown,
    this.deviceLabel,
    this.openSyncItems = const [],
    this.recentBackups = const [],
    this.activeRestore,
  });

  final ConnectivitySnapshot connectivity;
  final int pendingSyncCount;
  final int failedSyncCount;
  final int conflictCount;
  final DateTime? lastSyncAt;
  final BackupRecord? lastSuccessfulBackup;
  final BackupHealth backupHealth;
  final String? deviceLabel;
  final List<SyncQueueItem> openSyncItems;
  final List<BackupRecord> recentBackups;
  final RestoreSession? activeRestore;

  String get syncHealthLabel {
    if (connectivity.status == ConnectivityStatus.syncFailed ||
        failedSyncCount > 0) {
      return 'Needs attention';
    }
    if (pendingSyncCount > 0) return 'Catching up';
    if (connectivity.status == ConnectivityStatus.offline) {
      return 'Protected offline';
    }
    return 'Healthy';
  }

  String get backupStatusLabel {
    final last = lastSuccessfulBackup;
    if (last == null) return 'No backup yet';
    return 'Last backup ${ _relative(last.completedAt ?? last.createdAt) }';
  }

  static String _relative(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        connectivity,
        pendingSyncCount,
        failedSyncCount,
        conflictCount,
        lastSyncAt,
        lastSuccessfulBackup,
        backupHealth,
        deviceLabel,
        openSyncItems,
        recentBackups,
        activeRestore,
      ];
}
