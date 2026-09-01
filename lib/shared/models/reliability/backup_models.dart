import 'package:equatable/equatable.dart';

/// Business-facing backup vocabulary — never expose DB dumps / JSON files.
enum BackupKind { automatic, manual }

enum BackupHealth { healthy, attention, failed, unknown }

enum BackupRecordStatus {
  preparing,
  ready,
  uploading,
  completed,
  failed,
}

extension BackupKindX on BackupKind {
  String get label => switch (this) {
        BackupKind.automatic => 'Automatic',
        BackupKind.manual => 'Manual',
      };
}

extension BackupHealthX on BackupHealth {
  String get label => switch (this) {
        BackupHealth.healthy => 'Healthy',
        BackupHealth.attention => 'Needs attention',
        BackupHealth.failed => 'Failed',
        BackupHealth.unknown => 'Unknown',
      };
}

extension BackupRecordStatusX on BackupRecordStatus {
  String get label => switch (this) {
        BackupRecordStatus.preparing => 'Preparing',
        BackupRecordStatus.ready => 'Ready',
        BackupRecordStatus.uploading => 'Saving',
        BackupRecordStatus.completed => 'Completed',
        BackupRecordStatus.failed => 'Failed',
      };
}

/// One backup point in history — confidence, not technical export.
class BackupRecord extends Equatable {
  const BackupRecord({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.status,
    this.completedAt,
    this.health = BackupHealth.unknown,
    this.label,
    this.sizeBytes,
    this.errorMessage,
  });

  final String id;
  final DateTime createdAt;
  final BackupKind kind;
  final BackupRecordStatus status;
  final DateTime? completedAt;
  final BackupHealth health;

  /// Friendly label shown in history (e.g. "Morning safeguard").
  final String? label;
  final int? sizeBytes;
  final String? errorMessage;

  bool get isSuccessful =>
      status == BackupRecordStatus.completed &&
      health != BackupHealth.failed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'kind': kind.name,
        'status': status.name,
        'completed_at': completedAt?.toIso8601String(),
        'health': health.name,
        'label': label,
        'size_bytes': sizeBytes,
        'error_message': errorMessage,
      };

  factory BackupRecord.fromJson(Map<String, dynamic> json) {
    return BackupRecord(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      kind: BackupKind.values.byName(json['kind'] as String),
      status: BackupRecordStatus.values.byName(json['status'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'] as String),
      health: BackupHealth.values.byName(
        json['health'] as String? ?? BackupHealth.unknown.name,
      ),
      label: json['label'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      errorMessage: json['error_message'] as String?,
    );
  }

  BackupRecord copyWith({
    BackupRecordStatus? status,
    DateTime? completedAt,
    BackupHealth? health,
    int? sizeBytes,
    String? errorMessage,
    String? label,
  }) {
    return BackupRecord(
      id: id,
      createdAt: createdAt,
      kind: kind,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      health: health ?? this.health,
      label: label ?? this.label,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [id, createdAt, kind, status, health];
}

enum RestorePhase {
  idle,
  confirming,
  preparing,
  restoring,
  verifying,
  completed,
  failed,
}

extension RestorePhaseX on RestorePhase {
  String get label => switch (this) {
        RestorePhase.idle => 'Ready',
        RestorePhase.confirming => 'Confirm restore',
        RestorePhase.preparing => 'Preparing',
        RestorePhase.restoring => 'Restoring',
        RestorePhase.verifying => 'Checking integrity',
        RestorePhase.completed => 'Restored',
        RestorePhase.failed => 'Restore failed',
      };
}

/// In-flight or recent restore session — UI-facing recovery status.
class RestoreSession extends Equatable {
  const RestoreSession({
    required this.id,
    required this.backupId,
    required this.phase,
    required this.startedAt,
    this.progress = 0,
    this.completedAt,
    this.message,
  });

  final String id;
  final String backupId;
  final RestorePhase phase;
  final DateTime startedAt;

  /// 0.0 – 1.0
  final double progress;
  final DateTime? completedAt;
  final String? message;

  RestoreSession copyWith({
    RestorePhase? phase,
    double? progress,
    DateTime? completedAt,
    String? message,
  }) {
    return RestoreSession(
      id: id,
      backupId: backupId,
      phase: phase ?? this.phase,
      startedAt: startedAt,
      progress: progress ?? this.progress,
      completedAt: completedAt ?? this.completedAt,
      message: message ?? this.message,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'backup_id': backupId,
        'phase': phase.name,
        'started_at': startedAt.toIso8601String(),
        'progress': progress,
        'completed_at': completedAt?.toIso8601String(),
        'message': message,
      };

  factory RestoreSession.fromJson(Map<String, dynamic> json) {
    return RestoreSession(
      id: json['id'] as String,
      backupId: json['backup_id'] as String,
      phase: RestorePhase.values.byName(json['phase'] as String),
      startedAt: DateTime.parse(json['started_at'] as String),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'] as String),
      message: json['message'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, backupId, phase, progress, completedAt];
}
