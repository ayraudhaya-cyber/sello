import 'dart:async';

import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/reliability/conflict_detector.dart';
import 'package:sello/services/reliability/connectivity_service.dart';
import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/services/reliability/sync_handler.dart';
import 'package:sello/services/reliability/sync_outbox.dart';
import 'package:sello/shared/models/reliability/conflict_models.dart';
import 'package:sello/shared/models/reliability/connectivity_status.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';
import 'package:uuid/uuid.dart';

/// Shared synchronization engine — drains the outbox in order.
///
/// Future: background sync, selective sync, multi-device coordination.
class SyncEngine {
  SyncEngine({
    required SyncOutbox outbox,
    required ConnectivityService connectivity,
    required ConflictDetector conflicts,
    required ReliabilityStore store,
    BusinessEventBus? events,
    String Function()? companyId,
    String? Function()? actorEmployeeId,
    Uuid? uuid,
  })  : _outbox = outbox,
        _connectivity = connectivity,
        _conflicts = conflicts,
        _store = store,
        _events = events,
        _companyId = companyId,
        _actorEmployeeId = actorEmployeeId,
        _uuid = uuid ?? const Uuid();

  final SyncOutbox _outbox;
  final ConnectivityService _connectivity;
  final ConflictDetector _conflicts;
  final ReliabilityStore _store;
  final BusinessEventBus? _events;
  final String Function()? _companyId;
  final String? Function()? _actorEmployeeId;
  final Uuid _uuid;

  final Map<SyncDomain, SyncHandler> _handlers = {};
  bool _draining = false;
  StreamSubscription<ConnectivitySnapshot>? _connectivitySub;

  bool get isDraining => _draining;

  void registerHandler(SyncHandler handler) {
    _handlers[handler.domain] = handler;
  }

  /// Start listening for reconnect → auto sync.
  Future<void> start() async {
    await _connectivity.start();
    await _store.initialize();
    _connectivitySub ??= _connectivity.changes.listen((snap) {
      if (snap.transportOnline) {
        unawaited(syncNow(reason: 'connectivity_restored'));
      }
    });
    if (_connectivity.snapshot.transportOnline) {
      unawaited(syncNow(reason: 'startup'));
    }
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Enqueue then attempt sync when reachable.
  Future<SyncQueueItem> enqueue({
    required SyncDomain domain,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    String? clientId,
    String? entityId,
    String? companyId,
    DateTime? baseUpdatedAt,
  }) async {
    final item = await _outbox.enqueue(
      domain: domain,
      operation: operation,
      payload: payload,
      clientId: clientId,
      entityId: entityId,
      companyId: companyId,
      baseUpdatedAt: baseUpdatedAt,
    );

    if (_connectivity.snapshot.transportOnline) {
      unawaited(syncNow(reason: 'enqueue'));
    } else {
      _connectivity.setSyncStatus(ConnectivityStatus.waitingToSync);
    }
    return item;
  }

  /// Drain open queue items in sequence. Safe to call repeatedly.
  Future<SyncRunResult> syncNow({String reason = 'manual'}) async {
    if (_draining) {
      return SyncRunResult(
        processed: 0,
        succeeded: 0,
        failed: 0,
        conflicted: 0,
        finishedAt: DateTime.now(),
      );
    }

    if (!_connectivity.snapshot.transportOnline) {
      _connectivity.setSyncStatus(ConnectivityStatus.offline);
      return SyncRunResult(
        processed: 0,
        succeeded: 0,
        failed: 0,
        conflicted: 0,
        finishedAt: DateTime.now(),
      );
    }

    _draining = true;
    _connectivity.setSyncStatus(ConnectivityStatus.synchronizing);

    var processed = 0;
    var succeeded = 0;
    var failed = 0;
    var conflicted = 0;

    try {
      await _outbox.requeueFailed();
      final open = await _outbox.openItems();

      for (final item in open) {
        processed++;
        await _outbox.update(
          item.copyWith(
            status: SyncItemStatus.inFlight,
            lastAttemptAt: DateTime.now(),
          ),
        );

        final handler = _handlers[item.domain];
        if (handler == null) {
          // Keep pending until a module registers a handler.
          await _outbox.update(
            item.copyWith(status: SyncItemStatus.pending),
          );
          continue;
        }

        try {
          final entityId = await handler.process(item);
          await _outbox.markCompleted(item.id, entityId: entityId);
          succeeded++;
        } on SyncConflictException catch (error) {
          final detected = _conflicts.detectTimestampConflict(
            item: item,
            serverUpdatedAt: error.serverUpdatedAt ?? DateTime.now(),
          );
          await _conflicts.record(
            detected ??
                SyncConflict(
                  id: _uuid.v4(),
                  queueItemId: item.id,
                  domain: item.domain,
                  detectedAt: DateTime.now(),
                  strategy: ConflictDetectionStrategy.optimisticTimestamp,
                  entityId: item.entityId,
                  clientUpdatedAt: item.baseUpdatedAt,
                  serverUpdatedAt: error.serverUpdatedAt,
                  summary: error.message,
                ),
          );
          await _outbox.markConflicted(item.id, error.message);
          conflicted++;
        } catch (error) {
          await _outbox.markFailed(item.id, error.toString());
          failed++;
        }
      }

      final finished = DateTime.now();
      await _store.setLastSyncAt(finished);

      final stillOpen = await _outbox.openItems();
      if (failed > 0 || conflicted > 0) {
        _connectivity.setSyncStatus(ConnectivityStatus.syncFailed);
      } else if (stillOpen.isNotEmpty) {
        _connectivity.setSyncStatus(ConnectivityStatus.waitingToSync);
      } else {
        _connectivity.setSyncStatus(ConnectivityStatus.online);
      }

      final result = SyncRunResult(
        processed: processed,
        succeeded: succeeded,
        failed: failed,
        conflicted: conflicted,
        finishedAt: finished,
      );
      await _publishReliabilityEvent(result);
      return result;
    } finally {
      _draining = false;
    }
  }

  Future<void> _publishReliabilityEvent(SyncRunResult result) async {
    final bus = _events;
    final companyId = _companyId?.call();
    if (bus == null || companyId == null || companyId.isEmpty) return;
    if (result.processed == 0) return;

    if (result.hasFailures) {
      await bus.publish(
        companyId: companyId,
        actorEmployeeId: _actorEmployeeId?.call(),
        event: BusinessEvents.syncFailed(
          failedCount: result.failed + result.conflicted,
        ),
      );
    } else if (result.succeeded > 0) {
      await bus.publish(
        companyId: companyId,
        actorEmployeeId: _actorEmployeeId?.call(),
        event: BusinessEvents.syncCompleted(succeeded: result.succeeded),
      );
    }
  }
}
