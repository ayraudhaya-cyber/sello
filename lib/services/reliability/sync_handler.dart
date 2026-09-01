import 'package:sello/shared/models/reliability/sync_models.dart';

/// Domain handler registered with [SyncEngine].
///
/// Modules implement this and register — they must not own separate sync loops.
abstract class SyncHandler {
  SyncDomain get domain;

  /// Apply one queued mutation to the remote source of truth.
  ///
  /// Throw [SyncConflictException] when optimistic concurrency fails.
  /// Return the server entity id when known.
  Future<String?> process(SyncQueueItem item);
}

class SyncConflictException implements Exception {
  SyncConflictException(this.message, {this.serverUpdatedAt});

  final String message;
  final DateTime? serverUpdatedAt;

  @override
  String toString() => message;
}

/// Marker — handler not wired yet for this domain.
class SyncHandlerNotRegisteredException implements Exception {
  SyncHandlerNotRegisteredException(this.domain);

  final SyncDomain domain;

  @override
  String toString() =>
      'No sync handler registered for ${domain.label}.';
}
