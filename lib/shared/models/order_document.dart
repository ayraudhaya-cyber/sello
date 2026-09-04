import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/utils/formatters.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _stringValue(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Public document purpose resolved from a secure token.
enum PublicDocumentPurpose {
  orderConfirmation,
  invoice,
  collectionAcknowledgement,
  receipt;

  static PublicDocumentPurpose fromDb(String? value) {
    return switch (value) {
      'invoice' => PublicDocumentPurpose.invoice,
      'collection_acknowledgement' =>
        PublicDocumentPurpose.collectionAcknowledgement,
      'receipt' => PublicDocumentPurpose.receipt,
      _ => PublicDocumentPurpose.orderConfirmation,
    };
  }

  bool get isPaymentDocument =>
      this == PublicDocumentPurpose.collectionAcknowledgement ||
      this == PublicDocumentPurpose.receipt;

  bool get isPendingCollection =>
      this == PublicDocumentPurpose.collectionAcknowledgement;
}

/// Customer-facing order/invoice/payment snapshot. No internal UUIDs.
class OrderDocument extends Equatable {
  const OrderDocument({
    required this.orderNumber,
    required this.orderedAt,
    required this.total,
    required this.currencyCode,
    required this.companyName,
    required this.customerName,
    required this.lines,
    this.purpose = PublicDocumentPurpose.orderConfirmation,
    this.completedAt,
    this.subtotal = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.paymentStatus,
    this.paymentMethod,
    this.notes,
    this.companyLegalName,
    this.currencyPosition = CurrencyPosition.before,
    this.logoUrl,
    this.logoLightUrl,
    this.documentLogoUrl,
    this.documentAddress,
    this.documentPhone,
    this.documentEmail,
    this.documentTerms,
    this.primaryColor,
    this.customBrandingEnabled = false,
    this.showBusinessNameWithLogo = false,
    this.customerPhone,
    this.customerAddress,
    this.salesRepName,
    this.outstandingBalance,
    this.paymentNumber,
    this.pendingReview = false,
    this.reference,
  });

  final PublicDocumentPurpose purpose;
  final String orderNumber;
  final DateTime orderedAt;
  final DateTime? completedAt;
  final num subtotal;
  final num discountAmount;
  final num taxAmount;
  final num total;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? notes;
  final String companyName;
  final String? companyLegalName;
  final String currencyCode;
  final CurrencyPosition currencyPosition;
  final String? logoUrl;
  final String? logoLightUrl;

  /// Customer-facing issuer logo (independent of Custom Branding assets).
  final String? documentLogoUrl;
  final String? documentAddress;
  final String? documentPhone;
  final String? documentEmail;
  final String? documentTerms;
  final String? primaryColor;
  final bool customBrandingEnabled;

  /// When a logo exists, also show [companyName]. Ignored when no logo.
  final bool showBusinessNameWithLogo;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String? salesRepName;
  final num? outstandingBalance;
  final String? paymentNumber;
  final bool pendingReview;
  final String? reference;
  final List<OrderDocumentLine> lines;

  bool get isCollectionAcknowledgement =>
      purpose == PublicDocumentPurpose.collectionAcknowledgement;

  String get documentTitle {
    if (isCollectionAcknowledgement) {
      final number = paymentNumber ?? orderNumber;
      return number.isEmpty
          ? 'Collection acknowledgement'
          : 'Collection $number';
    }
    if (purpose == PublicDocumentPurpose.receipt) {
      final number = paymentNumber ?? orderNumber;
      return number.isEmpty ? 'Payment receipt' : 'Receipt $number';
    }
    if (purpose == PublicDocumentPurpose.invoice) {
      return orderNumber.isEmpty ? 'Invoice' : 'Invoice $orderNumber';
    }
    return orderNumber.isEmpty ? 'Order' : 'Order $orderNumber';
  }

  /// Theme accents only — issuer logo is [issuerIdentity], never the Sello mark.
  ClientBranding get branding => customBrandingEnabled
      ? ClientBranding.resolve(
          logoUrl: logoUrl,
          logoLightUrl: logoLightUrl,
          primaryColor: primaryColor,
        )
      : ClientBranding.sello;

  DocumentIssuerIdentity get issuerIdentity => DocumentIssuerIdentity.resolve(
        companyName: companyName,
        documentLogoUrl: documentLogoUrl,
        showBusinessNameWithLogo: showBusinessNameWithLogo,
        address: documentAddress,
        phone: documentPhone,
        email: documentEmail,
        terms: documentTerms,
      );

  String get currencySymbol => SelloFormatters.currencySymbol(currencyCode);

  String money(num value) =>
      SelloFormatters.currency(value, symbol: currencySymbol);

  factory OrderDocument.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lines = <OrderDocumentLine>[];
    if (rawLines is List) {
      for (final row in rawLines) {
        if (row is Map<String, dynamic>) {
          lines.add(OrderDocumentLine.fromJson(row));
        } else if (row is Map) {
          lines.add(OrderDocumentLine.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    final purpose = PublicDocumentPurpose.fromDb(_stringValue(json['purpose']));
    final paymentNumber = _stringValue(json['payment_number']);
    final amount = json.containsKey('amount') ? _numValue(json['amount']) : null;
    final receivedAt = _dateValue(json['received_at']);
    final pendingReview = json['pending_review'] == true ||
        _stringValue(json['status']) == 'pending';

    return OrderDocument(
      purpose: purpose,
      orderNumber: _stringValue(json['order_number']) ?? paymentNumber ?? '',
      orderedAt: receivedAt ??
          _dateValue(json['ordered_at']) ??
          DateTime.now().toUtc(),
      completedAt: _dateValue(json['completed_at']),
      subtotal: _numValue(json['subtotal']),
      discountAmount: _numValue(json['discount_amount']),
      taxAmount: _numValue(json['tax_amount']),
      total: amount ?? _numValue(json['total']),
      paymentStatus: _stringValue(json['payment_status']) ??
          _stringValue(json['status']),
      paymentMethod: _stringValue(json['payment_method']) ??
          _stringValue(json['method']),
      notes: _stringValue(json['notes']),
      companyName: _stringValue(json['company_name']) ?? 'Business',
      companyLegalName: _stringValue(json['company_legal_name']),
      currencyCode: _stringValue(json['currency']) ?? 'USD',
      currencyPosition: CurrencyPosition.fromDb(
        _stringValue(json['currency_position']),
      ),
      logoUrl: _stringValue(json['logo_url']),
      logoLightUrl: _stringValue(json['logo_light_url']),
      documentLogoUrl: _stringValue(json['document_logo_url']),
      documentAddress: _stringValue(json['document_address']),
      documentPhone: _stringValue(json['document_phone']),
      documentEmail: _stringValue(json['document_email']),
      documentTerms: _stringValue(json['document_terms']),
      primaryColor: _stringValue(json['primary_color']),
      customBrandingEnabled: json['custom_branding_enabled'] == true,
      showBusinessNameWithLogo:
          json['document_show_business_name_with_logo'] == true,
      customerName: _stringValue(json['customer_name']) ?? 'Customer',
      customerPhone: _stringValue(json['customer_phone']),
      customerAddress: _stringValue(json['customer_address']),
      salesRepName: _stringValue(json['sales_rep_name']),
      outstandingBalance: json['outstanding_balance'] == null
          ? null
          : _numValue(json['outstanding_balance']),
      paymentNumber: paymentNumber,
      pendingReview: pendingReview,
      reference: _stringValue(json['reference']),
      lines: lines,
    );
  }

  @override
  List<Object?> get props => [
        purpose,
        orderNumber,
        paymentNumber,
        total,
        customerName,
        pendingReview,
        lines,
      ];
}

class OrderDocumentLine extends Equatable {
  const OrderDocumentLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.sku,
  });

  final String name;
  final String? sku;
  final num quantity;
  final num unitPrice;
  final num lineTotal;

  factory OrderDocumentLine.fromJson(Map<String, dynamic> json) {
    return OrderDocumentLine(
      name: _stringValue(json['name']) ?? 'Item',
      sku: _stringValue(json['sku']),
      quantity: _numValue(json['quantity']),
      unitPrice: _numValue(json['unit_price']),
      lineTotal: _numValue(json['line_total']),
    );
  }

  @override
  List<Object?> get props => [name, quantity, lineTotal];
}

class OrderConfirmationPrepareResult {
  const OrderConfirmationPrepareResult({
    required this.alreadyPrepared,
    required this.token,
    required this.order,
    this.eventId,
    this.customer,
    this.hubRecipients = const [],
    this.salesRep,
  });

  final bool alreadyPrepared;
  final String? eventId;
  final String token;
  final OrderConfirmationOrderSnapshot order;
  final OrderConfirmationContact? customer;
  final List<OrderConfirmationHubRecipient> hubRecipients;
  final OrderConfirmationContact? salesRep;

  factory OrderConfirmationPrepareResult.fromJson(Map<String, dynamic> json) {
    final orderJson = json['order'];
    final customerJson = json['customer'];
    final hubJson = json['hub_recipients'];
    final salesRepJson = json['sales_rep'];

    OrderConfirmationContact? parseContact(dynamic raw) {
      if (raw is Map<String, dynamic>) {
        return OrderConfirmationContact.fromJson(raw);
      }
      if (raw is Map) {
        return OrderConfirmationContact.fromJson(
          Map<String, dynamic>.from(raw),
        );
      }
      return null;
    }

    return OrderConfirmationPrepareResult(
      alreadyPrepared: json['already_prepared'] == true,
      eventId: _stringValue(json['event_id']?.toString()),
      token: _stringValue(json['token']) ?? '',
      order: OrderConfirmationOrderSnapshot.fromJson(
        orderJson is Map<String, dynamic>
            ? orderJson
            : orderJson is Map
                ? Map<String, dynamic>.from(orderJson)
                : const {},
      ),
      customer: parseContact(customerJson),
      hubRecipients: [
        if (hubJson is List)
          for (final row in hubJson)
            if (row is Map<String, dynamic>)
              OrderConfirmationHubRecipient.fromJson(row)
            else if (row is Map)
              OrderConfirmationHubRecipient.fromJson(
                Map<String, dynamic>.from(row),
              ),
      ],
      salesRep: parseContact(salesRepJson),
    );
  }
}

class OrderConfirmationOrderSnapshot {
  const OrderConfirmationOrderSnapshot({
    required this.number,
    required this.total,
    required this.currency,
    required this.companyName,
    required this.customerName,
    this.orderedAt,
    this.completedAt,
    this.salesRepName,
  });

  final String number;
  final num total;
  final String currency;
  final String companyName;
  final String customerName;
  final DateTime? orderedAt;
  final DateTime? completedAt;
  final String? salesRepName;

  factory OrderConfirmationOrderSnapshot.fromJson(Map<String, dynamic> json) {
    return OrderConfirmationOrderSnapshot(
      number: _stringValue(json['number']) ?? '',
      total: _numValue(json['total']),
      currency: _stringValue(json['currency']) ?? 'USD',
      companyName: _stringValue(json['company_name']) ?? 'Sello',
      customerName: _stringValue(json['customer_name']) ?? 'Customer',
      orderedAt: _dateValue(json['ordered_at']),
      completedAt: _dateValue(json['completed_at']),
      salesRepName: _stringValue(json['sales_rep_name']),
    );
  }
}

class OrderConfirmationContact {
  const OrderConfirmationContact({
    required this.id,
    required this.name,
    this.phone,
    this.whatsapp,
  });

  final String id;
  final String name;
  final String? phone;
  final String? whatsapp;

  factory OrderConfirmationContact.fromJson(Map<String, dynamic> json) {
    return OrderConfirmationContact(
      id: _stringValue(json['id']) ?? '',
      name: _stringValue(json['name']) ?? 'Customer',
      phone: _stringValue(json['phone']),
      whatsapp: _stringValue(json['whatsapp']),
    );
  }
}

class OrderConfirmationHubRecipient {
  const OrderConfirmationHubRecipient({
    required this.id,
    required this.name,
    required this.role,
    this.phone,
  });

  final String id;
  final String name;
  final String role;
  final String? phone;

  factory OrderConfirmationHubRecipient.fromJson(Map<String, dynamic> json) {
    return OrderConfirmationHubRecipient(
      id: _stringValue(json['id']) ?? '',
      name: _stringValue(json['name']) ?? '',
      role: _stringValue(json['role']) ?? '',
      phone: _stringValue(json['phone']),
    );
  }
}
