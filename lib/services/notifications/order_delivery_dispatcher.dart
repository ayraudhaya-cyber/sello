import 'package:sello/services/notifications/outbound/document_link_factory.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Sends the buyer an automatic SMS after a successful delivery write.
///
/// Delivery and inventory changes are already committed before this runs.
/// Notification failures must never roll them back.
class OrderDeliveryDispatcher {
  const OrderDeliveryDispatcher({
    required this.prepare,
    required this.recordDispatch,
    required this.policiesResolver,
    required this.smsSender,
    this.links = const DocumentLinkFactory(),
  });

  final Future<OrderDeliveryPrepareResult> Function(String orderId) prepare;
  final Future<bool> Function({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status,
    String? skipReason,
  })
  recordDispatch;
  final Future<OutboundNotificationPolicies> Function() policiesResolver;
  final OutboundSmsSender smsSender;
  final DocumentLinkFactory links;

  Future<void> dispatch(String orderId, {num? deliveredQuantity}) async {
    try {
      final policies = await policiesResolver();
      const type = OutboundNotificationType.orderDelivery;
      final policy = policies.policyFor(type);
      if (!policy.enabled ||
          !policies.smsEnabled ||
          !policy.sms ||
          (!policy.sendsTo(OutboundRecipientTarget.customer) &&
              !policy.sendsTo(OutboundRecipientTarget.hub))) {
        return;
      }

      final prepared = await prepare(orderId);
      if (prepared.eventId.isEmpty || prepared.customer.id.isEmpty) return;

      final invoiceUrl = policy.includeDocumentLink
          ? links.orderDocument(prepared.token)
          : null;
      final body = OutboundMessageTemplate.render(
        policies.templateOverride(type) ??
            OutboundMessageTemplate.defaultFor(type),
        values: {
          'business_name': prepared.companyName,
          'company_name': prepared.companyName,
          'customer_name': prepared.customer.name,
          'order_number': prepared.orderNumber,
          'invoice_number': prepared.orderNumber,
          'sales_rep_name': prepared.recordedByName,
          'delivery_status': prepared.deliveryStatus,
          'delivered_quantity': deliveredQuantity == null
              ? null
              : SelloFormatters.quantity(deliveredQuantity),
          'invoice_link': invoiceUrl,
          'document_link': invoiceUrl,
        },
      );

      if (policy.sendsTo(OutboundRecipientTarget.customer)) {
        await _send(
          prepared: prepared,
          kind: OutboundRecipientKind.customer,
          key: 'customer:${prepared.customer.id}',
          recipient: MessagingPhone.preferredSms(
            prepared.customer.phone,
            prepared.customer.whatsapp,
          ),
          body: body,
        );
      }
      if (policy.sendsTo(OutboundRecipientTarget.hub)) {
        for (final hub in prepared.hubRecipients) {
          await _send(
            prepared: prepared,
            kind: OutboundRecipientKind.hub,
            key: 'employee:${hub.id}',
            recipient: MessagingPhone.international(hub.phone),
            body: body,
          );
        }
      }
    } catch (_) {
      // Delivery is a completed business transaction even when SMS fails.
    }
  }

  Future<void> _send({
    required OrderDeliveryPrepareResult prepared,
    required OutboundRecipientKind kind,
    required String key,
    required String? recipient,
    required String body,
  }) async {
    if (recipient == null || recipient.isEmpty) {
      await recordDispatch(
        eventId: prepared.eventId,
        channel: OutboundChannel.sms,
        recipientKind: kind,
        recipientKey: key,
        address: null,
        status: OutboundDispatchStatus.skipped,
        skipReason: 'No usable SMS number.',
      );
      return;
    }
    await smsSender.send(
      OutboundSmsRequest(
        eventId: prepared.eventId,
        recipientKind: kind,
        recipientKey: key,
        recipient: recipient,
        message: body,
      ),
    );
  }
}

class OrderDeliveryPrepareResult {
  const OrderDeliveryPrepareResult({
    required this.eventId,
    required this.token,
    required this.orderNumber,
    required this.companyName,
    required this.deliveryStatus,
    required this.customer,
    this.recordedByName,
    this.hubRecipients = const [],
  });

  final String eventId;
  final String token;
  final String orderNumber;
  final String companyName;
  final String deliveryStatus;
  final OrderConfirmationContact customer;
  final String? recordedByName;
  final List<OrderConfirmationHubRecipient> hubRecipients;

  factory OrderDeliveryPrepareResult.fromJson(Map<String, dynamic> json) {
    final customerRaw = json['customer'];
    final customer = customerRaw is Map
        ? OrderConfirmationContact.fromJson(
            Map<String, dynamic>.from(customerRaw),
          )
        : const OrderConfirmationContact(id: '', name: '');
    final hubRaw = json['hub_recipients'];
    return OrderDeliveryPrepareResult(
      eventId: json['event_id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      companyName: json['company_name']?.toString() ?? 'Sello',
      deliveryStatus:
          json['delivery_status']?.toString() ?? 'delivery recorded',
      customer: customer,
      recordedByName: json['recorded_by_name']?.toString(),
      hubRecipients: [
        if (hubRaw is List)
          for (final row in hubRaw)
            if (row is Map)
              OrderConfirmationHubRecipient.fromJson(
                Map<String, dynamic>.from(row),
              ),
      ],
    );
  }
}
