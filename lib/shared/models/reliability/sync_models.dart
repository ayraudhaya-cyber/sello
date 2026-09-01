import 'package:equatable/equatable.dart';

/// Domains prepared for offline-first support.
///
/// Notes are captured as fields on other entities today — reserved as a
/// first-class sync domain for a future notes module.
enum SyncDomain {
  customers,
  products,
  orders,
  customerVisits,
  schedule,
  notes,
}

extension SyncDomainX on SyncDomain {
  String get label => switch (this) {
        SyncDomain.customers => 'Customers',
        SyncDomain.products => 'Products',
        SyncDomain.orders => 'Orders',
        SyncDomain.customerVisits => 'Customer Visits',
        SyncDomain.schedule => 'Schedule',
        SyncDomain.notes => 'Notes',
      };

  String get code => name;
}

enum SyncOperation {
  create,
  update,
  delete,
  complete,
  cancel,
  upsert,
}

extension SyncOperationX on SyncOperation {
  String get code => name;
}

enum SyncItemStatus {
  pending,
  inFlight,
  completed,
  failed,
  cancelled,
  conflicted,
}

extension SyncItemStatusX on SyncItemStatus {
  String get label => switch (this) {
        SyncItemStatus.pending => 'Waiting',
        SyncItemStatus.inFlight => 'Syncing',
        SyncItemStatus.completed => 'Synced',
        SyncItemStatus.failed => 'Failed',
        SyncItemStatus.cancelled => 'Cancelled',
        SyncItemStatus.conflicted => 'Needs review',
      };

  bool get isOpen =>
      this == SyncItemStatus.pending ||
      this == SyncItemStatus.inFlight ||
      this == SyncItemStatus.failed ||
      this == SyncItemStatus.conflicted;
}

/// One offline / deferred mutation in the shared synchronization queue.
///
/// Modules enqueue here — they must not invent their own sync pipelines.
class SyncQueueItem extends Equatable {
  const SyncQueueItem({
    required this.id,
    required this.clientId,
    required this.domain,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.status = SyncItemStatus.pending,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastError,
    this.entityId,
    this.companyId,
    this.sequence,
    this.baseUpdatedAt,
  });

  /// Durable queue row id.
  final String id;

  /// Idempotency key — maps to DB `offline_client_id` where available.
  final String clientId;

  final SyncDomain domain;
  final SyncOperation operation;

  /// Opaque JSON-compatible map for the domain handler.
  final Map<String, dynamic> payload;

  final DateTime createdAt;
  final SyncItemStatus status;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? lastError;

  /// Server entity id once known / for updates.
  final String? entityId;
  final String? companyId;

  /// Monotonic order within the device queue — preserves execution order.
  final int? sequence;

  /// Optimistic concurrency token (entity `updated_at` at enqueue time).
  final DateTime? baseUpdatedAt;

  bool get canRetry =>
      status == SyncItemStatus.failed || status == SyncItemStatus.pending;

  SyncQueueItem copyWith({
    SyncItemStatus? status,
    int? attempts,
    DateTime? lastAttemptAt,
    String? lastError,
    String? entityId,
    int? sequence,
    Map<String, dynamic>? payload,
  }) {
    return SyncQueueItem(
      id: id,
      clientId: clientId,
      domain: domain,
      operation: operation,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      entityId: entityId ?? this.entityId,
      companyId: companyId,
      sequence: sequence ?? this.sequence,
      baseUpdatedAt: baseUpdatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'domain': domain.code,
        'operation': operation.code,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        'attempts': attempts,
        'last_attempt_at': lastAttemptAt?.toIso8601String(),
        'last_error': lastError,
        'entity_id': entityId,
        'company_id': companyId,
        'sequence': sequence,
        'base_updated_at': baseUpdatedAt?.toIso8601String(),
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncQueueItem(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      domain: SyncDomain.values.byName(json['domain'] as String),
      operation: SyncOperation.values.byName(json['operation'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      createdAt: DateTime.parse(json['created_at'] as String),
      status: SyncItemStatus.values.byName(
        json['status'] as String? ?? SyncItemStatus.pending.name,
      ),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastAttemptAt: json['last_attempt_at'] == null
          ? null
          : DateTime.tryParse(json['last_attempt_at'] as String),
      lastError: json['last_error'] as String?,
      entityId: json['entity_id'] as String?,
      companyId: json['company_id'] as String?,
      sequence: (json['sequence'] as num?)?.toInt(),
      baseUpdatedAt: json['base_updated_at'] == null
          ? null
          : DateTime.tryParse(json['base_updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        clientId,
        domain,
        operation,
        status,
        attempts,
        entityId,
        sequence,
      ];
}

/// Result of draining the queue once.
class SyncRunResult extends Equatable {
  const SyncRunResult({
    required this.processed,
    required this.succeeded,
    required this.failed,
    required this.conflicted,
    required this.finishedAt,
  });

  final int processed;
  final int succeeded;
  final int failed;
  final int conflicted;
  final DateTime finishedAt;

  bool get hasFailures => failed > 0 || conflicted > 0;

  @override
  List<Object?> get props =>
      [processed, succeeded, failed, conflicted, finishedAt];
}
