import 'package:sello/shared/models/cheque_source.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

/// How Record collection should treat an existing cheque that is clearly
/// tied to this order — never a guess against an unrelated customer cheque.
enum AssociatedChequeAction {
  /// No usable existing instrument. New collection is allowed.
  none,

  /// Awaiting-collection cheque from this visit/order. Collect it.
  collectExisting,

  /// Collected (or pending) cheque payment has unallocated remainder.
  /// Attach that remainder to this order; do not create another cheque.
  applyExisting,
}

class AssociatedChequeMatch {
  const AssociatedChequeMatch({
    required this.cheque,
    required this.action,
    required this.applicableAmount,
    this.allocatedToThisOrder = false,
  });

  final ChequeSummary cheque;
  final AssociatedChequeAction action;
  final num applicableAmount;
  final bool allocatedToThisOrder;

  bool get usesExisting => action != AssociatedChequeAction.none;
}

/// Snapshot of money already on this order. Used to explain a NEW collection.
class OrderCollectionSnapshot {
  const OrderCollectionSnapshot({
    required this.orderTotal,
    required this.amountPaid,
    this.amountPending = 0,
    this.entries = const [],
  });

  factory OrderCollectionSnapshot.fromBalance({
    required num orderTotal,
    required OrderCollectionBalance balance,
  }) {
    return OrderCollectionSnapshot(
      orderTotal: orderTotal,
      amountPaid: balance.amountPaid,
      amountPending: balance.amountPending,
      entries: balance.entries,
    );
  }

  final num orderTotal;
  final num amountPaid;
  final num amountPending;
  final List<OrderCollectionEntry> entries;

  num get remaining =>
      (orderTotal - amountPaid - amountPending).clamp(0, double.infinity);

  bool get isFullyCovered => remaining <= 0.001;

  bool get hasPriorCollections =>
      amountPaid > 0.001 || amountPending > 0.001 || entries.isNotEmpty;

  /// Latest completed (else pending) collection, for the compact summary.
  OrderCollectionEntry? get latestEntry {
    if (entries.isEmpty) return null;
    for (final entry in entries) {
      if (entry.countsTowardPaid) return entry;
    }
    return entries.first;
  }
}

/// Record collection against an existing order — not a replay of checkout.
abstract final class OrderCollectionAssociation {
  /// Checkout chips / `orders.payment_method` are intent, not money.
  /// Never pre-select a method from them.
  static PaymentMethod get defaultNewCollectionMethod => PaymentMethod.cash;

  static bool canOfferRecordCollection({
    required OrderStatus status,
    required PaymentStatus paymentStatus,
    required num total,
    required num outstanding,
  }) {
    if (outstanding <= 0.001) return false;
    if (total <= 0) return false;
    if (status == OrderStatus.draft || status == OrderStatus.cancelled) {
      return false;
    }
    return paymentStatus == PaymentStatus.unpaid ||
        paymentStatus == PaymentStatus.partial;
  }

  /// Mixed methods on the same order are valid (cheque then cash, etc.).
  static bool allowsDifferentMethodFromPrior(PaymentMethod next) {
    return OrderCollectionAssociation.supportedMethods.contains(next);
  }

  static const supportedMethods = <PaymentMethod>[
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.bankTransfer,
    PaymentMethod.cheque,
  ];

  /// Strict link: same visit, notes naming this order, or already allocated
  /// here. A random customer cheque is never assumed to belong to this order.
  static bool isClearlyAssociated({
    required ChequeSummary cheque,
    required String orderId,
    required String orderNumber,
    String? orderVisitId,
    Set<String> allocatedOrderIds = const {},
  }) {
    if (!_isUsableInstrument(cheque)) return false;
    if (allocatedOrderIds.contains(orderId)) return true;
    if (sharesVisit(cheque.visitId, orderVisitId)) return true;
    if (notesMentionOrder(cheque.notes, orderNumber)) return true;
    return false;
  }

  static bool sharesVisit(String? chequeVisitId, String? orderVisitId) {
    final chequeVisit = chequeVisitId?.trim() ?? '';
    final orderVisit = orderVisitId?.trim() ?? '';
    if (chequeVisit.isEmpty || orderVisit.isEmpty) return false;
    return chequeVisit == orderVisit;
  }

  static bool notesMentionOrder(String? notes, String orderNumber) {
    final text = notes?.trim() ?? '';
    final number = orderNumber.trim();
    if (text.isEmpty || number.isEmpty) return false;
    return text.toLowerCase().contains(number.toLowerCase());
  }

  static AssociatedChequeAction resolveAction({
    required ChequeSummary cheque,
    required bool allocatedToThisOrder,
    required num unallocatedOnPayment,
    required num orderRemaining,
  }) {
    if (!_isUsableInstrument(cheque)) return AssociatedChequeAction.none;
    if (orderRemaining <= 0.001) return AssociatedChequeAction.none;
    if (allocatedToThisOrder) return AssociatedChequeAction.none;
    if (cheque.status == ChequeStatus.awaitingCollection) {
      return AssociatedChequeAction.collectExisting;
    }
    if (cheque.paymentId != null && unallocatedOnPayment > 0.001) {
      return AssociatedChequeAction.applyExisting;
    }
    return AssociatedChequeAction.none;
  }

  /// Prefer collecting an awaiting visit cheque over applying leftover money.
  static AssociatedChequeMatch? pickMatch({
    required List<AssociatedChequeMatch> matches,
  }) {
    AssociatedChequeMatch? collect;
    AssociatedChequeMatch? apply;
    for (final match in matches) {
      if (match.action == AssociatedChequeAction.collectExisting) {
        collect ??= match;
      } else if (match.action == AssociatedChequeAction.applyExisting) {
        apply ??= match;
      }
    }
    return collect ?? apply;
  }

  /// Only cheques with a visit, note, or allocation link to this order.
  static List<AssociatedChequeMatch> buildMatches({
    required List<ChequeSummary> cheques,
    required String orderId,
    required String orderNumber,
    String? orderVisitId,
    required num orderRemaining,
    Map<String, List<PaymentAllocation>> allocationsByPaymentId = const {},
  }) {
    final matches = <AssociatedChequeMatch>[];
    for (final cheque in cheques) {
      final allocs = cheque.paymentId == null
          ? const <PaymentAllocation>[]
          : (allocationsByPaymentId[cheque.paymentId] ??
                const <PaymentAllocation>[]);
      final allocatedOrderIds = {
        for (final row in allocs)
          if (row.orderId != null && row.orderId!.trim().isNotEmpty)
            row.orderId!,
      };
      if (!isClearlyAssociated(
        cheque: cheque,
        orderId: orderId,
        orderNumber: orderNumber,
        orderVisitId: orderVisitId,
        allocatedOrderIds: allocatedOrderIds,
      )) {
        continue;
      }
      final allocatedHere = allocatedOrderIds.contains(orderId);
      final unallocated = cheque.paymentId == null
          ? (cheque.status == ChequeStatus.awaitingCollection
                ? cheque.amount
                : 0)
          : unallocatedOnPayment(
              paymentAmount: cheque.amount,
              allocations: allocs,
            );
      final action = resolveAction(
        cheque: cheque,
        allocatedToThisOrder: allocatedHere,
        unallocatedOnPayment: unallocated,
        orderRemaining: orderRemaining,
      );
      if (action == AssociatedChequeAction.none) continue;
      final applicable = action == AssociatedChequeAction.collectExisting
          ? _min(cheque.amount, orderRemaining)
          : _min(unallocated, orderRemaining);
      if (applicable <= 0.001) continue;
      matches.add(
        AssociatedChequeMatch(
          cheque: cheque,
          action: action,
          applicableAmount: applicable,
          allocatedToThisOrder: allocatedHere,
        ),
      );
    }
    return matches;
  }

  static AssociatedChequeMatch? findAssociatedCheque({
    required List<ChequeSummary> cheques,
    required String orderId,
    required String orderNumber,
    String? orderVisitId,
    required num orderRemaining,
    Map<String, List<PaymentAllocation>> allocationsByPaymentId = const {},
  }) {
    return pickMatch(
      matches: buildMatches(
        cheques: cheques,
        orderId: orderId,
        orderNumber: orderNumber,
        orderVisitId: orderVisitId,
        orderRemaining: orderRemaining,
        allocationsByPaymentId: allocationsByPaymentId,
      ),
    );
  }

  /// Checkout / order chips are never treated as money.
  static PaymentMethod methodForNewCollection({
    PaymentMethod? orderPaymentMethod,
    PaymentMethod? priorCollectionMethod,
  }) {
    switch ((orderPaymentMethod, priorCollectionMethod)) {
      case (_, _):
        return defaultNewCollectionMethod;
    }
  }

  static bool shouldUseExistingCheque({
    required PaymentMethod method,
    AssociatedChequeMatch? match,
  }) {
    return method == PaymentMethod.cheque &&
        match != null &&
        match.usesExisting;
  }

  /// New cheque row only when Cheque is chosen and nothing associated exists.
  static bool shouldCreateNewCheque({
    required PaymentMethod method,
    AssociatedChequeMatch? match,
  }) {
    if (method != PaymentMethod.cheque) return false;
    return match == null || !match.usesExisting;
  }

  /// Amount a *new* collection may take. Associated leftover is reserved so
  /// Record collection cannot duplicate money already sitting on a cheque.
  static num newCollectionCeiling({
    required num remaining,
    required PaymentMethod method,
    AssociatedChequeMatch? match,
  }) {
    if (shouldUseExistingCheque(method: method, match: match)) {
      return match!.applicableAmount;
    }
    final reserved = match != null && match.usesExisting
        ? match.applicableAmount
        : 0;
    final left = remaining - reserved;
    return left > 0 ? left : 0;
  }

  static String existingChequeActionLabel(AssociatedChequeAction action) {
    return switch (action) {
      AssociatedChequeAction.collectExisting => 'Mark cheque as received',
      AssociatedChequeAction.applyExisting => 'Apply existing cheque',
      AssociatedChequeAction.none => 'Record collection',
    };
  }

  static String methodChipLabel(PaymentMethod method) {
    if (method == PaymentMethod.bankTransfer) return 'Bank';
    return method.label;
  }

  static num unallocatedOnPayment({
    required num paymentAmount,
    required List<PaymentAllocation> allocations,
  }) {
    final used = allocations.fold<num>(0, (sum, row) => sum + row.amount);
    final left = paymentAmount - used;
    return left > 0 ? left : 0;
  }

  static num _min(num a, num b) => a < b ? a : b;

  static bool _isUsableInstrument(ChequeSummary cheque) {
    if (cheque.status == ChequeStatus.bounced ||
        cheque.status == ChequeStatus.cancelled) {
      return false;
    }
    if (cheque.source == ChequeSource.existing && cheque.paymentId == null) {
      return false;
    }
    return true;
  }
}
