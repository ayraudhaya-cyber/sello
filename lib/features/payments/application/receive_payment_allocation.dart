import 'package:sello/shared/models/payment_summary.dart';

/// Checkbox selection for Receive payment — full remaining, partial, or none.
abstract final class ReceivePaymentAllocation {
  static num fullAmount(ReceivableOrder receivable) =>
      receivable.remaining > 0 ? receivable.remaining : 0;

  static num clampAmount({required num amount, required num remaining}) {
    if (amount <= 0) return 0;
    if (remaining <= 0) return 0;
    return amount > remaining ? remaining : amount;
  }

  static Map<String, num> selectAll(List<ReceivableOrder> receivables) {
    return {
      for (final row in receivables)
        if (row.remaining > 0) row.id: row.remaining,
    };
  }

  static Set<String> selectedIdsFor(Map<String, num> allocations) {
    return {
      for (final entry in allocations.entries)
        if (entry.value > 0) entry.key,
    };
  }

  static num totalOf(Map<String, num> allocations) {
    return allocations.values.fold<num>(0, (sum, value) => sum + value);
  }

  /// Every listed balance is fully ticked. Extra cash can then go to the wallet.
  static bool coversEveryRemaining({
    required Map<String, num> allocations,
    required List<ReceivableOrder> receivables,
  }) {
    for (final row in receivables) {
      if (row.remaining <= 0) continue;
      final allocated = allocations[row.id] ?? 0;
      if (allocated + 0.001 < row.remaining) return false;
    }
    return true;
  }

  /// `true` all, `false` none, `null` mixed — for a tristate Select all box.
  static bool? selectAllValue({
    required List<ReceivableOrder> receivables,
    required Set<String> selectedIds,
  }) {
    if (receivables.isEmpty) return false;
    final eligible = receivables.where((row) => row.remaining > 0).toList();
    if (eligible.isEmpty) return false;
    final all = eligible.every((row) => selectedIds.contains(row.id));
    if (all) return true;
    if (selectedIds.isEmpty) return false;
    return null;
  }

  static String? validate({
    required num paymentAmount,
    required Map<String, num> allocations,
    required List<ReceivableOrder> receivables,
    num discountAmount = 0,
  }) {
    if (discountAmount < -0.001) {
      return 'Discount cannot be negative.';
    }
    final settlement = paymentAmount + (discountAmount < 0 ? 0 : discountAmount);
    final byId = {for (final row in receivables) row.id: row};
    num total = 0;
    for (final entry in allocations.entries) {
      if (entry.value <= 0) continue;
      final row = byId[entry.key];
      if (row == null) continue;
      if (entry.value > row.remaining + 0.001) {
        return 'This is more than what is still unpaid on ${row.pickerTitle}.';
      }
      total += entry.value;
    }
    if (total > settlement + 0.001) {
      return discountAmount > 0.001
          ? lessThanTickedWithDiscount
          : lessThanTicked;
    }
    final available = receivables.fold<num>(
      0,
      (sum, row) => sum + (row.remaining > 0 ? row.remaining : 0),
    );
    final required = settlement < available ? settlement : available;
    if (required > 0 && total + 0.001 < required) {
      return extraBeforeEveryOrder;
    }
    return null;
  }

  static const lessThanTicked =
      'This is less than the ticked orders. Change the amount on the order.';

  static const lessThanTickedWithDiscount =
      'The ticked orders are more than the money plus the discount. Lower an order amount.';

  static const extraBeforeEveryOrder =
      'Tick every unpaid order first. Extra money goes to the wallet only after that.';

  static const chequeExtraWithDiscount =
      'On a cheque, use a discount or extra money, not both. Clear the discount, or make the cheque amount match the ticked total.';

  /// How the typed cash compares with the ticked total.
  static ReceivePaymentGiving compareGiving({
    required num giving,
    required num covered,
    required Map<String, num> allocations,
    required List<ReceivableOrder> receivables,
  }) {
    if (receivables.isNotEmpty &&
        covered > 0.001 &&
        giving + 0.001 < covered) {
      return ReceivePaymentGiving.short;
    }
    final extra = giving - covered;
    if (extra <= 0.001 || receivables.isEmpty) {
      return ReceivePaymentGiving.same;
    }
    if (!coversEveryRemaining(
      allocations: allocations,
      receivables: receivables,
    )) {
      return ReceivePaymentGiving.extraBeforeAll;
    }
    return ReceivePaymentGiving.extraToWallet;
  }

  static String extraToWalletMessage(
    String formattedAmount, {
    bool whenChequeArrives = false,
  }) {
    if (whenChequeArrives) {
      return '$formattedAmount extra will be saved in their wallet when you have the cheque.';
    }
    return '$formattedAmount extra will be saved in their wallet.';
  }
}

enum ReceivePaymentGiving { same, short, extraBeforeAll, extraToWallet }
