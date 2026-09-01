import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Snapshot used to compose an order confirmation (no line items).
class OrderConfirmationCopy {
  const OrderConfirmationCopy({
    required this.companyName,
    required this.orderNumber,
    required this.customerName,
    required this.salesRepName,
    required this.orderedAt,
    required this.total,
    required this.currencyCode,
    required this.documentUrl,
  });

  final String companyName;
  final String orderNumber;
  final String customerName;
  final String salesRepName;
  final DateTime orderedAt;
  final num total;
  final String currencyCode;
  final String documentUrl;

  String get formattedTotal {
    final symbol = SelloFormatters.currencySymbol(currencyCode);
    return SelloFormatters.currency(total, symbol: symbol);
  }

  String get formattedDate => SelloFormatters.date(orderedAt);

  Map<String, String?> get templateValues {
    final business =
        companyName.trim().isEmpty ? 'Sello' : companyName.trim();
    final link = documentUrl.trim().isEmpty ? null : documentUrl.trim();
    final rep = salesRepName.trim().isEmpty ? null : salesRepName.trim();
    return {
      'business_name': business,
      'company_name': business,
      'order_number': orderNumber,
      'invoice_number': orderNumber,
      'customer_name': customerName,
      'sales_rep_name': rep,
      'date': formattedDate,
      'order_total': formattedTotal,
      'amount': formattedTotal,
      'invoice_link': link,
      'document_link': link,
    };
  }
}

/// Concise WhatsApp / SMS confirmation — never the full invoice.
abstract final class OrderConfirmationMessage {
  static String compose(
    OrderConfirmationCopy copy, {
    String? templateOverride,
    bool includeDocumentLink = true,
    OutboundNotificationType type = OutboundNotificationType.orderConfirmation,
  }) {
    final values = Map<String, String?>.from(copy.templateValues);
    if (!includeDocumentLink) {
      values['document_link'] = null;
      values['invoice_link'] = null;
      values['receipt_link'] = null;
    }
    final override = templateOverride?.trim();
    return OutboundMessageTemplate.render(
      (override != null && override.isNotEmpty)
          ? override
          : OutboundMessageTemplate.defaultFor(type),
      values: values,
    );
  }

  static String whatsappUri({
    required String digits,
    required String body,
  }) {
    return 'https://wa.me/$digits?text=${Uri.encodeComponent(body)}';
  }

  static String smsUri({
    required String digits,
    required String body,
  }) {
    return 'sms:$digits?body=${Uri.encodeComponent(body)}';
  }

  static String uriFor({
    required OutboundChannel channel,
    required String digits,
    required String body,
  }) {
    return switch (channel) {
      OutboundChannel.whatsapp => whatsappUri(digits: digits, body: body),
      OutboundChannel.sms => smsUri(digits: digits, body: body),
      OutboundChannel.inApp => '',
    };
  }
}
