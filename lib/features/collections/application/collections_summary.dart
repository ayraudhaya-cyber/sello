import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

/// Date presets shared by the Sales Rep "My collections" list and the Hub
/// Payments export. Ranges are local calendar days: [from, before).
enum CollectionsPeriod {
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  lastMonth('Last month');

  const CollectionsPeriod(this.label);

  final String label;

  ({DateTime from, DateTime before}) range([DateTime? now]) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    switch (this) {
      case CollectionsPeriod.today:
        return (from: today, before: today.add(const Duration(days: 1)));
      case CollectionsPeriod.thisWeek:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (from: monday, before: monday.add(const Duration(days: 7)));
      case CollectionsPeriod.thisMonth:
        return (
          from: DateTime(today.year, today.month),
          before: DateTime(today.year, today.month + 1),
        );
      case CollectionsPeriod.lastMonth:
        return (
          from: DateTime(today.year, today.month - 1),
          before: DateTime(today.year, today.month),
        );
    }
  }
}

/// One sales rep's slice of a collections list.
class RepCollectionTotals {
  const RepCollectionTotals({
    required this.employeeId,
    required this.name,
    required this.collectedCount,
    required this.collected,
    required this.pendingCount,
    required this.pending,
    required this.orderCollected,
    required this.openingCollected,
  });

  final String employeeId;
  final String name;
  final int collectedCount;
  final num collected;
  final int pendingCount;
  final num pending;

  /// Collected amount that paid orders (a split payment counts per allocation).
  final num orderCollected;

  /// Collected amount that paid opening-balance (pre-Sello) invoices.
  final num openingCollected;
}

/// Totals for a list of collections. Only completed rows count as collected;
/// pending-review rows are shown separately and never mixed into "collected".
class CollectionsSummary {
  const CollectionsSummary({
    required this.collected,
    required this.collectedCount,
    required this.pending,
    required this.pendingCount,
    required this.orderCollected,
    required this.openingCollected,
    required this.byRep,
  });

  final num collected;
  final int collectedCount;
  final num pending;
  final int pendingCount;
  final num orderCollected;
  final num openingCollected;
  final List<RepCollectionTotals> byRep;

  factory CollectionsSummary.of(List<PaymentSummary> rows) {
    num collected = 0;
    num pending = 0;
    var collectedCount = 0;
    var pendingCount = 0;
    num orderTotal = 0;
    num openingTotal = 0;

    final reps = <String, _RepAccumulator>{};

    for (final row in rows) {
      final isCompleted = row.status == PaymentRecordStatus.completed;
      final isPending = row.status == PaymentRecordStatus.pending;
      if (!isCompleted && !isPending) continue;

      final rep = reps.putIfAbsent(
        row.employeeId,
        () => _RepAccumulator(row.employeeId, row.employeeName ?? 'Unknown'),
      );

      if (isCompleted) {
        collected += row.amount;
        collectedCount += 1;
        rep.collected += row.amount;
        rep.collectedCount += 1;

        final split = _split(row);
        orderTotal += split.order;
        openingTotal += split.opening;
        rep.order += split.order;
        rep.opening += split.opening;
      } else {
        pending += row.amount;
        pendingCount += 1;
        rep.pending += row.amount;
        rep.pendingCount += 1;
      }
    }

    final byRep = [
      for (final r in reps.values)
        RepCollectionTotals(
          employeeId: r.id,
          name: r.name,
          collectedCount: r.collectedCount,
          collected: r.collected,
          pendingCount: r.pendingCount,
          pending: r.pending,
          orderCollected: r.order,
          openingCollected: r.opening,
        ),
    ]..sort((a, b) => b.collected.compareTo(a.collected));

    return CollectionsSummary(
      collected: collected,
      collectedCount: collectedCount,
      pending: pending,
      pendingCount: pendingCount,
      orderCollected: orderTotal,
      openingCollected: openingTotal,
      byRep: byRep,
    );
  }

  /// Splits a payment between order and opening-balance allocations. A payment
  /// with no allocations counts as order money so totals still add up.
  static ({num order, num opening}) _split(PaymentSummary row) {
    if (row.allocations.isEmpty) return (order: row.amount, opening: 0);
    num order = 0;
    num opening = 0;
    for (final a in row.allocations) {
      if (a.isOpeningBalance) {
        opening += a.amount;
      } else {
        order += a.amount;
      }
    }
    final leftover = row.amount - order - opening;
    if (leftover > 0.0001) order += leftover;
    return (order: order, opening: opening);
  }
}

class _RepAccumulator {
  _RepAccumulator(this.id, this.name);

  final String id;
  final String name;
  num collected = 0;
  num pending = 0;
  int collectedCount = 0;
  int pendingCount = 0;
  num order = 0;
  num opening = 0;
}
