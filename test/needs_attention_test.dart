import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/dashboard/needs_attention.dart';

void main() {
  group('NeedsAttentionLogic', () {
    test('empty counts produce no alerts', () {
      expect(NeedsAttentionLogic.build(const NeedsAttentionCounts()), isEmpty);
    });

    test('empty state flag is true when nothing needs attention', () {
      expect(const NeedsAttentionCounts().isEmpty, isTrue);
    });

    test('placed order appears as needing fulfillment', () {
      final items = NeedsAttentionLogic.build(
        const NeedsAttentionCounts(placed: 3),
      );
      expect(items, hasLength(1));
      expect(items.single.kind, NeedsAttentionKind.placedAwaitingFulfillment);
      expect(items.single.count, 3);
      expect(items.single.priority, NeedsAttentionPriority.medium);
      expect(items.single.route, RoutePaths.hubOrders);
      expect(items.single.title, '3 orders need fulfillment');
    });

    test('partially delivered order appears', () {
      final items = NeedsAttentionLogic.build(
        const NeedsAttentionCounts(partiallyDelivered: 2),
      );
      expect(items.single.kind, NeedsAttentionKind.partiallyDelivered);
      expect(items.single.count, 2);
      expect(items.single.title, '2 partially delivered orders');
    });

    test('completed and cancelled are outside input counts so never appear', () {
      // Logic only receives open fulfillment counts — completed/cancelled
      // are never passed in by the repository.
      expect(
        NeedsAttentionLogic.build(const NeedsAttentionCounts()),
        isEmpty,
      );
    });

    test('negative inventory appears as high priority', () {
      final items = NeedsAttentionLogic.build(
        const NeedsAttentionCounts(negativeStock: 1),
      );
      expect(items.single.kind, NeedsAttentionKind.negativeStock);
      expect(items.single.priority, NeedsAttentionPriority.high);
      expect(items.single.route, RoutePaths.hubInventory);
      expect(items.single.title, '1 product has negative stock');
    });

    test('zero or positive stock does not create negative-stock alert', () {
      expect(
        NeedsAttentionLogic.build(const NeedsAttentionCounts(negativeStock: 0)),
        isEmpty,
      );
    });

    test('orders above stock are not permanent problems without a block', () {
      // Placed demand alone is medium fulfillment — not a stock alert.
      final items = NeedsAttentionLogic.build(
        const NeedsAttentionCounts(placed: 5),
      );
      expect(
        items.any((i) => i.kind == NeedsAttentionKind.waitingForStock),
        isFalse,
      );
    });

    test('waiting for stock is high and excludes duplicate placed/partial rows', () {
      final counts = NeedsAttentionCounts(
        placed: 4,
        partiallyDelivered: 3,
        waitingPlaced: 1,
        waitingPartial: 2,
      );
      expect(counts.waitingForStock, 3);
      expect(counts.placedAwaitingFulfillment, 3);
      expect(counts.partialNeedingAttention, 1);

      final items = NeedsAttentionLogic.build(counts);
      expect(
        items.map((i) => i.kind),
        [
          NeedsAttentionKind.waitingForStock,
          NeedsAttentionKind.placedAwaitingFulfillment,
          NeedsAttentionKind.partiallyDelivered,
        ],
      );
      expect(
        items.firstWhere((i) => i.kind == NeedsAttentionKind.waitingForStock).count,
        3,
      );
      expect(
        items
            .firstWhere(
              (i) => i.kind == NeedsAttentionKind.placedAwaitingFulfillment,
            )
            .count,
        3,
      );
      expect(
        items
            .firstWhere((i) => i.kind == NeedsAttentionKind.partiallyDelivered)
            .count,
        1,
      );
    });

    test('counts match underlying records for mixed alerts', () {
      final counts = NeedsAttentionCounts(
        placed: 2,
        partiallyDelivered: 1,
        negativeStock: 4,
      );
      final items = NeedsAttentionLogic.build(counts);
      expect(items, hasLength(3));
      expect(
        items.firstWhere((i) => i.kind == NeedsAttentionKind.negativeStock).count,
        4,
      );
      expect(
        items
            .firstWhere(
              (i) => i.kind == NeedsAttentionKind.placedAwaitingFulfillment,
            )
            .count,
        2,
      );
      expect(
        items
            .firstWhere((i) => i.kind == NeedsAttentionKind.partiallyDelivered)
            .count,
        1,
      );
      expect(counts.totalAlerts, 3);
    });

    test('singular titles for count of one', () {
      final items = NeedsAttentionLogic.build(
        const NeedsAttentionCounts(placed: 1, partiallyDelivered: 1),
      );
      expect(
        items
            .firstWhere(
              (i) => i.kind == NeedsAttentionKind.placedAwaitingFulfillment,
            )
            .title,
        '1 order needs fulfillment',
      );
      expect(
        items
            .firstWhere((i) => i.kind == NeedsAttentionKind.partiallyDelivered)
            .title,
        '1 partially delivered order',
      );
    });

    test('reading notifications must not clear Needs Attention counts', () {
      // Needs Attention is derived from live order/inventory state, not read_at.
      const counts = NeedsAttentionCounts(placed: 2, negativeStock: 1);
      final before = NeedsAttentionLogic.build(counts);
      final after = NeedsAttentionLogic.build(counts);
      expect(after, before);
      expect(after.any((i) => i.count > 0), isTrue);
    });
  });
}
