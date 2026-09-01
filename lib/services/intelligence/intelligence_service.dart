import 'package:sello/data/repositories/employee_repository.dart';
import 'package:sello/data/repositories/inventory_repository.dart';
import 'package:sello/data/repositories/order_repository.dart';
import 'package:sello/data/repositories/payment_repository.dart';
import 'package:sello/data/repositories/report_repository.dart';
import 'package:sello/data/repositories/visit_repository.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/intelligence_insight.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/models/sales_day.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Proactive operational intelligence — composes domain repos; no parallel math.
///
/// Not a chatbot. Surfaces a short ranked list of actionable insights so owners,
/// managers, and sales reps know what to do next.
///
/// Future seams (stubs only): AI summaries, forecasting, NL search, voice,
/// automated recommendations, daily / weekly briefings.
class IntelligenceService {
  IntelligenceService({
    InventoryRepository? inventory,
    PaymentRepository? payments,
    OrderRepository? orders,
    VisitRepository? visits,
    EmployeeRepository? employees,
    ReportRepository? reports,
  })  : _inventory = inventory ?? InventoryRepository(),
        _payments = payments ?? PaymentRepository(),
        _orders = orders ?? OrderRepository(),
        _visits = visits ?? VisitRepository(),
        _employees = employees ?? EmployeeRepository(),
        _reports = reports ?? ReportRepository();

  final InventoryRepository _inventory;
  final PaymentRepository _payments;
  final OrderRepository _orders;
  final VisitRepository _visits;
  final EmployeeRepository _employees;
  final ReportRepository _reports;

  /// Default quality cap — never overwhelm the surface.
  static const int defaultLimit = 5;

  /// Build role-aware insights from existing business stats and day context.
  Future<IntelligenceSnapshot> generate({
    required AppSession session,
    CompanySettings settings = CompanySettings.defaults,
    SalesDaySnapshot? salesDay,
    int limit = defaultLimit,
  }) async {
    final role = session.appRole;
    final branchId = session.branch?.id;
    final currency = SelloFormatters.currencySymbol(settings.currency);
    final candidates = <IntelligenceInsight>[];

    try {
      switch (role) {
        case UserRole.owner:
          candidates.addAll(
            await _ownerCandidates(
              companyId: session.company.id,
              branchId: branchId,
              currency: currency,
              settings: settings,
            ),
          );
        case UserRole.manager:
          candidates.addAll(
            await _managerCandidates(
              companyId: session.company.id,
              branchId: branchId,
              currency: currency,
              settings: settings,
            ),
          );
        case UserRole.salesRepresentative:
          candidates.addAll(
            await _salesCandidates(
              companyId: session.company.id,
              employeeId: session.employee.id,
              branchId: branchId,
              currency: currency,
              settings: settings,
              salesDay: salesDay,
            ),
          );
      }
    } catch (_) {
      // Intelligence is additive — surfaces stay usable if a source fails.
    }

    candidates.sort((a, b) => a.priority.compareTo(b.priority));
    final capped = candidates.take(limit.clamp(1, defaultLimit)).toList();

    return IntelligenceSnapshot(
      insights: capped,
      generatedAt: DateTime.now(),
      role: role,
      // Daily / weekly AI briefings land here later.
      briefing: null,
    );
  }

  /// Reserved — predictive / AI forecast cards. Returns empty until enabled.
  Future<List<IntelligenceInsight>> forecastHints({
    required AppSession session,
  }) async {
    return const [];
  }

  /// Reserved — natural-language business search over insights / domains.
  Future<List<IntelligenceInsight>> searchInsights({
    required AppSession session,
    required String query,
  }) async {
    return const [];
  }

  /// Reserved — daily or weekly business briefing (rules or AI later).
  Future<IntelligenceBriefing?> briefing({
    required AppSession session,
    IntelligenceBriefingKind kind = IntelligenceBriefingKind.daily,
  }) async {
    return null;
  }

  // ── Owner: sales trends, inventory, collections, growth ─────────────────

  Future<List<IntelligenceInsight>> _ownerCandidates({
    required String companyId,
    String? branchId,
    required String currency,
    required CompanySettings settings,
  }) async {
    final out = <IntelligenceInsight>[];

    // Prefer shared analytics overview — same math as Hub Reports.
    ReportsOverview? overview;
    try {
      overview = await _reports.fetchOverview(
        companyId: companyId,
        branchId: branchId,
        preset: ReportDatePreset.thisMonth,
        query: ReportQuery(
          preset: ReportDatePreset.thisMonth,
          branchId: branchId,
        ),
      );
    } catch (_) {
      overview = null;
    }

    final inventory = overview?.inventory ??
        await _inventory.fetchDashboardStats(branchId: branchId);
    final payments =
        overview?.payments ?? await _payments.fetchDashboardStats();
    final visitStats = await _visits.fetchDashboardStats(companyId: companyId);
    final orderCounts = overview?.orderCounts ?? await _orders.fetchCounts();

    if (inventory.outOfStock > 0) {
      final n = inventory.outOfStock;
      out.add(
        IntelligenceInsight(
          id: 'inv_out_of_stock',
          category: IntelligenceCategory.inventory,
          title: '$n ${n == 1 ? 'product is' : 'products are'} out of stock',
          message: n == 1
              ? 'Customers can\'t buy what\'s missing — restock it, or hide '
                  'it from your catalog until it\'s back.'
              : 'Customers can\'t buy what\'s missing — restock these, or hide '
                  'them from your catalog until they\'re back.',
          action: IntelligenceActionKind.reviewInventory,
          priority: 10,
          metricLabel: '$n',
        ),
      );
    } else if (inventory.lowStock > 0) {
      final n = inventory.lowStock;
      out.add(
        IntelligenceInsight(
          id: 'inv_low_stock',
          category: IntelligenceCategory.inventory,
          title: '$n ${n == 1 ? 'product is' : 'products are'} running low',
          message:
              'Stock is at or below your reorder level. Check these before '
              'you run out during busy days.',
          action: IntelligenceActionKind.reviewInventory,
          priority: 20,
          metricLabel: '$n',
        ),
      );
    }

    if (payments.outstandingReceivables > 0) {
      out.add(
        IntelligenceInsight(
          id: 'pay_outstanding',
          category: IntelligenceCategory.payments,
          title: 'Money still owed by customers',
          message:
              '${_money(payments.outstandingReceivables, currency)} hasn\'t '
              'been paid yet. Follow up so cash comes in sooner.',
          action: IntelligenceActionKind.openPayments,
          priority: 15,
          metricLabel: _money(payments.outstandingReceivables, currency),
        ),
      );
    }

    if (visitStats.missed > 0) {
      final n = visitStats.missed;
      out.add(
        IntelligenceInsight(
          id: 'visit_missed_today',
          category: IntelligenceCategory.schedules,
          title: '$n missed ${n == 1 ? 'visit' : 'visits'} today',
          message:
              'A planned stop didn\'t happen. Reschedule or check in with '
              'the customer so the relationship stays strong.',
          action: IntelligenceActionKind.openSchedule,
          priority: 25,
          metricLabel: '$n',
        ),
      );
    }

    if (overview != null &&
        overview.visitsCompleted > 0 &&
        overview.visitConversionRate < 0.35) {
      final pct = (overview.visitConversionRate * 100).round();
      out.add(
        IntelligenceInsight(
          id: 'visit_conversion_low',
          category: IntelligenceCategory.customerVisits,
          title: 'Few visits are turning into orders',
          message:
              'Only $pct% of completed visits this month led to an order. '
              'Review what happened on those stops and how the team can '
              'close more sales.',
          action: IntelligenceActionKind.openVisits,
          priority: 28,
          metricLabel: '$pct%',
        ),
      );
    }

    if (overview != null && overview.salesInPeriod > 0) {
      final orders = overview.ordersInPeriod;
      final orderWord = orders == 1 ? 'order' : 'orders';
      out.add(
        IntelligenceInsight(
          id: 'sales_period_pulse',
          category: IntelligenceCategory.sales,
          title: 'Revenue this month',
          message:
              'You\'ve earned ${_money(overview.salesInPeriod, currency)} '
              'from $orders completed $orderWord.\n'
              'Average order: ${_money(overview.averageOrderValue, currency)}.',
          action: IntelligenceActionKind.openReport,
          priority: 45,
          metricLabel: _money(overview.salesInPeriod, currency),
        ),
      );
    }

    if (orderCounts.draft > 0) {
      final n = orderCounts.draft;
      out.add(
        IntelligenceInsight(
          id: 'orders_draft',
          category: IntelligenceCategory.orders,
          title: '$n unfinished ${n == 1 ? 'order' : 'orders'}',
          message:
              'These drafts aren\'t complete yet. Finish them so you can '
              'deliver and get paid.',
          action: IntelligenceActionKind.openOrders,
          priority: 35,
          metricLabel: '$n',
        ),
      );
    }

    try {
      final inactive = overview?.inactiveCustomers.isNotEmpty == true
          ? overview!.inactiveCustomers.take(3).toList()
          : await _reports.fetchInactiveCustomers(limit: 3);
      if (inactive.isNotEmpty) {
        final top = inactive.first;
        out.add(
          IntelligenceInsight(
            id: 'cust_inactive',
            category: IntelligenceCategory.customers,
            title: inactive.length == 1
                ? 'A customer has gone quiet'
                : '${inactive.length}+ customers have gone quiet',
            message:
                '${top.name}${inactive.length > 1 ? ' and others' : ''} '
                'haven\'t ordered in a while. A visit or call can bring '
                'them back.',
            action: IntelligenceActionKind.scheduleVisit,
            priority: 40,
            customerName: top.name,
            referenceType: 'customer',
            referenceId: top.id,
          ),
        );
      }
    } catch (_) {}

    if (payments.collectedToday > 0) {
      out.add(
        IntelligenceInsight(
          id: 'sales_collections_today',
          category: IntelligenceCategory.sales,
          title: 'Payments collected today',
          message:
              'You\'ve taken in ${_money(payments.collectedToday, currency)} '
              'so far today. Open reports to see how that compares with '
              'other days.',
          action: IntelligenceActionKind.openReport,
          priority: 55,
          metricLabel: _money(payments.collectedToday, currency),
        ),
      );
    }

    return out;
  }

  // ── Manager: team, schedule coverage, outstanding field work ────────────

  Future<List<IntelligenceInsight>> _managerCandidates({
    required String companyId,
    String? branchId,
    required String currency,
    required CompanySettings settings,
  }) async {
    final out = <IntelligenceInsight>[];

    final visitStats = await _visits.fetchDashboardStats(companyId: companyId);
    final payments = await _payments.fetchDashboardStats();
    final inventory = await _inventory.fetchDashboardStats(branchId: branchId);
    final orderCounts = await _orders.fetchCounts();

    if (visitStats.missed > 0) {
      final n = visitStats.missed;
      out.add(
        IntelligenceInsight(
          id: 'mgr_missed_visits',
          category: IntelligenceCategory.schedules,
          title: '$n missed ${n == 1 ? 'visit' : 'visits'}',
          message:
              'Reassign or reschedule so customers still get a visit today.',
          action: IntelligenceActionKind.openSchedule,
          priority: 10,
          metricLabel: '$n',
        ),
      );
    }

    final remaining =
        (visitStats.scheduled - visitStats.completed).clamp(0, 9999);
    if (remaining > 0) {
      out.add(
        IntelligenceInsight(
          id: 'mgr_visits_remaining',
          category: IntelligenceCategory.customerVisits,
          title:
              '$remaining scheduled ${remaining == 1 ? 'visit' : 'visits'} still open',
          message:
              'Check who still needs to finish their plan and offer help '
              'where it\'s needed.',
          action: IntelligenceActionKind.openVisits,
          priority: 20,
          metricLabel: '$remaining',
        ),
      );
    }

    if (payments.outstandingReceivables > 0) {
      out.add(
        IntelligenceInsight(
          id: 'mgr_outstanding',
          category: IntelligenceCategory.payments,
          title: 'Money still owed by customers',
          message:
              '${_money(payments.outstandingReceivables, currency)} is still '
              'unpaid. Ask the team to follow up on the largest amounts first.',
          action: IntelligenceActionKind.openPayments,
          priority: 25,
          metricLabel: _money(payments.outstandingReceivables, currency),
        ),
      );
    }

    if (inventory.lowStock + inventory.outOfStock > 0) {
      final n = inventory.lowStock + inventory.outOfStock;
      out.add(
        IntelligenceInsight(
          id: 'mgr_stock',
          category: IntelligenceCategory.inventory,
          title: '$n ${n == 1 ? 'product needs' : 'products need'} stock attention',
          message:
              'Some items are low or sold out. Fix stock before today\'s '
              'orders get held up.',
          action: IntelligenceActionKind.reviewInventory,
          priority: 30,
          metricLabel: '$n',
        ),
      );
    }

    if (orderCounts.draft > 0) {
      final n = orderCounts.draft;
      out.add(
        IntelligenceInsight(
          id: 'mgr_draft_orders',
          category: IntelligenceCategory.orders,
          title: '$n unfinished ${n == 1 ? 'order' : 'orders'}',
          message:
              'Finish these drafts so the team can deliver and collect payment.',
          action: IntelligenceActionKind.openOrders,
          priority: 35,
          metricLabel: '$n',
        ),
      );
    }

    try {
      final team = await _employees.fetchDashboardStats(companyId: companyId);
      if (team.salesRepresentatives > 0) {
        final n = team.salesRepresentatives;
        out.add(
          IntelligenceInsight(
            id: 'mgr_team',
            category: IntelligenceCategory.salesRepresentatives,
            title: '$n sales ${n == 1 ? 'person' : 'people'} on your team',
            message:
                'Review who is assigned where and who still has open work '
                'today.',
            action: IntelligenceActionKind.reviewTeam,
            priority: 60,
            metricLabel: '$n',
          ),
        );
      }
    } catch (_) {}

    return out;
  }

  // ── Sales: today priorities, follow-ups, collections, stock ─────────────

  Future<List<IntelligenceInsight>> _salesCandidates({
    required String companyId,
    required String employeeId,
    String? branchId,
    required String currency,
    required CompanySettings settings,
    SalesDaySnapshot? salesDay,
  }) async {
    final out = <IntelligenceInsight>[];
    final day = salesDay;

    final followUps = day?.insights.followUpsDue ?? 0;
    if (followUps > 0) {
      out.add(
        IntelligenceInsight(
          id: 'sales_followups',
          category: IntelligenceCategory.schedules,
          title:
              '$followUps follow-up${followUps == 1 ? '' : 's'} due today',
          message:
              'A customer needs a quick check-in. Reach out today so nothing '
              'slips.',
          action: IntelligenceActionKind.openCustomer,
          priority: 10,
          metricLabel: '$followUps',
        ),
      );
    }

    final remaining = day?.plannedRemainingCount ?? 0;
    if (day != null && day.hasVisitPlan && remaining > 0) {
      out.add(
        IntelligenceInsight(
          id: 'sales_plan_left',
          category: IntelligenceCategory.customerVisits,
          title:
              '$remaining ${remaining == 1 ? 'stop' : 'stops'} left on today’s plan',
          message:
              'Finish your planned visits first, then add any extra stops.',
          action: IntelligenceActionKind.openVisits,
          priority: 15,
          metricLabel: '$remaining',
        ),
      );
    }

    if (settings.salesCanViewOutstandingBalances) {
      try {
        final payments = await _payments.fetchDashboardStats();
        if (payments.outstandingReceivables > 0) {
          // Prefer a concrete customer from today’s queue when labelled.
          final stopWithBalance = day?.homeVisitQueue
              .where((s) =>
                  s.outstandingLabel != null &&
                  s.outstandingLabel!.trim().isNotEmpty)
              .firstOrNull;
          if (stopWithBalance != null) {
            out.add(
              IntelligenceInsight(
                id: 'sales_collect_${stopWithBalance.customerId ?? stopWithBalance.id}',
                category: IntelligenceCategory.payments,
                title: 'Collect payment from ${stopWithBalance.customerName}',
                message:
                    'They still owe ${stopWithBalance.outstandingLabel}. '
                    'Ask for payment while you\'re there.',
                action: IntelligenceActionKind.receivePayment,
                priority: 12,
                customerName: stopWithBalance.customerName,
                referenceType: 'customer',
                referenceId: stopWithBalance.customerId,
                metricLabel: stopWithBalance.outstandingLabel,
              ),
            );
          } else {
            out.add(
              IntelligenceInsight(
                id: 'sales_outstanding',
                category: IntelligenceCategory.payments,
                title: 'Customers still owe money',
                message:
                    '${_money(payments.outstandingReceivables, currency)} is '
                    'unpaid across customers. Collect what you can on your '
                    'visits today.',
                action: IntelligenceActionKind.receivePayment,
                priority: 18,
                metricLabel: _money(payments.outstandingReceivables, currency),
              ),
            );
          }
        }
      } catch (_) {}
    }

    if (settings.enableLowStockAlert) {
      try {
        final inventory =
            await _inventory.fetchDashboardStats(branchId: branchId);
        if (inventory.lowStock + inventory.outOfStock > 0) {
          final n = inventory.lowStock + inventory.outOfStock;
          out.add(
            IntelligenceInsight(
              id: 'sales_low_stock',
              category: IntelligenceCategory.inventory,
              title:
                  '$n ${n == 1 ? 'product is' : 'products are'} low or out of stock',
              message:
                  'Check stock before you promise an item, so customers '
                  'aren\'t disappointed.',
              action: IntelligenceActionKind.reviewInventory,
              priority: 45,
              metricLabel: '$n',
            ),
          );
        }
      } catch (_) {}
    }

    // Suggested next customer from remaining plan (no GPS ranking yet).
    final nextStop = day?.homeVisitQueue
        .where((s) => s.status == VisitStopStatus.pending)
        .firstOrNull;
    if (nextStop != null &&
        !out.any((i) => i.id.startsWith('sales_collect_${nextStop.customerId}'))) {
      out.add(
        IntelligenceInsight(
          id: 'sales_next_stop',
          category: IntelligenceCategory.recommendations,
          title: 'Next visit: ${nextStop.customerName}',
          message: nextStop.distanceLabel != null
              ? 'Up next on your plan — about ${nextStop.distanceLabel} away.'
              : 'This is the next customer on your planned list.',
          action: IntelligenceActionKind.openCustomer,
          priority: 22,
          customerName: nextStop.customerName,
          referenceType: 'customer',
          referenceId: nextStop.customerId,
        ),
      );
    }

    return out;
  }

  static String _money(num value, String symbol) =>
      SelloFormatters.currency(value, symbol: symbol);
}
