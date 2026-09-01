import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/sales_day.dart';

enum VisitStatus {
  scheduled,
  completed,
  missed,
  cancelled,
  unplanned;

  String get dbValue => name;

  String get label => switch (this) {
        VisitStatus.scheduled => 'Scheduled',
        VisitStatus.completed => 'Completed',
        VisitStatus.missed => 'Missed',
        VisitStatus.cancelled => 'Cancelled',
        VisitStatus.unplanned => 'Unplanned',
      };

  static VisitStatus fromDb(String? value) {
    return switch (value) {
      'completed' => VisitStatus.completed,
      'missed' => VisitStatus.missed,
      'cancelled' => VisitStatus.cancelled,
      'unplanned' => VisitStatus.unplanned,
      _ => VisitStatus.scheduled,
    };
  }

  /// Maps into Sales Home stop vocabulary.
  VisitStopStatus get homeStopStatus => switch (this) {
        VisitStatus.completed => VisitStopStatus.completed,
        VisitStatus.missed || VisitStatus.cancelled => VisitStopStatus.skipped,
        VisitStatus.scheduled || VisitStatus.unplanned => VisitStopStatus.pending,
      };
}

enum VisitPriority {
  low,
  normal,
  high,
  urgent;

  String get dbValue => name;

  String get label => switch (this) {
        VisitPriority.low => 'Low',
        VisitPriority.normal => 'Normal',
        VisitPriority.high => 'High',
        VisitPriority.urgent => 'Urgent',
      };

  static VisitPriority fromDb(String? value) {
    return switch (value) {
      'low' => VisitPriority.low,
      'high' => VisitPriority.high,
      'urgent' => VisitPriority.urgent,
      _ => VisitPriority.normal,
    };
  }
}

/// Persisted customer visit plan row.
class ScheduledVisit extends Equatable {
  const ScheduledVisit({
    required this.id,
    required this.companyId,
    this.customerId,
    required this.employeeId,
    required this.visitDate,
    required this.status,
    required this.priority,
    this.branchId,
    this.customerName,
    this.customerPhone,
    this.employeeName,
    this.preferredTime,
    this.expectedDurationMinutes,
    this.purpose,
    this.notes,
    this.area,
    this.sortOrder = 0,
    this.completedAt,
    this.cancelledAt,
    this.recurrenceRule,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? branchId;

  /// Null on area-only territory assignments.
  final String? customerId;
  final String employeeId;
  final DateTime visitDate;
  final VisitStatus status;
  final VisitPriority priority;
  final String? customerName;
  final String? customerPhone;
  final String? employeeName;

  /// Minutes from midnight local (optional preferred slot).
  final int? preferredTime;
  final int? expectedDurationMinutes;
  final String? purpose;
  final String? notes;

  /// Optional coverage area / locality (route planning seam).
  final String? area;
  final int sortOrder;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? recurrenceRule;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCustomerStop =>
      customerId != null && customerId!.trim().isNotEmpty;

  bool get isAreaAssignment =>
      !isCustomerStop && (area?.trim().isNotEmpty ?? false);

  String get displayTitle =>
      customerName ??
      (area?.trim().isNotEmpty == true ? area!.trim() : 'Field plan');

  bool get isOpen =>
      status == VisitStatus.scheduled || status == VisitStatus.unplanned;

  String? get preferredTimeLabel {
    final minutes = preferredTime;
    if (minutes == null) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }

  FieldVisitStop toFieldVisitStop() {
    final origin = status == VisitStatus.unplanned
        ? VisitOrigin.unplanned
        : VisitOrigin.planned;
    final badge = switch (status) {
      VisitStatus.completed => VisitBadgeKind.completed,
      VisitStatus.unplanned => VisitBadgeKind.unplanned,
      VisitStatus.missed || VisitStatus.cancelled => VisitBadgeKind.followUp,
      VisitStatus.scheduled => priority == VisitPriority.urgent ||
              priority == VisitPriority.high
          ? VisitBadgeKind.priority
          : VisitBadgeKind.scheduled,
    };

    return FieldVisitStop(
      id: id,
      customerId: customerId,
      customerName: customerName ?? 'Customer',
      origin: origin,
      status: status.homeStopStatus,
      badge: badge,
      area: area,
      lastVisitLabel: purpose,
      outstandingLabel: preferredTimeLabel,
      sortOrder: sortOrder,
    );
  }

  factory ScheduledVisit.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'];
    final employee = json['employees'];
    return ScheduledVisit(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String?,
      customerId: json['customer_id'] as String?,
      employeeId: json['employee_id'] as String,
      visitDate: DateTime.parse(json['visit_date'] as String),
      status: VisitStatus.fromDb(json['status'] as String?),
      priority: VisitPriority.fromDb(json['priority'] as String?),
      customerName: customer is Map ? customer['name'] as String? : null,
      customerPhone: customer is Map ? customer['phone'] as String? : null,
      employeeName:
          employee is Map ? employee['full_name'] as String? : null,
      preferredTime: _timeToMinutes(json['preferred_time']),
      expectedDurationMinutes:
          (json['expected_duration_minutes'] as num?)?.toInt(),
      purpose: _blankToNull(json['purpose'] as String?),
      notes: _blankToNull(json['notes'] as String?),
      area: _blankToNull(json['area'] as String?),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      completedAt: _parseDateTime(json['completed_at']),
      cancelledAt: _parseDateTime(json['cancelled_at']),
      recurrenceRule: _blankToNull(json['recurrence_rule'] as String?),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static int? _timeToMinutes(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      final parts = value.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return h * 60 + m;
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        customerId,
        employeeId,
        visitDate,
        status,
        priority,
        preferredTime,
        sortOrder,
        area,
        updatedAt,
      ];
}

class VisitUpsertInput {
  const VisitUpsertInput({
    this.id,
    this.customerId,
    required this.employeeId,
    required this.visitDate,
    this.priority = VisitPriority.normal,
    this.branchId,
    this.preferredTimeMinutes,
    this.expectedDurationMinutes,
    this.purpose,
    this.notes,
    this.area,
    this.status = VisitStatus.scheduled,
    this.sortOrder = 0,
    this.recurrenceRule,
  });

  final String? id;

  /// Null when planning an area-only territory assignment.
  final String? customerId;
  final String employeeId;
  final DateTime visitDate;
  final VisitPriority priority;
  final String? branchId;
  final int? preferredTimeMinutes;

  /// Optional — not collected in primary route planning. Reserved for
  /// future average/historical duration optimization.
  final int? expectedDurationMinutes;
  final String? purpose;
  final String? notes;

  /// Coverage area for the route stop (e.g. Colombo).
  final String? area;
  final VisitStatus status;
  final int sortOrder;

  /// Reserved — weekly / fortnightly / monthly expansion later.
  final String? recurrenceRule;

  bool get isCreate => id == null;
}

class VisitDashboardStats extends Equatable {
  const VisitDashboardStats({
    this.today = 0,
    this.scheduled = 0,
    this.completed = 0,
    this.missed = 0,
    this.unplanned = 0,
  });

  final int today;
  final int scheduled;
  final int completed;
  final int missed;
  final int unplanned;

  @override
  List<Object?> get props => [today, scheduled, completed, missed, unplanned];
}
