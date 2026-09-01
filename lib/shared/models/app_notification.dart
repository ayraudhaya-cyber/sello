import 'package:equatable/equatable.dart';

/// Domain category for notifications and company activity.
enum NotificationCategory {
  orders,
  inventory,
  payments,
  customers,
  suppliers,
  products,
  schedule,
  visits,
  team,
  system,
  intelligence,
  reliability;

  String get dbValue => name;

  String get label => switch (this) {
        NotificationCategory.orders => 'Orders',
        NotificationCategory.inventory => 'Inventory',
        NotificationCategory.payments => 'Payments',
        NotificationCategory.customers => 'Customers',
        NotificationCategory.suppliers => 'Suppliers',
        NotificationCategory.products => 'Products',
        NotificationCategory.schedule => 'Schedule',
        NotificationCategory.visits => 'Visits',
        NotificationCategory.team => 'Team',
        NotificationCategory.system => 'System',
        NotificationCategory.intelligence => 'Intelligence',
        NotificationCategory.reliability => 'Reliability',
      };

  static NotificationCategory fromDb(String? value) {
    return switch (value) {
      'orders' => NotificationCategory.orders,
      'inventory' => NotificationCategory.inventory,
      'payments' => NotificationCategory.payments,
      'customers' => NotificationCategory.customers,
      'suppliers' => NotificationCategory.suppliers,
      'products' => NotificationCategory.products,
      'schedule' => NotificationCategory.schedule,
      'visits' => NotificationCategory.visits,
      'team' => NotificationCategory.team,
      'intelligence' => NotificationCategory.intelligence,
      'reliability' => NotificationCategory.reliability,
      _ => NotificationCategory.system,
    };
  }

  /// Categories shown in preference / filter UIs.
  static const List<NotificationCategory> preferenceOrder = [
    NotificationCategory.orders,
    NotificationCategory.inventory,
    NotificationCategory.payments,
    NotificationCategory.customers,
    NotificationCategory.suppliers,
    NotificationCategory.products,
    NotificationCategory.schedule,
    NotificationCategory.visits,
    NotificationCategory.team,
    NotificationCategory.intelligence,
    NotificationCategory.reliability,
    NotificationCategory.system,
  ];
}

enum NotificationPriority {
  critical,
  high,
  normal,
  information;

  String get dbValue => name;

  String get label => switch (this) {
        NotificationPriority.critical => 'Critical',
        NotificationPriority.high => 'High',
        NotificationPriority.normal => 'Normal',
        NotificationPriority.information => 'Information',
      };

  static NotificationPriority fromDb(String? value) {
    return switch (value) {
      'critical' => NotificationPriority.critical,
      'high' => NotificationPriority.high,
      'information' => NotificationPriority.information,
      _ => NotificationPriority.normal,
    };
  }
}

/// Canonical notification type keys — domains publish these via NotificationService.
abstract final class NotificationTypes {
  // Orders
  static const orderCreated = 'order_created';
  static const orderSubmitted = 'order_submitted';
  static const orderApproved = 'order_approved';
  static const orderCompleted = 'order_completed';
  static const orderCancelled = 'order_cancelled';

  // Inventory
  static const lowStock = 'low_stock';
  static const outOfStock = 'out_of_stock';
  static const stockAdjusted = 'stock_adjusted';

  // Payments
  static const paymentReceived = 'payment_received';
  static const collectionPendingReview = 'collection_pending_review';
  static const collectionApproved = 'collection_approved';
  static const collectionRejected = 'collection_rejected';
  static const outstandingDue = 'outstanding_due';

  // Customers
  static const customerCreated = 'customer_created';
  static const customerAssigned = 'customer_assigned';
  static const customerArchived = 'customer_archived';

  // Suppliers
  static const supplierCreated = 'supplier_created';

  // Schedule / visits
  static const upcomingVisit = 'upcoming_visit';
  static const missedVisit = 'missed_visit';
  static const visitCompleted = 'visit_completed';
  static const followUpRequired = 'follow_up_required';
  static const visitScheduled = 'visit_scheduled';
  static const routePlanned = 'route_planned';

  // Team
  static const teamMemberInvited = 'team_member_invited';
  static const teamMemberJoined = 'team_member_joined';

  // Products
  static const productCreated = 'product_created';
  static const productUpdated = 'product_updated';
  static const productArchived = 'product_archived';

  // Reliability
  static const syncFailed = 'sync_failed';
  static const syncCompleted = 'sync_completed';
  static const backupCompleted = 'backup_completed';

  // Intelligence
  static const intelligenceInsight = 'intelligence_insight';
  static const intelligenceBriefing = 'intelligence_briefing';
}

/// In-app inbox row.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.companyId,
    required this.recipientEmployeeId,
    required this.category,
    required this.type,
    required this.priority,
    required this.title,
    required this.createdAt,
    this.actorEmployeeId,
    this.body,
    this.referenceType,
    this.referenceId,
    this.routeHint,
    this.readAt,
    this.archivedAt,
    this.snoozedUntil,
  });

  final String id;
  final String companyId;
  final String recipientEmployeeId;
  final String? actorEmployeeId;
  final NotificationCategory category;
  final String type;
  final NotificationPriority priority;
  final String title;
  final String? body;
  final String? referenceType;
  final String? referenceId;
  final String? routeHint;
  final DateTime? readAt;
  final DateTime? archivedAt;
  final DateTime? snoozedUntil;
  final DateTime createdAt;

  bool get isUnread => readAt == null;
  bool get isArchived => archivedAt != null;
  bool get isSnoozed =>
      snoozedUntil != null && snoozedUntil!.isAfter(DateTime.now().toUtc());

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      recipientEmployeeId: json['recipient_employee_id'] as String,
      actorEmployeeId: json['actor_employee_id'] as String?,
      category: NotificationCategory.fromDb(json['category'] as String?),
      type: json['type'] as String? ?? 'unknown',
      priority: NotificationPriority.fromDb(json['priority'] as String?),
      title: json['title'] as String? ?? '',
      body: _blankToNull(json['body'] as String?),
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      routeHint: _blankToNull(json['route_hint'] as String?),
      readAt: _parseDate(json['read_at']),
      archivedAt: _parseDate(json['archived_at']),
      snoozedUntil: _parseDate(json['snoozed_until']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static String? _blankToNull(String? value) {
    final t = value?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  @override
  List<Object?> get props => [id, readAt, archivedAt, snoozedUntil, createdAt];
}

/// Company operational timeline row.
class CompanyActivityEvent extends Equatable {
  const CompanyActivityEvent({
    required this.id,
    required this.companyId,
    required this.category,
    required this.eventType,
    required this.summary,
    required this.createdAt,
    this.actorEmployeeId,
    this.actorName,
    this.referenceType,
    this.referenceId,
  });

  final String id;
  final String companyId;
  final String? actorEmployeeId;
  final String? actorName;
  final NotificationCategory category;
  final String eventType;
  final String summary;
  final String? referenceType;
  final String? referenceId;
  final DateTime createdAt;

  factory CompanyActivityEvent.fromJson(Map<String, dynamic> json) {
    return CompanyActivityEvent(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      actorEmployeeId: json['actor_employee_id'] as String?,
      actorName: json['actor_name'] as String?,
      category: NotificationCategory.fromDb(json['category'] as String?),
      eventType: json['event_type'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, createdAt, summary];
}

/// Per-category channel preferences (in-app live; others reserved).
class NotificationPreference extends Equatable {
  const NotificationPreference({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.category,
    required this.channelInApp,
    this.channelPush = false,
    this.channelEmail = false,
    this.channelSms = false,
    this.channelWhatsapp = false,
  });

  final String id;
  final String companyId;
  final String employeeId;
  final NotificationCategory category;
  final bool channelInApp;
  final bool channelPush;
  final bool channelEmail;
  final bool channelSms;
  final bool channelWhatsapp;

  NotificationPreference copyWith({
    bool? channelInApp,
    bool? channelPush,
    bool? channelEmail,
    bool? channelSms,
    bool? channelWhatsapp,
  }) {
    return NotificationPreference(
      id: id,
      companyId: companyId,
      employeeId: employeeId,
      category: category,
      channelInApp: channelInApp ?? this.channelInApp,
      channelPush: channelPush ?? this.channelPush,
      channelEmail: channelEmail ?? this.channelEmail,
      channelSms: channelSms ?? this.channelSms,
      channelWhatsapp: channelWhatsapp ?? this.channelWhatsapp,
    );
  }

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      employeeId: json['employee_id'] as String,
      category: NotificationCategory.fromDb(json['category'] as String?),
      channelInApp: json['channel_in_app'] as bool? ?? true,
      channelPush: json['channel_push'] as bool? ?? false,
      channelEmail: json['channel_email'] as bool? ?? false,
      channelSms: json['channel_sms'] as bool? ?? false,
      channelWhatsapp: json['channel_whatsapp'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'channel_in_app': channelInApp,
      'channel_push': channelPush,
      'channel_email': channelEmail,
      'channel_sms': channelSms,
      'channel_whatsapp': channelWhatsapp,
    };
  }

  @override
  List<Object?> get props => [
        id,
        category,
        channelInApp,
        channelPush,
        channelEmail,
        channelSms,
        channelWhatsapp,
      ];
}

/// Emit payload used by [NotificationService].
class NotificationEmitInput {
  const NotificationEmitInput({
    required this.category,
    required this.type,
    required this.title,
    this.body,
    this.priority = NotificationPriority.normal,
    this.recipientEmployeeId,
    this.notifyHubRoles = false,
    this.excludeEmployeeId,
    this.referenceType,
    this.referenceId,
    this.routeHint,
    this.logActivity = true,
    this.activitySummary,
  });

  final NotificationCategory category;
  final String type;
  final String title;
  final String? body;
  final NotificationPriority priority;

  /// Single recipient. Ignored when [notifyHubRoles] is true.
  final String? recipientEmployeeId;
  final bool notifyHubRoles;
  final String? excludeEmployeeId;
  final String? referenceType;
  final String? referenceId;
  final String? routeHint;

  /// Also append to company activity feed.
  final bool logActivity;
  final String? activitySummary;
}
