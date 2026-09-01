import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// How a conflict was detected — resolution UI comes later.
enum ConflictDetectionStrategy {
  /// Compare entity `updated_at` / version at enqueue vs server.
  optimisticTimestamp,

  /// Explicit monotonic version column (future).
  optimisticVersion,
}

/// A detected sync conflict — architecture seam only.
///
/// Do not auto-merge yet. Surface friendly review later.
class SyncConflict extends Equatable {
  const SyncConflict({
    required this.id,
    required this.queueItemId,
    required this.domain,
    required this.detectedAt,
    required this.strategy,
    this.entityId,
    this.clientUpdatedAt,
    this.serverUpdatedAt,
    this.summary,
  });

  final String id;
  final String queueItemId;
  final SyncDomain domain;
  final DateTime detectedAt;
  final ConflictDetectionStrategy strategy;
  final String? entityId;
  final DateTime? clientUpdatedAt;
  final DateTime? serverUpdatedAt;

  /// Human-friendly one-liner for future review UI.
  final String? summary;

  Map<String, dynamic> toJson() => {
        'id': id,
        'queue_item_id': queueItemId,
        'domain': domain.code,
        'detected_at': detectedAt.toIso8601String(),
        'strategy': strategy.name,
        'entity_id': entityId,
        'client_updated_at': clientUpdatedAt?.toIso8601String(),
        'server_updated_at': serverUpdatedAt?.toIso8601String(),
        'summary': summary,
      };

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      id: json['id'] as String,
      queueItemId: json['queue_item_id'] as String,
      domain: SyncDomain.values.byName(json['domain'] as String),
      detectedAt: DateTime.parse(json['detected_at'] as String),
      strategy: ConflictDetectionStrategy.values.byName(
        json['strategy'] as String? ??
            ConflictDetectionStrategy.optimisticTimestamp.name,
      ),
      entityId: json['entity_id'] as String?,
      clientUpdatedAt: json['client_updated_at'] == null
          ? null
          : DateTime.tryParse(json['client_updated_at'] as String),
      serverUpdatedAt: json['server_updated_at'] == null
          ? null
          : DateTime.tryParse(json['server_updated_at'] as String),
      summary: json['summary'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, queueItemId, domain, detectedAt, strategy];
}
