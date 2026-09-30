import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/documents/presentation/order_document_print_html.dart';
import 'package:sello/shared/models/order_document.dart';

void main() {
  group('InvoiceCollectionReview', () {
    test('pending collection shows Processing payment without payment details', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-10-01T10:00:00Z',
        'total': 50000,
        'currency': 'LKR',
        'company_name': 'Acme',
        'customer_name': 'City Mart',
        'collection_review': 'processing',
        'collection_payment_number': 'PAY-12',
        'collection_payment_method': 'cash',
        'collection_payment_amount': 50000,
        'lines': const [],
      });

      expect(doc.collectionReview, InvoiceCollectionReview.processing);
      expect(doc.collectionStatusTag, 'Processing payment');
      expect(doc.collectionReview.showsPaymentDetails, isFalse);
      expect(doc.collectionMethodLabel, 'Cash');

      final html = buildOrderDocumentPrintHtml(doc);
      expect(html, contains('Processing payment'));
      expect(html, isNot(contains('Payment approved')));
      expect(html, isNot(contains('PAY-12')));
      expect(html, isNot(contains('Amount received')));
    });

    test('approved collection shows Payment approved with payment details', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-10-01T10:00:00Z',
        'total': 50000,
        'currency': 'LKR',
        'company_name': 'Acme',
        'customer_name': 'City Mart',
        'collection_review': 'approved',
        'collection_payment_number': 'PAY-12',
        'collection_payment_method': 'bank_transfer',
        'collection_payment_amount': 50000,
        'collection_received_at': '2026-10-01T12:00:00Z',
        'lines': const [],
      });

      expect(doc.collectionReview, InvoiceCollectionReview.approved);
      expect(doc.collectionStatusTag, 'Payment approved');
      expect(doc.collectionReview.showsPaymentDetails, isTrue);
      expect(doc.collectionMethodLabel, 'Bank transfer');
      expect(doc.collectionPaymentNumber, 'PAY-12');
      expect(doc.collectionPaymentAmount, 50000);

      final html = buildOrderDocumentPrintHtml(doc);
      expect(html, contains('Payment approved'));
      expect(html, contains('PAY-12'));
      expect(html, contains('Bank transfer'));
      expect(html, contains('Recorded on'));
      expect(html, isNot(contains('Paid on')));
      expect(html, contains('Amount received'));
      expect(html, isNot(contains('Processing payment')));
    });

    test('invoice without a review collection has no status tag', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-2',
        'ordered_at': '2026-10-01T10:00:00Z',
        'total': 100,
        'currency': 'LKR',
        'company_name': 'Acme',
        'customer_name': 'Buyer',
        'lines': const [],
      });

      expect(doc.collectionReview, InvoiceCollectionReview.none);
      expect(doc.collectionStatusTag, isNull);
      expect(buildOrderDocumentPrintHtml(doc), isNot(contains('Processing payment')));
      expect(buildOrderDocumentPrintHtml(doc), isNot(contains('Payment approved')));
    });
  });

  test('public document RPC looks up pending then approved collections', () {
    final sql = File(
      'supabase/migrations/20261001000084_084_invoice_collection_review.sql',
    ).readAsStringSync();

    expect(sql, contains('collection_review'));
    expect(sql, contains("'processing'"));
    expect(sql, contains("'approved'"));
    expect(sql, contains('p.status = \'pending\''));
    expect(sql, contains('p.reviewed_at is not null'));
    expect(sql, contains('payment_allocations'));
    expect(sql, isNot(contains('status = \'rejected\'')));
  });

  test('invoice date is when the collection was recorded, not approved', () {
    final sql = File(
      'supabase/migrations/20261001000086_086_invoice_collection_recorded_at.sql',
    ).readAsStringSync();
    expect(sql, contains("'received_at', p.created_at"));
    expect(sql, contains("v_collection ->> 'received_at'"));
    expect(sql, isNot(contains("'received_at', p.reviewed_at")));

    final recorded = DateTime.utc(2026, 9, 28, 8, 30);
    final approvedLater = DateTime.utc(2026, 10, 1, 12);
    final doc = OrderDocument.fromJson({
      'purpose': 'invoice',
      'order_number': 'SO-1',
      'ordered_at': '2026-09-28T08:00:00Z',
      'total': 50000,
      'currency': 'LKR',
      'company_name': 'Acme',
      'customer_name': 'City Mart',
      'collection_review': 'approved',
      'collection_received_at': recorded.toIso8601String(),
      'lines': const [],
    });
    expect(doc.collectionReceivedAt!.toUtc(), recorded);
    expect(doc.collectionReceivedAt!.toUtc(), isNot(approvedLater));
    expect(
      buildOrderDocumentPrintHtml(doc),
      contains('28 Sep 2026'),
    );
  });
}
