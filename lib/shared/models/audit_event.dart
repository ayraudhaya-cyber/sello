import 'package:equatable/equatable.dart';

/// Shared audit event — compliance / troubleshooting foundation.
///
/// Examples: "Order approved by John", "Inventory adjusted by Sarah".
/// Domains should publish via [AuditService] / BusinessEventBus — never own
/// parallel audit UIs.
class AuditEvent extends Equatable {
  const AuditEvent({
    required this.id,
    required this.companyId,
    required this.summary,
    required this.action,
    required this.createdAt,
    this.actorEmployeeId,
    this.actorName,
    this.moduleKey,
    this.referenceType,
    this.referenceId,
    this.metadata = const {},
  });

  final String id;
  final String companyId;
  final String? actorEmployeeId;
  final String? actorName;
  final String action;
  final String summary;
  final String? moduleKey;
  final String? referenceType;
  final String? referenceId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      actorEmployeeId: json['actor_employee_id'] as String?,
      actorName: json['actor_name'] as String?,
      action: json['action'] as String? ?? 'unknown',
      summary: json['summary'] as String? ?? '',
      moduleKey: json['module_key'] as String?,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  @override
  List<Object?> get props => [id, companyId, action, createdAt];
}

/// Input for writing an audit record.
class AuditLogInput {
  const AuditLogInput({
    required this.action,
    required this.summary,
    this.moduleKey,
    this.referenceType,
    this.referenceId,
    this.metadata = const {},
  });

  final String action;
  final String summary;
  final String? moduleKey;
  final String? referenceType;
  final String? referenceId;
  final Map<String, dynamic> metadata;
}

/// Future: device registration for trusted endpoints / push.
class DeviceRegistrationDraft {
  const DeviceRegistrationDraft({
    required this.deviceLabel,
    this.platform,
    this.pushToken,
  });

  final String deviceLabel;
  final String? platform;
  final String? pushToken;
}
