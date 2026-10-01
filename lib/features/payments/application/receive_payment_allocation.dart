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
  }) {
    final byId = {for (final row in receivables) row.id: row};
    num total = 0;
    for (final entry in allocations.entries) {
      if (entry.value <= 0) continue;
      final row = byId[entry.key];
      if (row == null) continue;
      if (entry.value > row.remaining + 0.001) {
        return 'Amount is more than the remaining balance on ${row.pickerTitle}.';
      }
      total += entry.value;
    }
    if (total > paymentAmount + 0.001) {
      return 'Selected outstanding is more than the payment amount.';
    }
    return null;
  }
}
