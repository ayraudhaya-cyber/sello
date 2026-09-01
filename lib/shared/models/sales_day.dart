import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/intelligence_insight.dart';

/// How today's visit list was established for a sales rep.
///
/// Home adapts: progress bar only when a plan exists; otherwise activity.
enum SalesDayMode {
  /// Manager assigned today's customer visits.
  managerPlanned,

  /// Rep prepared today's visit list before starting.
  repPlanned,

  /// No predefined plan — visits are recorded as the day unfolds.
  dynamic,
}

/// Whether a stop was on the morning plan or added in the field.
enum VisitOrigin {
  planned,
  unplanned,
}

enum VisitStopStatus {
  pending,
  inProgress,
  completed,
  skipped,
}

/// Field badge vocabulary for visit rows.
enum VisitBadgeKind {
  priority,
  scheduled,
  followUp,
  completed,
  unplanned,
}

/// One customer stop in today's field work (planned or spontaneous).
class FieldVisitStop extends Equatable {
  const FieldVisitStop({
    required this.id,
    required this.customerName,
    required this.origin,
    required this.status,
    required this.badge,
    this.customerId,
    this.customerVisitId,
    this.standingOrder = false,
    this.isNewCustomer = false,
    this.distanceLabel,
    this.area,
    this.lastVisitLabel,
    this.outstandingLabel,
    this.sortOrder = 0,
  });

  final String id;
  final String? customerId;
  /// Active operational [customer_visits] id when a visit is in progress.
  final String? customerVisitId;
  final String customerName;
  final VisitOrigin origin;
  final VisitStopStatus status;
  final VisitBadgeKind badge;
  final bool standingOrder;
  final bool isNewCustomer;
  final String? distanceLabel;
  /// Locality / coverage area from the schedule (e.g. Colombo).
  final String? area;
  final String? lastVisitLabel;
  final String? outstandingLabel;
  final int sortOrder;

  String? get placeLabel {
    final a = area?.trim();
    if (a != null && a.isNotEmpty) return a;
    final d = distanceLabel?.trim();
    if (d != null && d.isNotEmpty) return d;
    return null;
  }

  bool get isPlanned => origin == VisitOrigin.planned;
  bool get isUnplanned => origin == VisitOrigin.unplanned;
  bool get isComplete => status == VisitStopStatus.completed;
  bool get isInProgress => status == VisitStopStatus.inProgress;

  List<String> get metaParts {
    return [
      ?distanceLabel,
      if (standingOrder) 'Standing order',
      if (isNewCustomer) 'New customer',
      ?outstandingLabel,
      ?lastVisitLabel,
    ];
  }

  FieldVisitStop copyWith({
    VisitStopStatus? status,
    VisitBadgeKind? badge,
    String? customerVisitId,
    String? area,
    bool clearCustomerVisitId = false,
  }) {
    return FieldVisitStop(
      id: id,
      customerId: customerId,
      customerVisitId: clearCustomerVisitId
          ? null
          : (customerVisitId ?? this.customerVisitId),
      customerName: customerName,
      origin: origin,
      status: status ?? this.status,
      badge: badge ?? this.badge,
      standingOrder: standingOrder,
      isNewCustomer: isNewCustomer,
      distanceLabel: distanceLabel,
      area: area ?? this.area,
      lastVisitLabel: lastVisitLabel,
      outstandingLabel: outstandingLabel,
      sortOrder: sortOrder,
    );
  }

  @override
  List<Object?> get props => [
        id,
        customerId,
        customerVisitId,
        customerName,
        origin,
        status,
        badge,
        standingOrder,
        isNewCustomer,
        distanceLabel,
        area,
        lastVisitLabel,
        outstandingLabel,
        sortOrder,
      ];
}

/// Lightweight day totals when there is no visit plan (dynamic day).
class SalesDayActivity extends Equatable {
  const SalesDayActivity({
    this.customersVisited = 0,
    this.ordersCreated = 0,
    this.paymentsCollected = 0,
  });

  final int customersVisited;
  final int ordersCreated;
  final int paymentsCollected;

  bool get isEmpty =>
      customersVisited == 0 && ordersCreated == 0 && paymentsCollected == 0;

  @override
  List<Object?> get props =>
      [customersVisited, ordersCreated, paymentsCollected];
}

/// Actionable operational insights for Home summary cards (not analytics KPIs).
class SalesDayInsights extends Equatable {
  const SalesDayInsights({
    this.customerCount = 0,
    this.customerVisitsLeft = 0,
    this.openOrders = 0,
    this.ordersDueToday = 0,
    this.productCount = 0,
    this.lowStockCount = 0,
    this.outstandingTotal = 0,
    this.outstandingDueToday = 0,
    this.todaysSales = 0,
    this.followUpsDue = 0,
    this.pendingDeliveries = 0,
  });

  final int customerCount;
  final int customerVisitsLeft;
  final int openOrders;
  final int ordersDueToday;
  final int productCount;
  final int lowStockCount;

  /// Receivables visible only when company allows Sales balance access.
  final num outstandingTotal;
  final int outstandingDueToday;

  final num todaysSales;
  final int followUpsDue;
  final int pendingDeliveries;

  @override
  List<Object?> get props => [
        customerCount,
        customerVisitsLeft,
        openOrders,
        ordersDueToday,
        productCount,
        lowStockCount,
        outstandingTotal,
        outstandingDueToday,
        todaysSales,
        followUpsDue,
        pendingDeliveries,
      ];
}

/// Optional Sello Intelligence suggestions for today's visit list.
/// Prefer [IntelligenceInsight] — kept as a typedef for call-site clarity.
typedef SalesIntelligenceHint = IntelligenceInsight;

/// Snapshot of a sales rep's working day — drives Home companion UI.
class SalesDaySnapshot extends Equatable {
  const SalesDaySnapshot({
    required this.mode,
    required this.visits,
    required this.activity,
    required this.insights,
    this.assignedArea,
    this.showOutstandingBalances = true,
    this.intelligenceHints = const [],
  });

  final SalesDayMode mode;
  final List<FieldVisitStop> visits;
  final SalesDayActivity activity;
  final SalesDayInsights insights;

  /// Territory / area assigned for the day when the plan has no (or extra) stops.
  final String? assignedArea;
  final bool showOutstandingBalances;
  final List<IntelligenceInsight> intelligenceHints;

  /// True when a morning plan exists (manager- or rep-authored).
  ///
  /// Progress UI is only truthful when this is true — never fabricate from
  /// customers/orders totals.
  bool get hasAssignedArea =>
      assignedArea != null && assignedArea!.trim().isNotEmpty;

  bool get hasVisitPlan =>
      mode != SalesDayMode.dynamic &&
      (plannedVisits.isNotEmpty || hasAssignedArea);

  List<FieldVisitStop> get plannedVisits =>
      visits.where((v) => v.isPlanned).toList(growable: false);

  List<FieldVisitStop> get unplannedVisits =>
      visits.where((v) => v.isUnplanned).toList(growable: false);

  int get plannedCount => plannedVisits.length;

  int get plannedCompletedCount =>
      plannedVisits.where((v) => v.isComplete).length;

  int get plannedRemainingCount =>
      plannedCount - plannedCompletedCount;

  int get unplannedCount => unplannedVisits.length;

  int get unplannedCompletedCount =>
      unplannedVisits.where((v) => v.isComplete).length;

  /// Primary shop the rep should act on now (active visit, else next pending).
  FieldVisitStop? get focusStop {
    final active = visits.where((v) => v.isInProgress).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (active.isNotEmpty) return active.first;
    final pending = homeVisitQueue;
    return pending.isEmpty ? null : pending.first;
  }

  /// True when a plan exists and every planned stop is done.
  bool get isPlanComplete =>
      hasVisitPlan && plannedCount > 0 && plannedRemainingCount == 0;

  /// Dominant coverage area when planned stops share one locality.
  String? get primaryArea {
    if (hasAssignedArea) return assignedArea!.trim();
    final areas = plannedVisits
        .map((v) => v.area?.trim())
        .whereType<String>()
        .where((a) => a.isNotEmpty)
        .toSet();
    if (areas.length == 1) return areas.first;
    return null;
  }

  /// Compact workload line for Home greeting.
  String get homeWorkloadLabel {
    final actualDone = plannedCompletedCount + unplannedCompletedCount;
    final walkIns = unplannedCompletedCount;

    if (!hasVisitPlan) {
      if (actualDone == 0) return 'Ready when you are';
      if (walkIns > 0 && walkIns == actualDone) {
        return actualDone == 1
            ? '1 walk-in today'
            : '$actualDone walk-ins today';
      }
      return actualDone == 1 ? '1 visit today' : '$actualDone visits today';
    }

    if (plannedCount == 0 && hasAssignedArea) {
      return assignedArea!.trim();
    }

    if (isPlanComplete) {
      if (walkIns > 0) {
        return 'Plan done · $walkIns walk-in${walkIns == 1 ? '' : 's'}';
      }
      return actualDone == 0
          ? 'Plan done'
          : 'Plan done · $actualDone visit${actualDone == 1 ? '' : 's'}';
    }

    final parts = <String>['$plannedCount planned'];
    if (actualDone > 0) parts.add('$actualDone done');
    if (walkIns > 0 && plannedCompletedCount > 0) {
      // already counted in done — no extra part
    } else if (walkIns > 0 && plannedCompletedCount == 0) {
      parts.add('$walkIns walk-in${walkIns == 1 ? '' : 's'}');
    }
    return parts.join(' · ');
  }

  /// Relevant planned / in-progress stops for Home — never the full route.
  List<FieldVisitStop> homePlanPreview({int maxItems = 3}) {
    final inProgress = visits.where((v) => v.isInProgress).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final pendingPlanned = plannedVisits
        .where((v) => v.status == VisitStopStatus.pending)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final skipped = plannedVisits
        .where((v) => v.status == VisitStopStatus.skipped)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final out = <FieldVisitStop>[];
    void addUnique(FieldVisitStop stop) {
      if (out.any((s) => s.id == stop.id)) return;
      if (out.length >= maxItems) return;
      out.add(stop);
    }

    for (final s in inProgress) {
      addUnique(s);
    }
    if (skipped.isNotEmpty) addUnique(skipped.first);
    for (final s in pendingPlanned) {
      addUnique(s);
    }
    return out;
  }

  /// How many open planned stops are not shown in [homePlanPreview].
  int homePlanHiddenCount({int maxItems = 3}) {
    final openPlanned = plannedVisits
        .where((v) =>
            v.status == VisitStopStatus.pending ||
            v.status == VisitStopStatus.inProgress ||
            v.status == VisitStopStatus.skipped)
        .length;
    final shown = homePlanPreview(maxItems: maxItems)
        .where((v) => v.isPlanned)
        .length;
    final hidden = openPlanned - shown;
    return hidden < 0 ? 0 : hidden;
  }

  /// Actual visits completed today (planned + unplanned).
  int get actualVisitsCompleted =>
      plannedCompletedCount + unplannedCompletedCount;

  /// Ordered route for the workday companion — planned first, then extras.
  List<FieldVisitStop> get todaysRoute {
    final planned = [...plannedVisits]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final extras = unplannedVisits
        .where((v) =>
            v.isInProgress ||
            v.isComplete ||
            v.status == VisitStopStatus.pending)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [...planned, ...extras];
  }

  /// Stops to surface on Home: in-progress first, then pending planned, then unplanned.
  List<FieldVisitStop> get homeVisitQueue {
    final inProgress = visits
        .where((v) => v.status == VisitStopStatus.inProgress)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final pendingPlanned = plannedVisits
        .where((v) => v.status == VisitStopStatus.pending)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final unplanned = unplannedVisits
        .where((v) =>
            v.status == VisitStopStatus.pending ||
            v.status == VisitStopStatus.inProgress)
        .where((v) => v.status != VisitStopStatus.inProgress ||
            !inProgress.any((p) => p.id == v.id))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    // Avoid duplicating in-progress stops already listed.
    final unplannedPending = unplanned
        .where((v) => v.status == VisitStopStatus.pending)
        .toList();
    return [...inProgress, ...pendingPlanned, ...unplannedPending];
  }

  /// Planned Visits summary value — plan size when planned, else actual visits.
  int get visitsCardValue =>
      hasVisitPlan ? plannedCount : activity.customersVisited;

  String get visitsCardTrend {
    if (hasVisitPlan) {
      final left = plannedRemainingCount;
      if (left == 0) return 'Plan complete';
      return left == plannedCount
          ? '$plannedCount scheduled today'
          : '$left still planned';
    }
    if (activity.customersVisited == 0) return 'No visits yet';
    return '${activity.customersVisited} recorded today';
  }

  /// Greeting line under the welcome — keep light; schedule owns visit detail.
  String get greetingSubtitle {
    if (hasVisitPlan && plannedCount == 0 && hasAssignedArea) {
      return assignedArea!.trim();
    }
    if (hasVisitPlan && plannedRemainingCount > 0) {
      final done = plannedCompletedCount;
      if (done == 0) {
        return plannedCount == 1
            ? '1 visit planned today'
            : '$plannedCount visits planned today';
      }
      return '$done visit${done == 1 ? '' : 's'} completed · '
          '$plannedRemainingCount remaining';
    }
    if (hasVisitPlan) return 'Plan done';
    return 'Ready when you are';
  }

  String get plannedSectionSubtitle {
    if (hasVisitPlan) {
      final parts = <String>[
        if (plannedRemainingCount > 0)
          '$plannedRemainingCount left'
        else
          'All done',
        if (unplannedCount > 0) '$unplannedCount extra',
      ];
      return parts.join(' · ');
    }
    return '';
  }

  SalesDaySnapshot copyWith({
    SalesDayMode? mode,
    List<FieldVisitStop>? visits,
    SalesDayActivity? activity,
    SalesDayInsights? insights,
    bool? showOutstandingBalances,
    String? assignedArea,
    List<IntelligenceInsight>? intelligenceHints,
  }) {
    return SalesDaySnapshot(
      mode: mode ?? this.mode,
      visits: visits ?? this.visits,
      activity: activity ?? this.activity,
      insights: insights ?? this.insights,
      assignedArea: assignedArea ?? this.assignedArea,
      showOutstandingBalances:
          showOutstandingBalances ?? this.showOutstandingBalances,
      intelligenceHints: intelligenceHints ?? this.intelligenceHints,
    );
  }

  @override
  List<Object?> get props => [
        mode,
        visits,
        activity,
        insights,
        assignedArea,
        showOutstandingBalances,
        intelligenceHints,
      ];
}
