import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';
import 'package:uuid/uuid.dart';

/// Shared synchronization queue — single outbox for all modules.
class SyncOutbox {
  SyncOutbox({
    required ReliabilityStore store,
    Uuid? uuid,
  })  : _store = store,
        _uuid = uuid ?? const Uuid();

  final ReliabilityStore _store;
  final Uuid _uuid;

  Future<List<SyncQueueItem>> all() => _store.loadQueue();

  Future<List<SyncQueueItem>> openItems() async {
    final items = await all();
    final open = items.where((i) => i.status.isOpen).toList()
      ..sort((a, b) {
        final as = a.sequence ?? 0;
        final bs = b.sequence ?? 0;
        final bySeq = as.compareTo(bs);
        if (bySeq != 0) return bySeq;
        return a.createdAt.compareTo(b.createdAt);
      });
    return open;
  }

  Future<int> pendingCount() async => (await openItems()).length;

  /// Enqueue a mutation. [clientId] is the idempotency key (offline_client_id).
  Future<SyncQueueItem> enqueue({
    required SyncDomain domain,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    String? clientId,
    String? entityId,
    String? companyId,
    DateTime? baseUpdatedAt,
  }) async {
    await _store.initialize();
    final items = await _store.loadQueue();

    final idKey = clientId ?? _uuid.v4();
    // Prevent duplicate processing of the same offline client id.
    final existing = items.where((i) => i.clientId == idKey && i.status.isOpen);
    if (existing.isNotEmpty) {
      return existing.first;
    }

    final sequence = await _store.nextSequence();
    final item = SyncQueueItem(
      id: _uuid.v4(),
      clientId: idKey,
      domain: domain,
      operation: operation,
      payload: payload,
      createdAt: DateTime.now(),
      entityId: entityId,
      companyId: companyId,
      sequence: sequence,
      baseUpdatedAt: baseUpdatedAt,
    );

    await _store.saveQueue([...items, item]);
    return item;
  }

  Future<void> update(SyncQueueItem item) async {
    final items = await _store.loadQueue();
    final next = [
      for (final row in items) row.id == item.id ? item : row,
    ];
    await _store.saveQueue(next);
  }

  Future<void> markCompleted(String id, {String? entityId}) async {
    final items = await _store.loadQueue();
    final next = [
      for (final row in items)
        if (row.id == id)
          row.copyWith(
            status: SyncItemStatus.completed,
            entityId: entityId,
            lastAttemptAt: DateTime.now(),
          )
        else
          row,
    ];
    await _store.saveQueue(next);
  }

  Future<void> markFailed(String id, String error) async {
    final items = await _store.loadQueue();
    final next = [
      for (final row in items)
        if (row.id == id)
          row.copyWith(
            status: SyncItemStatus.failed,
            attempts: row.attempts + 1,
            lastAttemptAt: DateTime.now(),
            lastError: error,
          )
        else
          row,
    ];
    await _store.saveQueue(next);
  }

  Future<void> markConflicted(String id, String message) async {
    final items = await _store.loadQueue();
    final next = [
      for (final row in items)
        if (row.id == id)
          row.copyWith(
            status: SyncItemStatus.conflicted,
            lastAttemptAt: DateTime.now(),
            lastError: message,
          )
        else
          row,
    ];
    await _store.saveQueue(next);
  }

  /// Replace entire queue — used by integrity repair only.
  Future<void> replaceAll(List<SyncQueueItem> items) =>
      _store.saveQueue(items);

  /// Safe retry — only failed / pending items; preserves sequence.
  Future<void> requeueFailed() async {
    final items = await _store.loadQueue();
    final next = [
      for (final row in items)
        if (row.status == SyncItemStatus.failed)
          row.copyWith(status: SyncItemStatus.pending, lastError: null)
        else
          row,
    ];
    await _store.saveQueue(next);
  }
}
