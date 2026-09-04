import 'package:equatable/equatable.dart';
import 'package:sello/core/router/route_paths.dart';

/// Operational urgency for Hub Needs Attention rows.
enum NeedsAttentionPriority { high, medium }

/// Distinct alert kinds — order categories are mutually exclusive where noted.
enum NeedsAttentionKind {
  negativeStock,
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
    required this.route,
  });

  final NeedsAttentionKind kind;
  final NeedsAttentionPriority priority;
  final int count;
  final String title;

  /// Hub route to open (filters applied by the dashboard before navigate).
  final String route;

  @override
  List<Object?> get props => [kind, priority, count, title, route];
}

/// Raw counts before presentation rules.
class NeedsAttentionCounts extends Equatable {
  const NeedsAttentionCounts({
    this.placed = 0,
    this.partiallyDelivered = 0,
    this.waitingPlaced = 0,
    this.waitingPartial = 0,
    this.negativeStock = 0,
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
      negativeStock <= 0 &&
      waitingForStock <= 0 &&
      placedAwaitingFulfillment <= 0 &&
      partialNeedingAttention <= 0;

  int get totalAlerts {
    var n = 0;
    if (negativeStock > 0) n++;
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
      ];
}

/// Pure builder — keeps dashboard presentation free of counting rules.
abstract final class NeedsAttentionLogic {
  static List<NeedsAttentionItem> build(NeedsAttentionCounts counts) {
    final items = <NeedsAttentionItem>[];

    if (counts.negativeStock > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.negativeStock,
          priority: NeedsAttentionPriority.high,
          count: counts.negativeStock,
          title: counts.negativeStock == 1
              ? '1 product has negative stock'
              : '${counts.negativeStock} products have negative stock',
          route: RoutePaths.hubInventory,
        ),
      );
    }

    if (counts.waitingForStock > 0) {
      items.add(
        NeedsAttentionItem(
          kind: NeedsAttentionKind.waitingForStock,
          priority: NeedsAttentionPriority.high,
          count: counts.waitingForStock,
          title: counts.waitingForStock == 1
              ? '1 order is waiting for stock'
              : '${counts.waitingForStock} orders are waiting for stock',
          route: RoutePaths.hubOrders,
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
          route: RoutePaths.hubOrders,
        ),
      );
    }

    return items;
  }
}
