import 'package:equatable/equatable.dart';

/// Outcome of a completed field visit — extend via DB migration + this enum.
///
/// Future custom outcomes can be added without changing the visit workflow.
enum VisitOutcome {
  orderCreated,
  paymentCollected,
  followUpRequired,
  customerUnavailable,
  noOrderToday,
  newSalesOpportunity;

  String get dbValue => switch (this) {
        VisitOutcome.orderCreated => 'order_created',
        VisitOutcome.paymentCollected => 'payment_collected',
        VisitOutcome.followUpRequired => 'follow_up_required',
        VisitOutcome.customerUnavailable => 'customer_unavailable',
        VisitOutcome.noOrderToday => 'no_order_today',
        VisitOutcome.newSalesOpportunity => 'new_sales_opportunity',
      };

  String get label => switch (this) {
        VisitOutcome.orderCreated => 'Order created',
        VisitOutcome.paymentCollected => 'Payment collected',
        VisitOutcome.followUpRequired => 'Follow-up required',
        VisitOutcome.customerUnavailable => 'Customer unavailable',
        VisitOutcome.noOrderToday => 'No order today',
        VisitOutcome.newSalesOpportunity => 'New sales opportunity',
      };

  static VisitOutcome? fromDb(String? value) {
    return switch (value) {
      'order_created' => VisitOutcome.orderCreated,
      'payment_collected' => VisitOutcome.paymentCollected,
      'follow_up_required' => VisitOutcome.followUpRequired,
      'customer_unavailable' => VisitOutcome.customerUnavailable,
      'no_order_today' => VisitOutcome.noOrderToday,
      'new_sales_opportunity' => VisitOutcome.newSalesOpportunity,
      _ => null,
    };
  }

  static const List<VisitOutcome> selectable = VisitOutcome.values;
}

enum CustomerVisitStatus {
  inProgress,
  completed,
  cancelled;

  String get dbValue => switch (this) {
        CustomerVisitStatus.inProgress => 'in_progress',
        CustomerVisitStatus.completed => 'completed',
        CustomerVisitStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        CustomerVisitStatus.inProgress => 'In progress',
        CustomerVisitStatus.completed => 'Completed',
        CustomerVisitStatus.cancelled => 'Cancelled',
      };

  static CustomerVisitStatus fromDb(String? value) {
    return switch (value) {
      'completed' => CustomerVisitStatus.completed,
      'cancelled' => CustomerVisitStatus.cancelled,
      _ => CustomerVisitStatus.inProgress,
    };
  }
}

/// Point-in-time GPS capture (start or complete) — never continuous tracking.
///
/// Stored on the visit and carried through the Reliability sync payload.
class VisitGpsPoint extends Equatable {
  const VisitGpsPoint({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      };

  @override
  List<Object?> get props => [latitude, longitude, accuracyMeters];
}

/// Operational customer visit — what actually happened in the field.
///
/// Separate from Schedule (planned work). Future: photos, voice notes,
/// customer signature, AI visit summary — columns reserved in DB.
class CustomerVisit extends Equatable {
  const CustomerVisit({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.employeeId,
    required this.status,
    required this.startedAt,
    this.branchId,
    this.scheduledVisitId,
    this.customerName,
    this.customerPhone,
    this.employeeName,
    this.outcome,
    this.notes,
    this.endedAt,
    this.durationMinutes,
    this.startLatitude,
    this.startLongitude,
    this.endLatitude,
    this.endLongitude,
    this.orderCount = 0,
    this.paymentCount = 0,
    this.createdAt,
    this.updatedAt,
    this.offlineClientId,
    this.signatureStoragePath,
    this.photoPaths = const [],
    this.voiceNotePath,
    this.pendingSync = false,
  });

  final String id;
  final String companyId;
  final String? branchId;
  final String customerId;
  final String employeeId;
  final String? scheduledVisitId;
  final String? customerName;
  final String? customerPhone;
  final String? employeeName;
  final CustomerVisitStatus status;
  final VisitOutcome? outcome;
  final String? notes;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationMinutes;
  final double? startLatitude;
  final double? startLongitude;
  final double? endLatitude;
  final double? endLongitude;
  final int orderCount;
  final int paymentCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Idempotent offline key — maps to `customer_visits.offline_client_id`.
  final String? offlineClientId;

  /// Future customer signature evidence (storage path).
  final String? signatureStoragePath;

  /// Future photo evidence paths.
  final List<String> photoPaths;

  /// Future voice note storage path.
  final String? voiceNotePath;

  /// True while a local optimistic visit awaits Reliability sync.
  final bool pendingSync;

  bool get isActive => status == CustomerVisitStatus.inProgress;
  bool get isCompleted => status == CustomerVisitStatus.completed;
  bool get isLocalOnly => id.startsWith('local:');

  bool get hasStartGps => startLatitude != null && startLongitude != null;
  bool get hasEndGps => endLatitude != null && endLongitude != null;

  String get durationLabel {
    final minutes = durationMinutes ??
        (endedAt == null
            ? DateTime.now().difference(startedAt).inMinutes
            : endedAt!.difference(startedAt).inMinutes);
    if (minutes < 1) return '< 1 min';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  factory CustomerVisit.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'];
    final employee = json['employees'];
    final photos = json['photo_paths'];
    return CustomerVisit(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String?,
      customerId: json['customer_id'] as String,
      employeeId: json['employee_id'] as String,
      scheduledVisitId: json['scheduled_visit_id'] as String?,
      status: CustomerVisitStatus.fromDb(json['status'] as String?),
      outcome: VisitOutcome.fromDb(json['outcome'] as String?),
      notes: _blankToNull(json['notes'] as String?),
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: _parseDateTime(json['ended_at']),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      startLatitude: (json['start_latitude'] as num?)?.toDouble(),
      startLongitude: (json['start_longitude'] as num?)?.toDouble(),
      endLatitude: (json['end_latitude'] as num?)?.toDouble(),
      endLongitude: (json['end_longitude'] as num?)?.toDouble(),
      customerName: customer is Map ? customer['name'] as String? : null,
      customerPhone: customer is Map ? customer['phone'] as String? : null,
      employeeName: employee is Map ? employee['full_name'] as String? : null,
      orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
      paymentCount: (json['payment_count'] as num?)?.toInt() ?? 0,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      offlineClientId: json['offline_client_id'] as String?,
      signatureStoragePath: json['signature_storage_path'] as String?,
      photoPaths: photos is List
          ? [
              for (final p in photos)
                if (p is String && p.isNotEmpty) p,
            ]
          : const [],
      voiceNotePath: json['voice_note_path'] as String?,
    );
  }

  CustomerVisit copyWith({
    String? id,
    CustomerVisitStatus? status,
    VisitOutcome? outcome,
    String? notes,
    DateTime? endedAt,
    int? durationMinutes,
    double? endLatitude,
    double? endLongitude,
    int? orderCount,
    int? paymentCount,
    String? offlineClientId,
    String? customerName,
    String? employeeName,
    bool? pendingSync,
    List<String>? photoPaths,
    String? signatureStoragePath,
    String? voiceNotePath,
  }) {
    return CustomerVisit(
      id: id ?? this.id,
      companyId: companyId,
      branchId: branchId,
      customerId: customerId,
      employeeId: employeeId,
      scheduledVisitId: scheduledVisitId,
      status: status ?? this.status,
      outcome: outcome ?? this.outcome,
      notes: notes ?? this.notes,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      endLatitude: endLatitude ?? this.endLatitude,
      endLongitude: endLongitude ?? this.endLongitude,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone,
      employeeName: employeeName ?? this.employeeName,
      orderCount: orderCount ?? this.orderCount,
      paymentCount: paymentCount ?? this.paymentCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      offlineClientId: offlineClientId ?? this.offlineClientId,
      signatureStoragePath: signatureStoragePath ?? this.signatureStoragePath,
      photoPaths: photoPaths ?? this.photoPaths,
      voiceNotePath: voiceNotePath ?? this.voiceNotePath,
      pendingSync: pendingSync ?? this.pendingSync,
    );
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
        status,
        outcome,
        startedAt,
        endedAt,
        updatedAt,
        offlineClientId,
        pendingSync,
        orderCount,
        paymentCount,
      ];
}

class StartCustomerVisitInput {
  const StartCustomerVisitInput({
    required this.customerId,
    required this.employeeId,
    this.branchId,
    this.scheduledVisitId,
    this.gps,
    this.offlineClientId,
  });

  final String customerId;
  final String employeeId;
  final String? branchId;
  final String? scheduledVisitId;
  final VisitGpsPoint? gps;

  /// Idempotent offline key — maps to `customer_visits.offline_client_id`.
  final String? offlineClientId;
}

class CompleteCustomerVisitInput {
  const CompleteCustomerVisitInput({
    required this.visitId,
    required this.outcome,
    this.notes,
    this.gps,
    this.signatureStoragePath,
  });

  final String visitId;
  final VisitOutcome outcome;
  final String? notes;
  final VisitGpsPoint? gps;

  /// Optional buyer signature evidence path (storage or pending local key).
  final String? signatureStoragePath;
}

/// Manager-facing day rollup for operational visits.
class CustomerVisitDayStats extends Equatable {
  const CustomerVisitDayStats({
    this.completed = 0,
    this.inProgress = 0,
    this.cancelled = 0,
    this.scheduledPending = 0,
    this.missed = 0,
  });

  final int completed;
  final int inProgress;
  final int cancelled;
  final int scheduledPending;
  final int missed;

  @override
  List<Object?> get props =>
      [completed, inProgress, cancelled, scheduledPending, missed];
}
