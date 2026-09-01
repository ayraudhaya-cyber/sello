import 'package:equatable/equatable.dart';

/// Append-only activity row from `public.employee_activity_events`.
class EmployeeActivityEvent extends Equatable {
  const EmployeeActivityEvent({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.eventType,
    required this.summary,
    required this.createdAt,
    this.referenceType,
    this.referenceId,
  });

  final String id;
  final String companyId;
  final String employeeId;
  final String eventType;
  final String summary;
  final DateTime createdAt;
  final String? referenceType;
  final String? referenceId;

  factory EmployeeActivityEvent.fromJson(Map<String, dynamic> json) {
    return EmployeeActivityEvent(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      employeeId: json['employee_id'] as String,
      eventType: json['event_type'] as String,
      summary: json['summary'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        employeeId,
        eventType,
        summary,
        createdAt,
        referenceType,
        referenceId,
      ];
}
