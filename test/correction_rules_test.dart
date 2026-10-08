import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/corrections/application/correction_rules.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/utils/hub_table_paging.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/models/sms_quota.dart';

void main() {
  group('Hub table paging', () {
    test('page size is at least 50', () {
      expect(kHubTablePageSize, greaterThanOrEqualTo(50));
    });

    test('grouped inventory pages by parent product, not variant rows', () {
      InventoryItem item(String productId, String id) {
        return InventoryItem(
          inventoryId: id,
          companyId: 'c',
          branchId: 'b',
          productId: productId,
          sku: id,
          name: productId,
          quantity: 1,
          reservedQuantity: 0,
          isActive: true,
        );
      }

      final items = [
        item('p1', 'v1'),
        item('p1', 'v2'),
        item('p1', 'v3'),
        item('p2', 'v4'),
        item('p3', 'v5'),
        item('p3', 'v6'),
      ];

      final page0 = paginateGroupedInventory(items: items, page: 0, pageSize: 2);
      expect(page0.items.map((row) => row.productId).toSet(), {'p1', 'p2'});
      expect(page0.hasMore, isTrue);

      final page1 = paginateGroupedInventory(items: items, page: 1, pageSize: 2);
      expect(page1.items.map((row) => row.productId).toSet(), {'p3'});
      expect(page1.hasMore, isFalse);
    });
  });

  group('OrderCorrectionRules', () {
    test('Owner can change Sales Rep except cancelled', () {
      expect(OrderCorrectionRules.canChangeSalesRep(OrderStatus.draft), isTrue);
      expect(OrderCorrectionRules.canChangeSalesRep(OrderStatus.placed), isTrue);
      expect(
        OrderCorrectionRules.canChangeSalesRep(OrderStatus.completed),
        isTrue,
      );
      expect(
        OrderCorrectionRules.canChangeSalesRep(OrderStatus.cancelled),
        isFalse,
      );
    });

    test('customer change is draft-only and blocked after collections', () {
      expect(
        OrderCorrectionRules.canChangeCustomer(
          status: OrderStatus.draft,
          hasCollections: false,
        ),
        isTrue,
      );
      expect(
        OrderCorrectionRules.canChangeCustomer(
          status: OrderStatus.draft,
          hasCollections: true,
        ),
        isFalse,
      );
      expect(
        OrderCorrectionRules.canChangeCustomer(
          status: OrderStatus.placed,
          hasCollections: false,
        ),
        isFalse,
      );
      expect(
        OrderCorrectionRules.canChangeCustomer(
          status: OrderStatus.completed,
          hasCollections: false,
        ),
        isFalse,
      );
    });

    test('line edits stay on drafts', () {
      expect(OrderCorrectionRules.canEditLines(OrderStatus.draft), isTrue);
      expect(OrderCorrectionRules.canEditLines(OrderStatus.placed), isFalse);
      expect(OrderCorrectionRules.canEditLines(OrderStatus.completed), isFalse);
    });
  });

  group('PaymentCorrectionRules', () {
    test('completed and pending can be corrected', () {
      expect(
        PaymentCorrectionRules.canCorrect(PaymentRecordStatus.completed),
        isTrue,
      );
      expect(
        PaymentCorrectionRules.canCorrect(PaymentRecordStatus.pending),
        isTrue,
      );
      expect(
        PaymentCorrectionRules.canCorrect(PaymentRecordStatus.cancelled),
        isFalse,
      );
      expect(
        PaymentCorrectionRules.canCorrect(PaymentRecordStatus.rejected),
        isFalse,
      );
    });

    test('explanation uses reverse-and-replace language', () {
      expect(
        PaymentCorrectionRules.explanation(PaymentRecordStatus.completed),
        contains('reverse the original payment'),
      );
    });
  });

  group('ChequeCorrectionRules', () {
    test('Sales Rep may edit details only while waiting to receive', () {
      expect(
        ChequeCorrectionRules.canEditDetails(
          status: ChequeStatus.awaitingCollection,
          isHubFinancialRole: false,
          isOwnCheque: true,
        ),
        isTrue,
      );
      expect(
        ChequeCorrectionRules.canEditDetails(
          status: ChequeStatus.cleared,
          isHubFinancialRole: false,
          isOwnCheque: true,
        ),
        isFalse,
      );
    });

    test('Owner can edit descriptive details until cancelled or bounced', () {
      expect(
        ChequeCorrectionRules.canEditDetails(
          status: ChequeStatus.cleared,
          isHubFinancialRole: true,
          isOwnCheque: false,
        ),
        isTrue,
      );
      expect(
        ChequeCorrectionRules.canEditDetails(
          status: ChequeStatus.cancelled,
          isHubFinancialRole: true,
          isOwnCheque: false,
        ),
        isFalse,
      );
    });
  });

  group('SMS quota visibility', () {
    test('unconfigured stays hidden', () {
      expect(
        SmsQuotaView.fromEdgeJson({'status': 'unconfigured'}).isHidden,
        isTrue,
      );
      expect(SmsQuotaView.fromEdgeJson({'status': 'hidden'}).isHidden, isTrue);
    });

    test('edge or Text.lk failure is unavailable, not hidden', () {
      expect(
        SmsQuotaView.fromEdgeJson({'status': 'unavailable'}).isUnavailable,
        isTrue,
      );
      expect(SmsQuotaView.fromEdgeJson(null).isUnavailable, isTrue);
    });

    test('ok payload is ready', () {
      final view = SmsQuotaView.fromEdgeJson({
        'status': 'ok',
        'remaining': 80,
        'baseline': 100,
      });
      expect(view.isReady, isTrue);
      expect(view.quota!.caption, '20 used / 100');
    });
  });
}
