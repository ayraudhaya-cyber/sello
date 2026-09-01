import 'package:equatable/equatable.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/shared/models/user_role.dart';

/// Domain buckets for operational intelligence — not chat topics.
enum IntelligenceCategory {
  sales,
  customers,
  inventory,
  payments,
  orders,
  schedules,
  customerVisits,
  salesRepresentatives,
  forecasts,
  recommendations,
}

extension IntelligenceCategoryX on IntelligenceCategory {
  String get label => switch (this) {
        IntelligenceCategory.sales => 'Sales',
        IntelligenceCategory.customers => 'Customers',
        IntelligenceCategory.inventory => 'Inventory',
        IntelligenceCategory.payments => 'Payments',
        IntelligenceCategory.orders => 'Orders',
        IntelligenceCategory.schedules => 'Schedules',
        IntelligenceCategory.customerVisits => 'Customer Visits',
        IntelligenceCategory.salesRepresentatives => 'Sales Representatives',
        IntelligenceCategory.forecasts => 'Forecasts',
        IntelligenceCategory.recommendations => 'Recommendations',
      };
}

/// Clear next step every insight must offer ("So what should I do?").
enum IntelligenceActionKind {
  reviewInventory,
  scheduleVisit,
  openCustomer,
  receivePayment,
  openReport,
  openOrders,
  openSchedule,
  openVisits,
  openPayments,
  openProducts,
  reviewTeam,
}

extension IntelligenceActionKindX on IntelligenceActionKind {
  String get label => switch (this) {
        IntelligenceActionKind.reviewInventory => 'Check Stock',
        IntelligenceActionKind.scheduleVisit => 'Plan a Visit',
        IntelligenceActionKind.openCustomer => 'View Customer',
        IntelligenceActionKind.receivePayment => 'Collect Payment',
        IntelligenceActionKind.openReport => 'See Reports',
        IntelligenceActionKind.openOrders => 'View Orders',
        IntelligenceActionKind.openSchedule => 'View Schedule',
        IntelligenceActionKind.openVisits => 'View Visits',
        IntelligenceActionKind.openPayments => 'View Payments',
        IntelligenceActionKind.openProducts => 'View Products',
        IntelligenceActionKind.reviewTeam => 'View Team',
      };

  /// Role-aware deep link — Hub vs Sales workspaces.
  String routeFor(UserRole role) {
    final hub = role.usesHub;
    return switch (this) {
      IntelligenceActionKind.reviewInventory =>
        hub ? RoutePaths.hubInventory : RoutePaths.selloInventory,
      IntelligenceActionKind.scheduleVisit =>
        hub ? RoutePaths.hubSchedule : RoutePaths.selloDashboard,
      IntelligenceActionKind.openCustomer =>
        hub ? RoutePaths.hubCustomers : RoutePaths.selloCustomers,
      IntelligenceActionKind.receivePayment =>
        hub ? RoutePaths.hubPayments : RoutePaths.selloCustomers,
      IntelligenceActionKind.openReport =>
        hub ? RoutePaths.hubReports : RoutePaths.selloDashboard,
      IntelligenceActionKind.openOrders =>
        hub ? RoutePaths.hubOrders : RoutePaths.selloOrders,
      IntelligenceActionKind.openSchedule =>
        hub ? RoutePaths.hubSchedule : RoutePaths.selloDashboard,
      IntelligenceActionKind.openVisits =>
        hub ? RoutePaths.hubVisits : RoutePaths.selloDashboard,
      IntelligenceActionKind.openPayments =>
        hub ? RoutePaths.hubPayments : RoutePaths.selloCustomers,
      IntelligenceActionKind.openProducts =>
        hub ? RoutePaths.hubProducts : RoutePaths.selloProducts,
      IntelligenceActionKind.reviewTeam =>
        hub ? RoutePaths.hubEmployees : RoutePaths.selloProfile,
    };
  }
}

/// Future briefing windows — daily / weekly digests (not conversational).
enum IntelligenceBriefingKind { daily, weekly }

/// One proactive, actionable insight — the unit of Sello Intelligence.
class IntelligenceInsight extends Equatable {
  const IntelligenceInsight({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.action,
    required this.priority,
    this.metricLabel,
    this.referenceType,
    this.referenceId,
    this.customerName,
  });

  final String id;
  final IntelligenceCategory category;

  /// Short headline — what is happening.
  final String title;

  /// Why it matters / supporting detail.
  final String message;

  final IntelligenceActionKind action;

  /// Lower = more urgent. Engine keeps the top few by this order.
  final int priority;

  /// Optional compact metric for Action Center rows (e.g. "Rs 12,400").
  final String? metricLabel;

  final String? referenceType;
  final String? referenceId;
  final String? customerName;

  String get actionLabel => action.label;

  String routeFor(UserRole role) => action.routeFor(role);

  @override
  List<Object?> get props => [
        id,
        category,
        title,
        message,
        action,
        priority,
        metricLabel,
        referenceType,
        referenceId,
        customerName,
      ];
}

/// Ranked insight set for a role at a point in time.
class IntelligenceSnapshot extends Equatable {
  const IntelligenceSnapshot({
    required this.insights,
    required this.generatedAt,
    this.role,
    this.briefing,
  });

  factory IntelligenceSnapshot.empty({UserRole? role}) => IntelligenceSnapshot(
        insights: const [],
        generatedAt: DateTime.now(),
        role: role,
      );

  final List<IntelligenceInsight> insights;
  final DateTime generatedAt;
  final UserRole? role;

  /// Reserved — AI / rule-based daily or weekly business briefing.
  final IntelligenceBriefing? briefing;

  bool get isEmpty => insights.isEmpty;
  bool get isNotEmpty => insights.isNotEmpty;

  IntelligenceInsight? get primary =>
      insights.isEmpty ? null : insights.first;

  @override
  List<Object?> get props => [insights, generatedAt, role, briefing];
}

/// Future-ready daily / weekly summary seam (AI or rules later).
class IntelligenceBriefing extends Equatable {
  const IntelligenceBriefing({
    required this.kind,
    required this.headline,
    required this.summary,
    this.generatedAt,
  });

  final IntelligenceBriefingKind kind;
  final String headline;
  final String summary;
  final DateTime? generatedAt;

  @override
  List<Object?> get props => [kind, headline, summary, generatedAt];
}
