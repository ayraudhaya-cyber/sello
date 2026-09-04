import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/dashboard/needs_attention.dart';
import 'package:sello/shared/models/order_status.dart';

/// Guards the V1 delivery terminology pass — status badges stay unchanged;
/// user-facing attention copy uses delivery language.
void main() {
  group('order delivery terminology (V1)', () {
    test('status badges keep Draft / Placed / Completed labels', () {
      expect(OrderStatus.draft.label, 'Draft');
      expect(OrderStatus.placed.label, 'Placed');
      expect(OrderStatus.partiallyDelivered.label, 'Partially delivered');
      expect(OrderStatus.completed.label, 'Completed');
      expect(OrderStatus.cancelled.label, 'Cancelled');
    });

    test('needs attention uses waiting to deliver (not fulfillment)', () {
      final items = NeedsAttentionLogic.build(
        const NeedsAttentionCounts(placed: 1),
      );
      expect(items.single.title, '1 order waiting to deliver');
      expect(items.single.title.toLowerCase(), isNot(contains('fulfill')));
    });
  });
}
