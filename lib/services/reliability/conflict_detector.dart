import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/shared/models/reliability/conflict_models.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';
import 'package:uuid/uuid.dart';

/// Detects conflicts via optimistic timestamp comparison.
///
/// Full user-facing resolution is intentionally deferred.
class ConflictDetector {
  ConflictDetector({
    required ReliabilityStore store,
    Uuid? uuid,
  })  : _store = store,
        _uuid = uuid ?? const Uuid();

  final ReliabilityStore _store;
  final Uuid _uuid;

  /// Returns a conflict when the server entity moved after [item.baseUpdatedAt].
  SyncConflict? detectTimestampConflict({
    required SyncQueueItem item,
    required DateTime? serverUpdatedAt,
  }) {
    final base = item.baseUpdatedAt;
    if (base == null || serverUpdatedAt == null) return null;
    if (!serverUpdatedAt.isAfter(base)) return null;

    return SyncConflict(
      id: _uuid.v4(),
      queueItemId: item.id,
      domain: item.domain,
      detectedAt: DateTime.now(),
      strategy: ConflictDetectionStrategy.optimisticTimestamp,
      entityId: item.entityId,
      clientUpdatedAt: base,
      serverUpdatedAt: serverUpdatedAt,
      summary:
          '${item.domain.label} changed on another device while this update '
          'was waiting to sync.',
    );
  }

  Future<void> record(SyncConflict conflict) async {
    final existing = await _store.loadConflicts();
    await _store.saveConflicts([...existing, conflict]);
  }

  Future<List<SyncConflict>> openConflicts() => _store.loadConflicts();
}
