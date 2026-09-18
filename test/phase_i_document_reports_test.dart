import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/documents/presentation/order_document_print_html.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/utils/formatters.dart';

void main() {
  group('OrderDocumentLine snapshot identity', () {
    test('multi-option shows name, label, and sellable sku', () {
      final line = OrderDocumentLine.fromJson(const {
        'name': 'Door Lock',
        'variant_label': '20"',
        'sku': 'DL-20',
        'quantity': 3,
        'unit_price': 6000,
        'line_total': 18000,
      });

      expect(line.name, 'Door Lock');
      expect(line.variantLabel, '20"');
      expect(line.sku, 'DL-20');
      expect(line.displayTitle, 'Door Lock · 20"');
      expect(
        line.displayMeta('Rs 6,000.00', SelloFormatters.quantity),
        '3 × Rs 6,000.00 · DL-20',
      );
    });

    test('simple product omits Default and keeps clean title', () {
      final line = OrderDocumentLine.fromJson(const {
        'name': 'Widget',
        'variant_label': 'Default',
        'sku': 'W-1',
        'quantity': 2,
        'unit_price': 100,
        'line_total': 200,
      });

      expect(line.variantLabel, isNull);
      expect(line.displayTitle, 'Widget');
      expect(line.displayTitle.toLowerCase(), isNot(contains('default')));
      expect(
        line.displayMeta('\$100.00', SelloFormatters.quantity),
        '2 × \$100.00 · W-1',
      );
    });

    test('blank variant label is treated as absent', () {
      final line = OrderDocumentLine.fromJson(const {
        'name': 'Widget',
        'variant_label': '  ',
        'quantity': 1,
        'unit_price': 10,
        'line_total': 10,
      });
      expect(line.variantLabel, isNull);
      expect(line.displayTitle, 'Widget');
    });

    test('historical rename: payload name is the snapshot, not live catalog', () {
      // RPC prefers oi.product_name; Flutter renders whatever the token returns.
      final line = OrderDocumentLine.fromJson(const {
        'name': 'Door Lock (sold as)',
        'variant_label': '12"',
        'sku': 'DL-12-OLD',
        'quantity': 1,
        'unit_price': 1500,
        'line_total': 1500,
      });
      expect(line.name, 'Door Lock (sold as)');
      expect(line.sku, 'DL-12-OLD');
      expect(line.displayTitle, 'Door Lock (sold as) · 12"');
    });

    test('historical sku wins when provided on the line payload', () {
      final line = OrderDocumentLine.fromJson(const {
        'name': 'Door Lock',
        'sku': 'HISTORIC-SKU',
        'quantity': 1,
        'unit_price': 10,
        'line_total': 10,
      });
      expect(line.sku, 'HISTORIC-SKU');
      expect(
        line.displayMeta('\$10.00', SelloFormatters.quantity),
        contains('HISTORIC-SKU'),
      );
    });
  });

  group('OrderDocument fromJson lines', () {
    test('parses variant_label onto document lines', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-09-18T10:00:00Z',
        'total': 18000,
        'currency': 'LKR',
        'company_name': 'Acme',
        'customer_name': 'City Mart',
        'lines': [
          {
            'name': 'Door Lock',
            'variant_label': '20"',
            'sku': 'DL-20',
            'quantity': 3,
            'unit_price': 6000,
            'line_total': 18000,
          },
        ],
      });

      expect(doc.lines, hasLength(1));
      expect(doc.lines.single.displayTitle, 'Door Lock · 20"');
      expect(doc.lines.single.sku, 'DL-20');
    });

    test('payment/receipt documents without lines remain valid', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'receipt',
        'payment_number': 'PAY-1',
        'amount': 500,
        'received_at': '2026-09-18T10:00:00Z',
        'currency': 'LKR',
        'company_name': 'Acme',
        'customer_name': 'City Mart',
        'lines': const [],
      });

      expect(doc.purpose, PublicDocumentPurpose.receipt);
      expect(doc.lines, isEmpty);
      expect(doc.total, 500);
    });

    test('print html includes option identity and sku', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'order_confirmation',
        'order_number': 'SO-9',
        'ordered_at': '2026-09-18T10:00:00Z',
        'subtotal': 18000,
        'total': 18000,
        'currency': 'LKR',
        'company_name': 'Acme',
        'customer_name': 'City Mart',
        'lines': [
          {
            'name': 'Door Lock',
            'variant_label': '20"',
            'sku': 'DL-20',
            'quantity': 3,
            'unit_price': 6000,
            'line_total': 18000,
          },
        ],
      });

      final html = buildOrderDocumentPrintHtml(doc);
      expect(html, contains('Door Lock · 20&quot;'));
      expect(html, contains('DL-20'));
      expect(html.toLowerCase(), isNot(contains('>default<')));
    });
  });

  group('OrderLineItem internal display', () {
    test('details/fulfillment displayTitle includes variant label', () {
      final line = OrderLineItem.fromJson({
        'id': 'oi1',
        'product_id': 'p1',
        'variant_id': 'v20',
        'product_name': 'Door Lock',
        'variant_label': '20"',
        'sku': 'DL-20',
        'quantity': 3,
        'unit_price': 6000,
        'line_total': 18000,
      });

      expect(line.displayTitle, 'Door Lock · 20"');
      expect(line.productSku, 'DL-20');
    });

    test('simple product displayTitle has no Default', () {
      final line = OrderLineItem.fromJson({
        'id': 'oi1',
        'product_id': 'p1',
        'product_name': 'Widget',
        'variant_label': 'Default',
        'sku': 'W-1',
        'quantity': 1,
        'unit_price': 10,
        'line_total': 10,
      });

      expect(line.displayTitle, 'Widget');
      expect(line.displayTitle.toLowerCase(), isNot(contains('default')));
    });

    test('snapshot product_name beats live products join', () {
      final line = OrderLineItem.fromJson({
        'id': 'oi1',
        'product_id': 'p1',
        'product_name': 'Sold As Name',
        'sku': 'SOLD-SKU',
        'quantity': 1,
        'unit_price': 10,
        'line_total': 10,
        'products': const {
          'name': 'Renamed Later',
          'sku': 'NEW-SKU',
        },
      });

      expect(line.productName, 'Sold As Name');
      expect(line.productSku, 'SOLD-SKU');
      expect(line.displayTitle, 'Sold As Name');
    });
  });

  group('Top products ranking grain', () {
    test('parent product_id remains the aggregation key shape', () {
      // Mirrors report_repository._fetchTopProducts: map keyed by product_id.
      final rows = [
        {
          'product_id': 'p-lock',
          'product_name': 'Door Lock',
          'sku': 'LOCK-12',
          'line_total': 7500,
          'quantity': 5,
        },
        {
          'product_id': 'p-lock',
          'product_name': 'Door Lock',
          'sku': 'LOCK-20',
          'line_total': 5400,
          'quantity': 3,
        },
      ];

      final totals = <String, ({String name, String? sku, num value, int count})>{};
      for (final row in rows) {
        final productId = row['product_id']! as String;
        final snapshotName = row['product_name'] as String?;
        final snapshotSku = row['sku'] as String?;
        final existing = totals[productId];
        if (existing == null) {
          totals[productId] = (
            name: snapshotName ?? 'Product',
            sku: snapshotSku,
            value: row['line_total'] as num,
            count: (row['quantity'] as num).round(),
          );
        } else {
          totals[productId] = (
            name: existing.name,
            sku: existing.sku,
            value: existing.value + (row['line_total'] as num),
            count: existing.count + (row['quantity'] as num).round(),
          );
        }
      }

      expect(totals.keys, ['p-lock']);
      expect(totals['p-lock']!.name, 'Door Lock');
      expect(totals['p-lock']!.value, 12900);
      expect(totals['p-lock']!.count, 8);
      // First snapshot sku kept as subtitle — not variant-expanded.
      expect(totals['p-lock']!.sku, 'LOCK-12');
    });
  });
}
