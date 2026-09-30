import 'package:equatable/equatable.dart';

/// Catalog id for the Hub Collections Report.
const String kCollectionsReportId = 'payments_collections_by_rep';

const String kCollectionsReportTitle = 'Collections Report';

const String kCollectionsReportQuestion =
    'See open invoices and outstanding balances by sales representative.';

/// Document type shown on the Collections Report (customer-facing).
const String kCollectionsDocumentType = 'Invoice';

const Set<String> kCollectionsEligibleOrderStatuses = {
  'placed',
  'partially_delivered',
  'completed',
};

const double kCollectionsOpenBalanceEpsilon = 0.001;

/// One completed-or-pending allocation used to compute an as-of open balance.
class CollectionsReportAllocation extends Equatable {
  const CollectionsReportAllocation({
    required this.amount,
    required this.receivedAt,
    required this.completed,
  });

  final num amount;
  final DateTime receivedAt;

  /// True only for completed payments. Pending / rejected do not count.
  final bool completed;

  @override
  List<Object?> get props => [amount, receivedAt, completed];
}

/// One open invoice row on the Collections Report.
class CollectionsReportInvoice extends Equatable {
  const CollectionsReportInvoice({
    required this.orderId,
    required this.orderNumber,
    required this.orderedAt,
    required this.customerId,
    required this.customerName,
    required this.salesRepId,
    required this.salesRepName,
    required this.openBalance,
    required this.agingDays,
    this.customerPhone,
  });

  final String orderId;
  final String orderNumber;
  final DateTime orderedAt;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String salesRepId;
  final String salesRepName;
  final num openBalance;
  final int agingDays;

  @override
  List<Object?> get props => [
        orderId,
        orderNumber,
        orderedAt,
        customerId,
        customerName,
        customerPhone,
        salesRepId,
        salesRepName,
        openBalance,
        agingDays,
      ];
}

/// Invoices belonging to one customer.
class CollectionsReportCustomerGroup extends Equatable {
  const CollectionsReportCustomerGroup({
    required this.customerId,
    required this.customerName,
    required this.invoices,
    this.customerPhone,
  });

  final String customerId;
  final String customerName;
  final String? customerPhone;
  final List<CollectionsReportInvoice> invoices;

  num get subtotal =>
      invoices.fold<num>(0, (sum, invoice) => sum + invoice.openBalance);

  /// Header sales-rep label. Mixed sellers on one customer become explicit.
  String get salesRepLabel {
    final names = <String>{
      for (final invoice in invoices)
        if (invoice.salesRepName.trim().isNotEmpty) invoice.salesRepName.trim(),
    };
    if (names.isEmpty) return '—';
    if (names.length == 1) return names.first;
    return 'Multiple sales reps';
  }

  @override
  List<Object?> get props =>
      [customerId, customerName, customerPhone, invoices];
}

/// Shared snapshot used by preview, Excel, and PDF.
class CollectionsReportSnapshot extends Equatable {
  const CollectionsReportSnapshot({
    required this.asOfDate,
    required this.salesRepsLabel,
    required this.groups,
    required this.currencySymbol,
  });

  final DateTime asOfDate;
  final String salesRepsLabel;
  final List<CollectionsReportCustomerGroup> groups;
  final String currencySymbol;

  List<CollectionsReportInvoice> get invoices => [
        for (final group in groups) ...group.invoices,
      ];

  num get grandTotal =>
      groups.fold<num>(0, (sum, group) => sum + group.subtotal);

  bool get isEmpty => invoices.isEmpty;

  @override
  List<Object?> get props => [asOfDate, salesRepsLabel, groups, currencySymbol];
}

/// As-of receivable rules for the Collections Report.
///
/// Mirrors Hub [ReceivableOrder] eligibility and completed-allocation math,
/// with an as-of cutoff on [CollectionsReportAllocation.receivedAt].
abstract final class CollectionsReportMath {
  /// Inclusive end of the selected local calendar day, in UTC.
  static DateTime asOfEndUtc(DateTime asOfLocalDate) {
    final local = DateTime(
      asOfLocalDate.year,
      asOfLocalDate.month,
      asOfLocalDate.day,
      23,
      59,
      59,
      999,
    );
    return local.toUtc();
  }

  /// Order age in whole local days from [orderedAt] to the as-of calendar date.
  static int agingDays({
    required DateTime orderedAt,
    required DateTime asOfDate,
  }) {
    final orderDay = DateTime(
      orderedAt.toLocal().year,
      orderedAt.toLocal().month,
      orderedAt.toLocal().day,
    );
    final asOfDay = DateTime(
      asOfDate.year,
      asOfDate.month,
      asOfDate.day,
    );
    final days = asOfDay.difference(orderDay).inDays;
    return days < 0 ? 0 : days;
  }

  static String salesRepsLabel({
    required List<String> selectedIds,
    required List<String> selectedNames,
  }) {
    if (selectedIds.isEmpty) return 'All Sales Reps';
    if (selectedNames.length == 1) return selectedNames.first;
    if (selectedNames.isNotEmpty) return selectedNames.join(', ');
    return '${selectedIds.length} sales reps';
  }

  static bool matchesSalesRep({
    required String employeeId,
    required List<String> selectedIds,
  }) {
    if (selectedIds.isEmpty) return true;
    return selectedIds.contains(employeeId);
  }

  static bool isEligibleOrder({
    required String status,
    required bool archived,
    required DateTime orderedAt,
    required DateTime asOfEndUtc,
  }) {
    if (archived) return false;
    if (!kCollectionsEligibleOrderStatuses.contains(status)) return false;
    if (orderedAt.isAfter(asOfEndUtc)) return false;
    return true;
  }

  static num completedAllocatedAsOf({
    required List<CollectionsReportAllocation> allocations,
    required DateTime asOfEndUtc,
  }) {
    num total = 0;
    for (final allocation in allocations) {
      if (!allocation.completed) continue;
      if (allocation.receivedAt.isAfter(asOfEndUtc)) continue;
      total += allocation.amount;
    }
    return total;
  }

  /// Remaining as-of balance, or null when the invoice should be omitted.
  static num? openBalanceAsOf({
    required num total,
    required List<CollectionsReportAllocation> allocations,
    required DateTime asOfEndUtc,
  }) {
    final remaining =
        (total - completedAllocatedAsOf(
          allocations: allocations,
          asOfEndUtc: asOfEndUtc,
        )).clamp(0, double.infinity);
    if (remaining <= kCollectionsOpenBalanceEpsilon) return null;
    return remaining;
  }

  /// Apply eligibility, sales-rep filter, as-of payments, and aging.
  static CollectionsReportInvoice? considerOrder({
    required String orderId,
    required String orderNumber,
    required DateTime orderedAt,
    required String status,
    required bool archived,
    required num total,
    required String customerId,
    required String customerName,
    String? customerPhone,
    required String salesRepId,
    required String salesRepName,
    required List<CollectionsReportAllocation> allocations,
    required DateTime asOfDate,
    List<String> selectedEmployeeIds = const [],
  }) {
    final cutoff = asOfEndUtc(asOfDate);
    if (!isEligibleOrder(
      status: status,
      archived: archived,
      orderedAt: orderedAt,
      asOfEndUtc: cutoff,
    )) {
      return null;
    }
    if (!matchesSalesRep(
      employeeId: salesRepId,
      selectedIds: selectedEmployeeIds,
    )) {
      return null;
    }
    final open = openBalanceAsOf(
      total: total,
      allocations: allocations,
      asOfEndUtc: cutoff,
    );
    if (open == null) return null;
    return CollectionsReportInvoice(
      orderId: orderId,
      orderNumber: orderNumber,
      orderedAt: orderedAt,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      salesRepId: salesRepId,
      salesRepName: salesRepName,
      openBalance: open,
      agingDays: agingDays(orderedAt: orderedAt, asOfDate: asOfDate),
    );
  }

  static CollectionsReportSnapshot assemble({
    required DateTime asOfDate,
    required String salesRepsLabel,
    required String currencySymbol,
    required List<CollectionsReportInvoice> invoices,
  }) {
    final byCustomer = <String, List<CollectionsReportInvoice>>{};
    for (final invoice in invoices) {
      byCustomer.putIfAbsent(invoice.customerId, () => []).add(invoice);
    }

    final groups = byCustomer.entries.map((entry) {
      final rows = [...entry.value]
        ..sort((a, b) {
          final byDate = a.orderedAt.compareTo(b.orderedAt);
          if (byDate != 0) return byDate;
          return a.orderNumber.compareTo(b.orderNumber);
        });
      return CollectionsReportCustomerGroup(
        customerId: entry.key,
        customerName: rows.first.customerName,
        customerPhone: rows.first.customerPhone,
        invoices: rows,
      );
    }).toList()
      ..sort(
        (a, b) => a.customerName.toLowerCase().compareTo(
              b.customerName.toLowerCase(),
            ),
      );

    return CollectionsReportSnapshot(
      asOfDate: DateTime(asOfDate.year, asOfDate.month, asOfDate.day),
      salesRepsLabel: salesRepsLabel,
      groups: groups,
      currencySymbol: currencySymbol,
    );
  }
}
