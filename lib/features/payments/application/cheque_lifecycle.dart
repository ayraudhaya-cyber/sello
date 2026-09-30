import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/payment_summary.dart';

export 'package:sello/shared/utils/customer_search.dart';

/// Safe forward step for the current cheque. Bounce / Cancel are not included.
enum ChequeForwardAction { collect, approve, deposit, clear }

String chequeForwardActionLabel(ChequeForwardAction action) {
  return switch (action) {
    ChequeForwardAction.collect => 'Mark received',
    ChequeForwardAction.approve => 'Approve',
    ChequeForwardAction.deposit => 'Take to bank',
    ChequeForwardAction.clear => 'Bank paid it',
  };
}

/// Collect / Deposit / Clear are reversible under current rules and skip a
/// confirm dialog. Approve applies balances and still requires confirmation.
bool chequeForwardActionNeedsConfirmation(ChequeForwardAction action) {
  return action == ChequeForwardAction.approve;
}

const chequeConfirmedDestructiveActions = {'bounce', 'cancel'};

bool chequeDestructiveActionRequiresConfirmation(String action) {
  return chequeConfirmedDestructiveActions.contains(action);
}

/// Next valid forward action the signed-in role is allowed to run.
ChequeForwardAction? chequeNextForwardAction({
  required ChequeSummary cheque,
  required bool canCollect,
  required bool canManageClearance,
}) {
  if (canCollect && cheque.canCollect) {
    return ChequeForwardAction.collect;
  }
  if (canManageClearance && cheque.canApproveCollection) {
    return ChequeForwardAction.approve;
  }
  if (canManageClearance && cheque.canDeposit) {
    return ChequeForwardAction.deposit;
  }
  if (canManageClearance && cheque.status.canClear) {
    return ChequeForwardAction.clear;
  }
  return null;
}

bool chequeShowsBounce({
  required ChequeSummary cheque,
  required bool canManageClearance,
}) {
  return canManageClearance && cheque.canBounce;
}

bool chequeShowsCancel({
  required ChequeSummary cheque,
  required bool canCollect,
  required bool canManageClearance,
}) {
  if (!cheque.status.canCancel) return false;
  if (canManageClearance) return true;
  return canCollect && cheque.status == ChequeStatus.awaitingCollection;
}

/// Collect must not reopen allocation when a payment / apply already exists.
bool chequeCollectPreservesExistingAllocation(ChequeSummary cheque) {
  return cheque.paymentId != null || cheque.balanceAppliedAt != null;
}

/// Allocation UI is only needed when collect would create a payment and the
/// caller cannot apply the existing FIFO / empty-allocation rule automatically.
/// Today that UI is never required: collect always auto-FIFOs (or sends `[]`
/// when there are no receivables), matching the previous collect sheet.
bool chequeCollectShouldPromptAllocation(ChequeSummary cheque) {
  return false;
}

/// User-facing labels only — never show a raw UUID.
String? chequeUserFacingLabel(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (_looksLikeRawUuid(trimmed)) return null;
  return trimmed;
}

bool _looksLikeRawUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

class ChequeRelatedDocuments {
  const ChequeRelatedDocuments({
    this.paymentNumber,
    this.orderNumbers = const [],
  });

  final String? paymentNumber;
  final List<String> orderNumbers;

  bool get isEmpty => paymentNumber == null && orderNumbers.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Related payment / order labels for cheque details. Pending payments still
/// surface when a payment row and allocations exist.
ChequeRelatedDocuments chequeRelatedDocuments({
  required String? paymentNumber,
  required List<PaymentAllocation> allocations,
}) {
  final numbers = <String>[];
  final seen = <String>{};
  for (final alloc in allocations) {
    final label = chequeUserFacingLabel(alloc.orderNumber);
    if (label == null) continue;
    if (seen.add(label)) numbers.add(label);
  }
  return ChequeRelatedDocuments(
    paymentNumber: chequeUserFacingLabel(paymentNumber),
    orderNumbers: numbers,
  );
}

/// Puts [preferredOrderId] first; remaining orders keep their original order.
List<ReceivableOrder> orderReceivablesForCheque({
  required List<ReceivableOrder> orders,
  String? preferredOrderId,
}) {
  final preferredId = preferredOrderId?.trim();
  if (preferredId == null || preferredId.isEmpty) return orders;
  ReceivableOrder? preferred;
  final rest = <ReceivableOrder>[];
  for (final order in orders) {
    if (order.id == preferredId) {
      preferred = order;
    } else {
      rest.add(order);
    }
  }
  if (preferred == null) return orders;
  return [preferred, ...rest];
}

num? preferredChequeDefaultAmount({
  required List<ReceivableOrder> orders,
  String? preferredOrderId,
}) {
  final preferredId = preferredOrderId?.trim();
  if (preferredId == null || preferredId.isEmpty) return null;
  for (final order in orders) {
    if (order.id == preferredId && order.remaining > 0) {
      return order.remaining;
    }
  }
  return null;
}

/// Checking an outstanding order covers its remaining balance.
num chequeOrderSelectionAmount(ReceivableOrder order) =>
    order.remaining > 0 ? order.remaining : 0;

num clampChequeOrderAllocation({
  required num amount,
  required num remaining,
}) {
  if (amount <= 0) return 0;
  if (remaining <= 0) return 0;
  return amount > remaining ? remaining : amount;
}

/// Client-side allocation checks. Server still enforces remaining / amount.
String? chequeManualAllocationError({
  required num chequeAmount,
  required Map<String, num> allocations,
  required List<ReceivableOrder> orders,
}) {
  final byId = {for (final order in orders) order.id: order};
  num total = 0;
  for (final entry in allocations.entries) {
    if (entry.value <= 0) continue;
    final order = byId[entry.key];
    if (order == null) continue;
    if (entry.value > order.remaining + 0.001) {
      return 'Allocation exceeds remaining on ${order.orderNumber}.';
    }
    total += entry.value;
  }
  if (total > chequeAmount + 0.001) {
    return 'Allocated orders exceed the cheque amount.';
  }
  return null;
}

/// FIFO against outstanding orders. When [preferredOrderId] is set, that
/// order is allocated first; any remainder follows existing FIFO order.
List<PaymentAllocationInput> fifoChequeAllocations({
  required num amount,
  required List<ReceivableOrder> orders,
  String? preferredOrderId,
}) {
  if (amount <= 0) return const [];
  final sequenced = orderReceivablesForCheque(
    orders: orders,
    preferredOrderId: preferredOrderId,
  );
  final allocations = <PaymentAllocationInput>[];
  var remaining = amount;
  for (final order in sequenced) {
    if (remaining <= 0) break;
    final take = order.remaining.clamp(0, remaining);
    if (take > 0) {
      allocations.add(
        PaymentAllocationInput(orderId: order.id, amount: take),
      );
      remaining -= take;
    }
  }
  return allocations;
}

/// Allocations to send with [collect_cheque]. Empty when the cheque already
/// has a payment (RPC is idempotent) or when there is nothing to allocate.
List<PaymentAllocationInput> allocationsForCollect({
  required ChequeSummary cheque,
  required List<ReceivableOrder> receivables,
}) {
  if (chequeCollectPreservesExistingAllocation(cheque)) {
    return const [];
  }
  return fifoChequeAllocations(amount: cheque.amount, orders: receivables);
}

/// Holder defaults to the customer name until the user types a different value.
String defaultChequeHolderName({
  required String currentHolder,
  required String selectedCustomerName,
  String? previousCustomerName,
}) {
  final trimmed = currentHolder.trim();
  if (trimmed.isEmpty) return selectedCustomerName;
  final previous = previousCustomerName?.trim();
  if (previous != null && previous.isNotEmpty && trimmed == previous) {
    return selectedCustomerName;
  }
  return currentHolder;
}

bool chequeEligibleForBatchDeposit(ChequeSummary cheque) => cheque.canDeposit;
