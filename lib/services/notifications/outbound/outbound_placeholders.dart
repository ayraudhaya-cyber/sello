import 'package:sello/shared/models/outbound_notification_policies.dart';

/// A personalization field the owner can insert into a message template.
class OutboundPlaceholder {
  const OutboundPlaceholder({required this.token, required this.label});

  /// Token written into the template, without braces (e.g. `customer_name`).
  final String token;

  /// Human-friendly chip label (e.g. `Customer name`).
  final String label;

  String get insertion => '{{$token}}';
}

/// Placeholders that Sello can actually fill from order / collection snapshots.
abstract final class OutboundPlaceholders {
  static const customerName = OutboundPlaceholder(
    token: 'customer_name',
    label: 'Customer name',
  );
  static const orderNumber = OutboundPlaceholder(
    token: 'order_number',
    label: 'Order number',
  );
  static const orderTotal = OutboundPlaceholder(
    token: 'order_total',
    label: 'Order total',
  );
  static const businessName = OutboundPlaceholder(
    token: 'business_name',
    label: 'Business name',
  );
  static const salesRep = OutboundPlaceholder(
    token: 'sales_rep_name',
    label: 'Sales Rep',
  );
  static const invoiceNumber = OutboundPlaceholder(
    token: 'invoice_number',
    label: 'Invoice number',
  );
  static const invoiceLink = OutboundPlaceholder(
    token: 'invoice_link',
    label: 'Invoice link',
  );
  static const collectionAmount = OutboundPlaceholder(
    token: 'collection_amount',
    label: 'Collection amount',
  );
  static const collectionNumber = OutboundPlaceholder(
    token: 'collection_number',
    label: 'Collection number',
  );
  static const receiptLink = OutboundPlaceholder(
    token: 'receipt_link',
    label: 'Receipt link',
  );

  static const orderFields = <OutboundPlaceholder>[
    customerName,
    orderNumber,
    orderTotal,
    businessName,
    salesRep,
    invoiceNumber,
    invoiceLink,
  ];

  static const collectionFields = <OutboundPlaceholder>[
    customerName,
    collectionAmount,
    collectionNumber,
    businessName,
    salesRep,
    receiptLink,
  ];

  static List<OutboundPlaceholder> forType(OutboundNotificationType type) {
    return switch (type) {
      OutboundNotificationType.orderConfirmation ||
      OutboundNotificationType.orderNotification ||
      OutboundNotificationType.invoice =>
        orderFields,
      OutboundNotificationType.collectionAcknowledgement ||
      OutboundNotificationType.collectionSubmitted ||
      OutboundNotificationType.receipt =>
        collectionFields,
    };
  }

  /// Sample values for the Settings preview (never real tenant data).
  static Map<String, String?> previewValues(OutboundNotificationType type) {
    final link = 'https://app.sello.example/d/preview';
    final shared = <String, String?>{
      'customer_name': 'City Mart',
      'business_name': 'Your business',
      'company_name': 'Your business',
      'sales_rep_name': 'Amina Perera',
    };
    if (type.isOrderFamily) {
      return {
        ...shared,
        'order_number': 'SO-0001',
        'invoice_number': 'SO-0001',
        'order_total': 'Rs 12,500.00',
        'amount': 'Rs 12,500.00',
        'invoice_link': link,
        'document_link': link,
      };
    }
    return {
      ...shared,
      'collection_number': 'PAY-0001',
      'collection_amount': 'Rs 5,000.00',
      'amount': 'Rs 5,000.00',
      'receipt_link': link,
      'document_link': link,
    };
  }
}
