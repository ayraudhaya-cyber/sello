import 'package:equatable/equatable.dart';

/// Reusable connectivity / sync surface state across the app.
///
/// Not a network-only flag — includes sync lifecycle so Sales and Hub share
/// one vocabulary for banners, badges, and the Reliability page.
enum ConnectivityStatus {
  online,
  offline,
  synchronizing,
  syncFailed,
  waitingToSync,
}

extension ConnectivityStatusX on ConnectivityStatus {
  String get label => switch (this) {
        ConnectivityStatus.online => 'Online',
        ConnectivityStatus.offline => 'Offline',
        ConnectivityStatus.synchronizing => 'Synchronizing',
        ConnectivityStatus.syncFailed => 'Sync Failed',
        ConnectivityStatus.waitingToSync => 'Waiting to Sync',
      };

  String get confidenceMessage => switch (this) {
        ConnectivityStatus.online => 'Connected — changes sync immediately.',
        ConnectivityStatus.offline =>
          'Working offline — changes will sync when you reconnect.',
        ConnectivityStatus.synchronizing =>
          'Syncing your latest work safely…',
        ConnectivityStatus.syncFailed =>
          'Some changes could not sync. Sello will retry automatically.',
        ConnectivityStatus.waitingToSync =>
          'Changes are queued and will sync when ready.',
      };

  bool get isReachable =>
      this == ConnectivityStatus.online ||
      this == ConnectivityStatus.synchronizing;

  bool get hasPendingWork =>
      this == ConnectivityStatus.waitingToSync ||
      this == ConnectivityStatus.synchronizing ||
      this == ConnectivityStatus.syncFailed;
}

/// Snapshot used by providers and diagnostics.
class ConnectivitySnapshot extends Equatable {
  const ConnectivitySnapshot({
    required this.status,
    required this.updatedAt,
    this.lastOnlineAt,
    this.transportOnline = true,
  });

  factory ConnectivitySnapshot.online() => ConnectivitySnapshot(
        status: ConnectivityStatus.online,
        updatedAt: DateTime.now(),
        lastOnlineAt: DateTime.now(),
        transportOnline: true,
      );

  final ConnectivityStatus status;
  final DateTime updatedAt;
  final DateTime? lastOnlineAt;

  /// Raw transport reachability (Wi‑Fi / cellular). Sync status may differ.
  final bool transportOnline;

  ConnectivitySnapshot copyWith({
    ConnectivityStatus? status,
    DateTime? updatedAt,
    DateTime? lastOnlineAt,
    bool? transportOnline,
  }) {
    return ConnectivitySnapshot(
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
      transportOnline: transportOnline ?? this.transportOnline,
    );
  }

  @override
  List<Object?> get props => [status, updatedAt, lastOnlineAt, transportOnline];
}
