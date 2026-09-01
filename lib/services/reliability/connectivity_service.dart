import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sello/shared/models/reliability/connectivity_status.dart';

/// Observes transport connectivity and exposes shared [ConnectivitySnapshot].
///
/// SyncEngine adjusts status further (synchronizing / waiting / failed).
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<ConnectivitySnapshot>.broadcast();

  ConnectivitySnapshot _snapshot = ConnectivitySnapshot.online();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _started = false;

  ConnectivitySnapshot get snapshot => _snapshot;
  Stream<ConnectivitySnapshot> get changes => _controller.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      _applyTransport(_isOnline(results));
    });
  }

  Future<ConnectivitySnapshot> refresh() async {
    final results = await _connectivity.checkConnectivity();
    _applyTransport(_isOnline(results));
    return _snapshot;
  }

  /// SyncEngine / UI may refine status without changing transport Online/Offline.
  void setSyncStatus(ConnectivityStatus status) {
    if (!_snapshot.transportOnline &&
        status != ConnectivityStatus.offline &&
        status != ConnectivityStatus.waitingToSync) {
      // Stay offline-facing when transport is down.
      _emit(
        _snapshot.copyWith(
          status: ConnectivityStatus.offline,
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }
    _emit(
      _snapshot.copyWith(status: status, updatedAt: DateTime.now()),
    );
  }

  void _applyTransport(bool online) {
    final now = DateTime.now();
    if (online) {
      final nextStatus =
          _snapshot.status == ConnectivityStatus.waitingToSync ||
                  _snapshot.status == ConnectivityStatus.syncFailed
              ? _snapshot.status
              : ConnectivityStatus.online;
      _emit(
        _snapshot.copyWith(
          status: nextStatus == ConnectivityStatus.offline
              ? ConnectivityStatus.online
              : nextStatus,
          transportOnline: true,
          updatedAt: now,
          lastOnlineAt: now,
        ),
      );
    } else {
      _emit(
        _snapshot.copyWith(
          status: ConnectivityStatus.offline,
          transportOnline: false,
          updatedAt: now,
        ),
      );
    }
  }

  void _emit(ConnectivitySnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  static bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
