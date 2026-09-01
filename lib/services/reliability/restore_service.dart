import 'package:sello/services/reliability/reliability_store.dart';
import 'package:sello/shared/models/reliability/backup_models.dart';
import 'package:uuid/uuid.dart';

/// Restore architecture — recovery status for businesses, not import tooling.
///
/// Full cloud restore / disaster recovery lands later; this owns the session
/// lifecycle and confirmation/progress vocabulary.
class RestoreService {
  RestoreService({
    required ReliabilityStore store,
    Uuid? uuid,
  })  : _store = store,
        _uuid = uuid ?? const Uuid();

  final ReliabilityStore _store;
  final Uuid _uuid;

  Future<RestoreSession?> activeSession() async {
    await _store.initialize();
    return _store.loadActiveRestore();
  }

  /// Begin restore confirmation for a backup in history.
  Future<RestoreSession> beginConfirm(String backupId) async {
    await _store.initialize();
    final session = RestoreSession(
      id: _uuid.v4(),
      backupId: backupId,
      phase: RestorePhase.confirming,
      startedAt: DateTime.now(),
      progress: 0,
      message: 'Confirm to restore your business to this safeguard.',
    );
    await _store.saveActiveRestore(session);
    return session;
  }

  /// Advance through restore phases. Payload apply is a future seam.
  Future<RestoreSession> runRestore(String sessionId) async {
    await _store.initialize();
    final current = await _store.loadActiveRestore();
    if (current == null || current.id != sessionId) {
      throw StateError('No restore session to run.');
    }

    var session = current.copyWith(
      phase: RestorePhase.preparing,
      progress: 0.15,
      message: 'Preparing recovery…',
    );
    await _store.saveActiveRestore(session);

    session = session.copyWith(
      phase: RestorePhase.restoring,
      progress: 0.55,
      message: 'Restoring your information…',
    );
    await _store.saveActiveRestore(session);

    session = session.copyWith(
      phase: RestorePhase.verifying,
      progress: 0.85,
      message: 'Checking integrity…',
    );
    await _store.saveActiveRestore(session);

    // Foundation completes the session locally. Cloud apply comes later.
    session = session.copyWith(
      phase: RestorePhase.completed,
      progress: 1,
      completedAt: DateTime.now(),
      message: 'Restore complete. Your business is ready.',
    );
    await _store.saveActiveRestore(session);
    return session;
  }

  Future<void> cancel() async {
    await _store.saveActiveRestore(null);
  }
}
