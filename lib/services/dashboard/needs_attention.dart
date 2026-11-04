import 'package:equatable/equatable.dart';
import 'package:sello/core/router/route_paths.dart';

/// Operational urgency for Hub Needs Attention rows.
enum NeedsAttentionPriority { high, medium }

/// Distinct alert kinds — order categories are mutually exclusive where noted.
enum NeedsAttentionKind {
  pendingCollections,
  negativeStock,
  stockShortage,
  waitingForStock,
  placedAwaitingFulfillment,
  partiallyDelivered,
}

/// One compact alert row derived from live Hub data.
class NeedsAttentionItem extends Equatable {
  const NeedsAttentionItem({
    required this.kind,
    required this.priority,
    required this.count,
    required this.title,
    required this.action,
    required this.route,
    this.detail,
  });

  final NeedsAttentionKind kind;
  final NeedsAttentionPriority priority;
  final int count;
  final String title;

  /// What the row is asking the owner to do.
  final String action;

  /// Age or other context under the title. Empty when we have no date.
  final String? detail;

  /// Hub route to open (filters applied by the dashboard before navigate).
  final String route;

  @override
  List<Object?> get props => [kind, priority, count, title, action, detail, route];
}

/// Raw counts before presentation rules.
class NeedsAttentionCounts extends Equatable {
  const NeedsAttentionCounts({
    this.placed = 0,
    this.partiallyDelivered = 0,
    this.waitingPlaced = 0,
    this.waitingPartial = 0,
    this.negativeStock = 0,
    this.stockShortage = 0,
    this.pendingCollections = 0,
    this.oldestWaiting,
    this.oldestReadyPlaced,
    this.oldestReadyPartial,
  });

  /// Orders with status `placed`.
  final int placed;

  /// Orders with status `partially_delivered`.
  final int partiallyDelivered;

  /// Placed orders blocked because remaining qty exceeds available stock.
  final int waitingPlaced;

  /// Partially delivered orders blocked the same way.
  final int waitingPartial;

  /// Active products with physical `inventory.quantity < 0` (branch-scoped).
  final int negativeStock;

  /// Active products whose reserved quantity exceeds on-hand (branch-scoped).
  final int stockShortage;

  /// Sales Rep collections waiting for Owner / Manager approval.
  final int pendingCollections;

  final DateTime? oldestWaiting;
  final DateTime? oldestReadyPlaced;
  final DateTime? oldestReadyPartial;

  int get waitingForStock => waitingPlaced + waitingPartial;

  /// Placed orders that still need fulfillment and are not stock-blocked.
  int get placedAwaitingFulfillment {
    final value = placed - waitingPlaced;
    return value < 0 ? 0 : value;
  }

  /// Partially delivered orders not already counted as waiting for stock.
  int get partialNeedingAttention {
    final value = partiallyDelivered - waitingPartial;
    return value < 0 ? 0 : value;
  }

  bool get isEmpty =>
      pendingCollections <= 0 &&
      negativeStock <= 0 &&
      stockShortage <= 0 &&
      waitingForStock <= 0 &&
      placedAwaitingFulfillment <= 0 &&
      partialNeedingAttention <= 0;

  int get totalAlerts {
    var n = 0;
    if (pendingCollections > 0) n++;
    if (negativeStock > 0) n++;
    if (stockShortage > 0) n++;
    if (waitingForStock > 0) n++;
    if (placedAwaitingFulfillment > 0) n++;
    if (partialNeedingAttention > 0) n++;
    return n;
  }

  @override
  List<Object?> get props => [
        placed,
        partiallyDelivered,
        waitingPlaced,
        waitingPartial,
        negativeStock,
        stockShortage,
        pendingCollections,
        oldestWaiting,
        oldestReadyPlaced,
        oldestReadyPartial,
      ];
}

/// How long ago an open order was placed, for a Needs attention row.
String? attentionPlacedLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final localNow = (now ?? DateTime.now()).toLocal();
  final localAt = at.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final day = DateTime(localAt.year, localAt.month, localAt.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Placed today';
  if (days == 1) return 'Placed yesterday';
  return 'Placed $days days ago';
}

/// Pure builder — keeps dashboard presentation free of counting rules.
abstract final class NeedsAttentionLogic {
  static List<NeedsAttentionItem> build(NeedsAttentionCounts counts) {
    final items = <NeedsAttentionItem>[];

    if (counts.waitingForStock > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.waitingForStock,
          priority: NeedsAttentionPriority.high,
          count: counts.waitingForStock,
          title: counts.waitingForStock == 1
              ? '1 order is waiting for stock'
              : '${counts.waitingForStock} orders are waiting for stock',
          action: 'Restock',
          detail: attentionPlacedLabel(counts.oldestWaiting),
          route: RoutePaths.hubOrders,
        ),
      );
    }

    if (counts.negativeStock > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.negativeStock,
          priority: NeedsAttentionPriority.high,
          count: counts.negativeStock,
          title: counts.negativeStock == 1
              ? '1 product has negative stock'
              : '${counts.negativeStock} products have negative stock',
          action: 'Restock',
          route: RoutePaths.hubInventory,
        ),
      );
    }

    if (counts.stockShortage > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.stockShortage,
          priority: NeedsAttentionPriority.high,
          count: counts.stockShortage,
          title: counts.stockShortage == 1
              ? '1 product is short of reserved stock'
              : '${counts.stockShortage} products are short of reserved stock',
          action: 'Restock',
          route: RoutePaths.hubInventory,
        ),
      );
    }

    if (counts.pendingCollections > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.pendingCollections,
          priority: NeedsAttentionPriority.high,
          count: counts.pendingCollections,
          title: counts.pendingCollections == 1
              ? '1 collection waiting for your approval'
              : '${counts.pendingCollections} collections waiting for your approval',
          action: 'Review',
          route: RoutePaths.hubPayments,
        ),
      );
    }

    if (counts.placedAwaitingFulfillment > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.placedAwaitingFulfillment,
          priority: NeedsAttentionPriority.medium,
          count: counts.placedAwaitingFulfillment,
          title: counts.placedAwaitingFulfillment == 1
              ? '1 order waiting to deliver'
              : '${counts.placedAwaitingFulfillment} orders waiting to deliver',
          action: 'Deliver',
          detail: attentionPlacedLabel(counts.oldestReadyPlaced),
          route: RoutePaths.hubOrders,
        ),
      );
    }

    if (counts.partialNeedingAttention > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.partiallyDelivered,
          priority: NeedsAttentionPriority.medium,
          count: counts.partialNeedingAttention,
          title: counts.partialNeedingAttention == 1
              ? '1 partially delivered order'
              : '${counts.partialNeedingAttention} partially delivered orders',
          action: 'Deliver',
          detail: attentionPlacedLabel(counts.oldestReadyPartial),
          route: RoutePaths.hubOrders,
        ),
      );
    }

    return items;
  }
}
