/// Which open orders cannot be fully packed from physical stock.
///
/// Older orders claim on-hand quantity first. A short order still takes what
/// is left, so later orders only see the remainder. Reserved quantity is not
/// used here: it already includes these same orders.
abstract final class OrderStockAllocation {
  static Set<String> ordersShortOfStock({
    required List<OpenOrderStockDemand> orders,
    required Map<String, num> onHandByKey,
  }) {
    final sorted = [...orders]..sort((a, b) {
      final byTime = a.orderedAt.compareTo(b.orderedAt);
      if (byTime != 0) return byTime;
      return a.orderId.compareTo(b.orderId);
    });

    final pool = <String, num>{
      for (final entry in onHandByKey.entries)
        entry.key: entry.value < 0 ? 0 : entry.value,
    };
    final short = <String>{};

    for (final order in sorted) {
      final need = <String, num>{};
      for (final line in order.lines) {
        if (line.remaining <= 0) continue;
        need[line.stockKey] = (need[line.stockKey] ?? 0) + line.remaining;
      }
      if (need.isEmpty) continue;

      var blocked = false;
      for (final entry in need.entries) {
        final have = pool[entry.key] ?? 0;
        if (entry.value > have) blocked = true;
        final take = entry.value < have ? entry.value : have;
        pool[entry.key] = have - take;
      }
      if (blocked) short.add(order.orderId);
    }

    return short;
  }

  /// Physical units this order may deliver without taking stock older open
  /// orders still need. [onHand] and [olderOpenDemand] are for one branch and
  /// one sellable unit.
  static num deliverableQuantity({
    required num onHand,
    required num olderOpenDemand,
  }) {
    final older = olderOpenDemand < 0 ? 0 : olderOpenDemand;
    final free = onHand - older;
    return free < 0 ? 0 : free;
  }

  /// Shared hold after a delivery. [openUndelivered] still includes the units
  /// being delivered, because the line is updated after the stock change.
  static num reservedAfterDelivery({
    required num openUndelivered,
    required num delivering,
  }) {
    final left = openUndelivered - (delivering < 0 ? 0 : delivering);
    return left < 0 ? 0 : left;
  }

  /// Shared hold after a cancellation. Physical on-hand is unchanged.
  static num reservedAfterRelease({
    required num reserved,
    required num releasing,
  }) {
    final left = reserved - (releasing < 0 ? 0 : releasing);
    return left < 0 ? 0 : left;
  }
}

class OpenOrderStockDemand {
  const OpenOrderStockDemand({
    required this.orderId,
    required this.orderedAt,
    required this.lines,
  });

  final String orderId;
  final DateTime orderedAt;
  final List<OpenOrderStockLine> lines;
}

class OpenOrderStockLine {
  const OpenOrderStockLine({required this.stockKey, required this.remaining});

  /// Branch and sellable unit, already combined by the caller.
  final String stockKey;
  final num remaining;
}
