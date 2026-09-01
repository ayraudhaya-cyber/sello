import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/services/intelligence/intelligence_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/sales_day.dart';
import 'package:sello/shared/models/scheduled_visit.dart';

/// Sales Home day companion — loads today's assigned visits for the signed-in
/// employee and merges active / completed operational visits.
final selloHomeDayProvider =
    NotifierProvider<SelloHomeDayNotifier, SalesDaySnapshot>(
  SelloHomeDayNotifier.new,
);

class SelloHomeDayNotifier extends Notifier<SalesDaySnapshot> {
  @override
  SalesDaySnapshot build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous == null
          ? null
          : '${previous.company.id}:${previous.employee.id}';
      final nextKey =
          next == null ? null : '${next.company.id}:${next.employee.id}';
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });
    ref.listen(activeCustomerVisitProvider, (previous, next) {
      // Avoid stacking refreshes when visit clears during finish.
      final prevId = previous?.valueOrNull?.id;
      final nextId = next.valueOrNull?.id;
      if (prevId == nextId) return;
      Future.microtask(refresh);
    });

    Future.microtask(refresh);
    return SalesDaySnapshots.emptyDynamic();
  }

  Future<void> refresh() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = SalesDaySnapshots.emptyDynamic();
      return;
    }

    try {
      final repo = ref.read(visitRepositoryProvider);
      final day = DateTime.now();
      final start = DateTime(day.year, day.month, day.day);

      final scheduledFuture = repo.fetchVisitsForDay(
        companyId: session.company.id,
        day: day,
        employeeId: session.employee.id,
      );
      final operationalFuture = repo.fetchCustomerVisits(
        companyId: session.company.id,
        employeeId: session.employee.id,
        from: start,
        to: start.add(const Duration(days: 1)),
        limit: 100,
      );
      final scheduled = await scheduledFuture;
      final operational = await operationalFuture;

      final activeByCustomer = <String, CustomerVisit>{};
      final completedScheduledIds = <String>{};
      final completedCustomerIds = <String>{};
      for (final visit in operational) {
        if (visit.isActive) {
          activeByCustomer[visit.customerId] = visit;
        } else if (visit.isCompleted) {
          completedCustomerIds.add(visit.customerId);
          if (visit.scheduledVisitId != null) {
            completedScheduledIds.add(visit.scheduledVisitId!);
          }
        }
      }

      final stops = <FieldVisitStop>[];
      final seenCustomers = <String>{};
      String? assignedArea;

      for (final visit in scheduled) {
        if (!visit.isCustomerStop) {
          final area = visit.area?.trim();
          if (area != null && area.isNotEmpty) {
            assignedArea ??= area;
          }
          continue;
        }
        seenCustomers.add(visit.customerId!);
        final active = activeByCustomer[visit.customerId];
        var stop = visit.toFieldVisitStop();
        if (active != null) {
          stop = stop.copyWith(
            status: VisitStopStatus.inProgress,
            badge: VisitBadgeKind.scheduled,
            customerVisitId: active.id,
          );
        } else if (completedScheduledIds.contains(visit.id) ||
            (completedCustomerIds.contains(visit.customerId) &&
                visit.status == VisitStatus.scheduled)) {
          // Prefer operational completion over stale schedule status.
          if (visit.status != VisitStatus.completed) {
            stop = stop.copyWith(
              status: VisitStopStatus.completed,
              badge: VisitBadgeKind.completed,
            );
          }
        }
        stops.add(stop);
      }

      // Unplanned operational visits not tied to today's schedule.
      for (final visit in operational) {
        if (seenCustomers.contains(visit.customerId)) continue;
        if (visit.scheduledVisitId != null) continue;
        stops.add(
          FieldVisitStop(
            id: visit.id,
            customerId: visit.customerId,
            customerVisitId: visit.isActive ? visit.id : null,
            customerName: visit.customerName ?? 'Customer',
            origin: VisitOrigin.unplanned,
            status: visit.isActive
                ? VisitStopStatus.inProgress
                : visit.isCompleted
                    ? VisitStopStatus.completed
                    : VisitStopStatus.skipped,
            badge: visit.isActive
                ? VisitBadgeKind.unplanned
                : visit.isCompleted
                    ? VisitBadgeKind.completed
                    : VisitBadgeKind.followUp,
            lastVisitLabel: visit.outcome?.label,
            sortOrder: 1000 + stops.length,
          ),
        );
      }

      final planned = stops.where((s) => s.isPlanned).toList();
      final completedToday = stops.where((s) => s.isComplete).length;
      final mode = planned.isNotEmpty ||
              (assignedArea != null && assignedArea.trim().isNotEmpty)
          ? SalesDayMode.managerPlanned
          : SalesDayMode.dynamic;

      final settings = ref.read(selloCompanySettingsProvider).valueOrNull ??
          CompanySettings.defaults;
      final branchId = session.branch?.id;

      var lowStock = 0;
      num outstanding = 0;
      num collectedToday = 0;
      var ordersToday = 0;
      final statsFutures = <Future<void>>[];
      if (settings.enableLowStockAlert) {
        statsFutures.add(() async {
          try {
            final inv = await ref
                .read(inventoryRepositoryProvider)
                .fetchDashboardStats(branchId: branchId);
            lowStock = inv.lowStock + inv.outOfStock;
          } catch (_) {}
        }());
      }
      statsFutures.add(() async {
        try {
          final pay =
              await ref.read(paymentRepositoryProvider).fetchDashboardStats();
          collectedToday = pay.collectedToday;
          if (settings.salesCanViewOutstandingBalances) {
            outstanding = pay.outstandingReceivables;
          }
        } catch (_) {}
      }());
      statsFutures.add(() async {
        try {
          final now = DateTime.now();
          final start = DateTime(now.year, now.month, now.day);
          final result = await ref.read(orderRepositoryProvider).fetchOrders(
                employeeId: session.employee.id,
                orderedFrom: start,
                pageSize: 100,
              );
          ordersToday = result.items.length;
        } catch (_) {}
      }());
      await Future.wait(statsFutures);

      final followUpsDue =
          scheduled.where((v) => v.status == VisitStatus.missed).length;
      final visitsLeft = planned
          .where((s) =>
              s.status == VisitStopStatus.pending ||
              s.status == VisitStopStatus.inProgress)
          .length;

      final snapshot = SalesDaySnapshot(
        mode: mode,
        visits: stops,
        assignedArea: assignedArea,
        activity: SalesDayActivity(
          customersVisited: completedToday,
          ordersCreated: ordersToday,
        ),
        insights: SalesDayInsights(
          customerVisitsLeft: visitsLeft,
          followUpsDue: followUpsDue,
          lowStockCount: lowStock,
          outstandingTotal: outstanding,
          todaysSales: collectedToday,
        ),
        showOutstandingBalances: settings.salesCanViewOutstandingBalances,
        intelligenceHints: const [],
      );

      // Compose intelligence from the day context + shared domain stats.
      var hints = snapshot.intelligenceHints;
      try {
        final intel = await ref.read(intelligenceServiceProvider).generate(
              session: session,
              settings: settings,
              salesDay: snapshot,
            );
        hints = intel.insights;
      } catch (_) {}

      state = snapshot.copyWith(intelligenceHints: hints);
    } on AppFailure {
      state = SalesDaySnapshots.emptyDynamic();
    } catch (_) {
      state = SalesDaySnapshots.emptyDynamic();
    }
  }

  /// Switch demo mode (DX / design review).
  void previewMode(SalesDayMode mode) {
    state = switch (mode) {
      SalesDayMode.managerPlanned => SalesDaySnapshots.demoManagerPlanned(),
      SalesDayMode.repPlanned => SalesDaySnapshots.demoRepPlanned(),
      SalesDayMode.dynamic => SalesDaySnapshots.demoDynamic(),
    };
  }

  /// Spontaneous stop — persists as an unplanned schedule marker when needed,
  /// or just refreshes after starting an operational visit elsewhere.
  void recordUnplannedVisit(FieldVisitStop stop) {
    final unplanned = FieldVisitStop(
      id: stop.id,
      customerId: stop.customerId,
      customerVisitId: stop.customerVisitId,
      customerName: stop.customerName,
      origin: VisitOrigin.unplanned,
      status: stop.status,
      badge: VisitBadgeKind.unplanned,
      standingOrder: stop.standingOrder,
      isNewCustomer: stop.isNewCustomer,
      distanceLabel: stop.distanceLabel,
      lastVisitLabel: stop.lastVisitLabel,
      outstandingLabel:
          state.showOutstandingBalances ? stop.outstandingLabel : null,
      sortOrder: state.visits.length,
    );
    state = state.copyWith(
      visits: [...state.visits, unplanned],
      activity: SalesDayActivity(
        customersVisited: state.activity.customersVisited +
            (stop.isComplete ? 1 : 0),
        ordersCreated: state.activity.ordersCreated,
        paymentsCollected: state.activity.paymentsCollected,
      ),
    );
  }
}

/// Placeholder / empty / demo snapshots.
abstract final class SalesDaySnapshots {
  static SalesDaySnapshot emptyDynamic() {
    return const SalesDaySnapshot(
      mode: SalesDayMode.dynamic,
      visits: [],
      activity: SalesDayActivity(),
      insights: SalesDayInsights(),
      intelligenceHints: [],
    );
  }

  static SalesDaySnapshot demoManagerPlanned() {
    return SalesDaySnapshot(
      mode: SalesDayMode.managerPlanned,
      showOutstandingBalances: true,
      insights: const SalesDayInsights(
        customerCount: 86,
        customerVisitsLeft: 3,
        openOrders: 12,
        ordersDueToday: 4,
        productCount: 214,
        lowStockCount: 8,
        outstandingTotal: 18450,
        outstandingDueToday: 4,
        todaysSales: 6250,
        followUpsDue: 5,
        pendingDeliveries: 3,
      ),
      activity: const SalesDayActivity(
        customersVisited: 4,
        ordersCreated: 2,
        paymentsCollected: 1,
      ),
      intelligenceHints: const [],
      visits: const [
        FieldVisitStop(
          id: 'd1',
          customerId: 'c1',
          customerName: 'Harbor Traders',
          origin: VisitOrigin.planned,
          status: VisitStopStatus.pending,
          badge: VisitBadgeKind.priority,
          area: 'Colombo',
          lastVisitLabel: 'Collect payment',
          outstandingLabel: '\$1,240 due',
          sortOrder: 0,
        ),
        FieldVisitStop(
          id: 'd2',
          customerId: 'c2',
          customerName: 'City Mart',
          origin: VisitOrigin.planned,
          status: VisitStopStatus.completed,
          badge: VisitBadgeKind.completed,
          area: 'Colombo',
          sortOrder: 1,
        ),
      ],
    );
  }

  static SalesDaySnapshot demoRepPlanned() {
    return SalesDaySnapshots.demoManagerPlanned().copyWith(
      mode: SalesDayMode.repPlanned,
    );
  }

  static SalesDaySnapshot demoDynamic() {
    return const SalesDaySnapshot(
      mode: SalesDayMode.dynamic,
      visits: [],
      activity: SalesDayActivity(customersVisited: 2),
      insights: SalesDayInsights(customerVisitsLeft: 0),
      intelligenceHints: [],
    );
  }
}
