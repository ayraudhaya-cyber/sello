import 'package:sello/services/notifications/outbound/document_link_factory.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/order_confirmation_message.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Persistence used by [OrderConfirmationDispatcher]. Fakeable in tests.
abstract class OrderConfirmationGateway {
  Future<OrderConfirmationPrepareResult> prepare(String orderId);

  Future<bool> recordDispatch({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
    String? skipReason,
  });
}

/// Generates confirmation copy, WhatsApp share intents, and automatic SMS.
///
/// SMS is sent server-side (Text.lk). WhatsApp remains a device prefill.
/// Respects tenant [OutboundNotificationPolicies].
class OrderConfirmationDispatcher {
  OrderConfirmationDispatcher({
    required this.gateway,
    this.policies = OutboundNotificationPolicies.defaults,
    this.policiesResolver,
    this.links = const DocumentLinkFactory(),
    this.smsSender,
  });

  final OrderConfirmationGateway gateway;
  final OutboundNotificationPolicies policies;
  final Future<OutboundNotificationPolicies> Function()? policiesResolver;
  final DocumentLinkFactory links;
  final OutboundSmsSender? smsSender;

  static bool shouldDispatch(OrderStatus status) =>
      status == OrderStatus.completed;

  Future<OutboundNotificationPolicies> _resolvePolicies() async {
    final resolver = policiesResolver;
    if (resolver == null) return policies;
    return resolver();
  }

  static const _orderTypes = [
    OutboundNotificationType.orderConfirmation,
    OutboundNotificationType.orderNotification,
  ];

  Future<OrderConfirmationOutcome?> dispatch(String orderId) async {
    final effectivePolicies = await _resolvePolicies();
    final activeTypes = [
      for (final type in _orderTypes)
        if (effectivePolicies.isActive(type)) type,
    ];
    if (activeTypes.isEmpty) return null;

    final prepared = await gateway.prepare(orderId);
    final tokenUrl = links.orderDocument(prepared.token);
    final copy = OrderConfirmationCopy(
      companyName: prepared.order.companyName,
      orderNumber: prepared.order.number,
      customerName: prepared.order.customerName,
      salesRepName: prepared.order.salesRepName ?? '',
      orderedAt: prepared.order.completedAt ??
          prepared.order.orderedAt ??
          DateTime.now().toUtc(),
      total: prepared.order.total,
      currencyCode: prepared.order.currency,
      documentUrl: tokenUrl,
    );

    final actions = <OrderConfirmationAction>[];
    String? customerSkipped;
    String messageBody = '';
    var includeAnyLink = false;

    for (final type in activeTypes) {
      final typePolicy = effectivePolicies.policyFor(type);
      if (typePolicy.includeDocumentLink) includeAnyLink = true;
      final body = OrderConfirmationMessage.compose(
        copy,
        templateOverride: effectivePolicies.templateOverride(type),
        includeDocumentLink: typePolicy.includeDocumentLink,
        type: type,
      );
      if (type == OutboundNotificationType.orderConfirmation ||
          messageBody.isEmpty) {
        messageBody = body;
      }
      final channelPolicy = OutboundChannelPolicy.fromType(
        masterWhatsapp: effectivePolicies.whatsappEnabled,
        masterSms: effectivePolicies.smsEnabled,
        typeWhatsapp: typePolicy.whatsapp,
        typeSms: typePolicy.sms,
      );

      if (typePolicy.sendsTo(OutboundRecipientTarget.customer)) {
        final skipped = await _dispatchCustomer(
          prepared: prepared,
          actions: actions,
          body: body,
          channelPolicy: channelPolicy,
        );
        customerSkipped ??= skipped;
      }

      if (typePolicy.sendsTo(OutboundRecipientTarget.hub)) {
        await _dispatchHub(
          prepared: prepared,
          actions: actions,
          body: body,
          channelPolicy: channelPolicy,
        );
      }

      if (typePolicy.sendsTo(OutboundRecipientTarget.salesRep)) {
        await _dispatchSalesRep(
          prepared: prepared,
          actions: actions,
          body: body,
          channelPolicy: channelPolicy,
        );
      }
    }

    return OrderConfirmationOutcome(
      orderNumber: prepared.order.number,
      documentUrl: includeAnyLink ? tokenUrl : '',
      messageBody: messageBody,
      alreadyPrepared: prepared.alreadyPrepared,
      eventId: prepared.eventId,
      token: prepared.token,
      actions: actions,
      customerSkippedReason: customerSkipped,
    );
  }

  Future<String?> _dispatchCustomer({
    required OrderConfirmationPrepareResult prepared,
    required List<OrderConfirmationAction> actions,
    required String body,
    required OutboundChannelPolicy channelPolicy,
  }) async {
    final customer = prepared.customer;
    if (customer == null || customer.id.isEmpty) {
      return 'Customer record is missing.';
    }
        final whatsapp = MessagingPhone.preferredWhatsApp(
          customer.whatsapp,
          customer.phone,
        );
        final sms = MessagingPhone.preferredSms(
          customer.phone,
          customer.whatsapp,
        );
        if (whatsapp == null && sms == null) {
          const skipped = 'Customer has no WhatsApp or phone number.';
          await _skip(
            prepared.eventId,
            channel: OutboundChannel.whatsapp,
            kind: OutboundRecipientKind.customer,
            key: 'customer:${customer.id}',
            reason: skipped,
          );
          return skipped;
        }
        await _addChannelActions(
          actions: actions,
          eventId: prepared.eventId,
          kind: OutboundRecipientKind.customer,
          key: 'customer:${customer.id}',
          name: customer.name,
          whatsappDigits: whatsapp,
          smsRecipient: sms,
          body: body,
          alreadyPrepared: prepared.alreadyPrepared,
          policy: channelPolicy,
        );
        return null;
  }

  Future<void> _dispatchHub({
    required OrderConfirmationPrepareResult prepared,
    required List<OrderConfirmationAction> actions,
    required String body,
    required OutboundChannelPolicy channelPolicy,
  }) async {
    for (final hub in prepared.hubRecipients) {
      final digits = MessagingPhone.digits(hub.phone);
      if (digits == null) {
        await _skip(
          prepared.eventId,
          channel: OutboundChannel.whatsapp,
          kind: OutboundRecipientKind.hub,
          key: 'employee:${hub.id}',
          reason: 'No phone number.',
        );
        continue;
      }
      await _addChannelActions(
        actions: actions,
        eventId: prepared.eventId,
        kind: OutboundRecipientKind.hub,
        key: 'employee:${hub.id}',
        name: hub.name,
        whatsappDigits: digits,
        smsRecipient: MessagingPhone.international(hub.phone),
        body: body,
        alreadyPrepared: prepared.alreadyPrepared,
        policy: channelPolicy,
        roleLabel: hub.role == 'owner' ? 'Owner' : 'Manager',
      );
    }
  }

  Future<void> _dispatchSalesRep({
    required OrderConfirmationPrepareResult prepared,
    required List<OrderConfirmationAction> actions,
    required String body,
    required OutboundChannelPolicy channelPolicy,
  }) async {
    final rep = prepared.salesRep;
    if (rep == null || rep.id.isEmpty) return;
    final digits = MessagingPhone.digits(rep.phone);
    if (digits == null) {
      await _skip(
        prepared.eventId,
        channel: OutboundChannel.whatsapp,
        kind: OutboundRecipientKind.salesRep,
        key: 'employee:${rep.id}',
        reason: 'No phone number.',
      );
      return;
    }
    await _addChannelActions(
      actions: actions,
      eventId: prepared.eventId,
      kind: OutboundRecipientKind.salesRep,
      key: 'employee:${rep.id}',
      name: rep.name,
      whatsappDigits: digits,
      smsRecipient: MessagingPhone.international(rep.phone),
      body: body,
      alreadyPrepared: prepared.alreadyPrepared,
      policy: channelPolicy,
      roleLabel: 'Sales rep',
    );
  }

  Future<void> _addChannelActions({
    required List<OrderConfirmationAction> actions,
    required String? eventId,
    required OutboundRecipientKind kind,
    required String key,
    required String name,
    required String? whatsappDigits,
    required String? smsRecipient,
    required String body,
    required bool alreadyPrepared,
    required OutboundChannelPolicy policy,
    String? roleLabel,
  }) async {
    if (policy.whatsapp && whatsappDigits != null) {
      final inserted = await _record(
        eventId,
        channel: OutboundChannel.whatsapp,
        kind: kind,
        key: key,
        address: whatsappDigits,
      );
      actions.add(
        OrderConfirmationAction(
          channel: OutboundChannel.whatsapp,
          recipientKind: kind,
          recipientKey: key,
          recipientName: name,
          address: whatsappDigits,
          label: kind == OutboundRecipientKind.customer
              ? 'WhatsApp customer'
              : 'WhatsApp ${roleLabel ?? name}',
          launchUri: OrderConfirmationMessage.whatsappUri(
            digits: whatsappDigits,
            body: body,
          ),
          duplicate: alreadyPrepared || inserted == false,
        ),
      );
    }
    if (policy.sms) {
      await _deliverSms(
        sender: smsSender,
        eventId: eventId,
        kind: kind,
        key: key,
        recipient: smsRecipient,
        body: body,
      );
    }
  }

  Future<void> _deliverSms({
    required OutboundSmsSender? sender,
    required String? eventId,
    required OutboundRecipientKind kind,
    required String key,
    required String? recipient,
    required String body,
  }) async {
    if (eventId == null || eventId.isEmpty) return;
    if (sender == null) return;
    if (recipient == null || recipient.isEmpty) {
      await _skip(
        eventId,
        channel: OutboundChannel.sms,
        kind: kind,
        key: key,
        reason: 'No usable SMS number.',
      );
      return;
    }
    try {
      final result = await sender.send(
        OutboundSmsRequest(
          eventId: eventId,
          recipientKind: kind,
          recipientKey: key,
          recipient: recipient,
          message: body,
        ),
      );
      if (result.status == OutboundSmsStatus.skippedMissingSender) {
        await _skip(
          eventId,
          channel: OutboundChannel.sms,
          kind: kind,
          key: key,
          reason: 'SMS Sender ID is not configured.',
        );
      }
    } catch (_) {
      // SMS must never fail the business transaction.
    }
  }

  Future<bool?> _record(
    String? eventId, {
    required OutboundChannel channel,
    required OutboundRecipientKind kind,
    required String key,
    String? address,
  }) async {
    if (eventId == null || eventId.isEmpty) return null;
    return gateway.recordDispatch(
      eventId: eventId,
      channel: channel,
      recipientKind: kind,
      recipientKey: key,
      address: address,
      status: OutboundDispatchStatus.prepared,
    );
  }

  Future<void> _skip(
    String? eventId, {
    required OutboundChannel channel,
    required OutboundRecipientKind kind,
    required String key,
    required String reason,
  }) async {
    if (eventId == null || eventId.isEmpty) return;
    await gateway.recordDispatch(
      eventId: eventId,
      channel: channel,
      recipientKind: kind,
      recipientKey: key,
      status: OutboundDispatchStatus.skipped,
      skipReason: reason,
    );
  }
}

/// Collection acknowledgement share intents (pending review — not approved).
class CollectionAcknowledgementDispatcher {
  CollectionAcknowledgementDispatcher({
    required this.prepare,
    required this.recordDispatch,
    this.policies = OutboundNotificationPolicies.defaults,
    this.policiesResolver,
    this.links = const DocumentLinkFactory(),
    this.smsSender,
  });

  final Future<CollectionAcknowledgementPrepareResult> Function(String paymentId)
      prepare;
  final Future<bool> Function({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status,
    String? skipReason,
  }) recordDispatch;
  final OutboundNotificationPolicies policies;
  final Future<OutboundNotificationPolicies> Function()? policiesResolver;
  final DocumentLinkFactory links;
  final OutboundSmsSender? smsSender;

  static const _collectionTypes = [
    OutboundNotificationType.collectionAcknowledgement,
    OutboundNotificationType.collectionSubmitted,
  ];

  Future<OrderConfirmationOutcome?> dispatch(String paymentId) async {
    final resolver = policiesResolver;
    final effectivePolicies =
        resolver == null ? policies : await resolver();
    final activeTypes = [
      for (final type in _collectionTypes)
        if (effectivePolicies.isActive(type)) type,
    ];
    if (activeTypes.isEmpty) return null;

    final prepared = await prepare(paymentId);
    final tokenUrl = links.orderDocument(prepared.token);
    final symbol = SelloFormatters.currencySymbol(prepared.currency);
    final amountLabel =
        SelloFormatters.currency(prepared.amount, symbol: symbol);

    final actions = <OrderConfirmationAction>[];
    String messageBody = '';
    var includeAnyLink = false;
    String? customerSkipped;

    for (final type in activeTypes) {
      final typePolicy = effectivePolicies.policyFor(type);
      if (typePolicy.includeDocumentLink) includeAnyLink = true;
      final documentUrl = typePolicy.includeDocumentLink ? tokenUrl : '';
      final body = OutboundMessageTemplate.render(
        effectivePolicies.templateOverride(type) ??
            OutboundMessageTemplate.defaultFor(type),
        values: {
          'business_name': prepared.companyName,
          'company_name': prepared.companyName,
          'customer_name': prepared.customerName,
          'sales_rep_name': prepared.salesRepName,
          'collection_amount': amountLabel,
          'amount': amountLabel,
          'collection_number': prepared.paymentNumber,
          'payment_number': prepared.paymentNumber,
          'payment_method': prepared.methodLabel,
          'date': SelloFormatters.date(prepared.receivedAt),
          'receipt_link': documentUrl.trim().isEmpty ? null : documentUrl.trim(),
          'document_link':
              documentUrl.trim().isEmpty ? null : documentUrl.trim(),
        },
      );
      if (type == OutboundNotificationType.collectionAcknowledgement ||
          messageBody.isEmpty) {
        messageBody = body;
      }

      final channelPolicy = OutboundChannelPolicy.fromType(
        masterWhatsapp: effectivePolicies.whatsappEnabled,
        masterSms: effectivePolicies.smsEnabled,
        typeWhatsapp: typePolicy.whatsapp,
        typeSms: typePolicy.sms,
      );

      if (typePolicy.sendsTo(OutboundRecipientTarget.customer)) {
        final skipped = await _addCustomerActions(
          prepared: prepared,
          actions: actions,
          body: body,
          channelPolicy: channelPolicy,
        );
        customerSkipped ??= skipped;
      }

      if (typePolicy.sendsTo(OutboundRecipientTarget.hub)) {
        await _addHubActions(
          prepared: prepared,
          actions: actions,
          body: body,
          channelPolicy: channelPolicy,
        );
      }
    }

    return OrderConfirmationOutcome(
      orderNumber: prepared.paymentNumber,
      documentUrl: includeAnyLink ? tokenUrl : '',
      messageBody: messageBody,
      alreadyPrepared: prepared.alreadyPrepared,
      eventId: prepared.eventId,
      token: prepared.token,
      actions: actions,
      customerSkippedReason: customerSkipped,
    );
  }

  Future<String?> _addCustomerActions({
    required CollectionAcknowledgementPrepareResult prepared,
    required List<OrderConfirmationAction> actions,
    required String body,
    required OutboundChannelPolicy channelPolicy,
  }) async {
    final customer = prepared.customer;
    if (customer == null || customer.id.isEmpty) {
      return 'Customer record is missing.';
    }
    final whatsapp = MessagingPhone.preferredWhatsApp(
      customer.whatsapp,
      customer.phone,
    );
    final sms = MessagingPhone.preferredSms(
      customer.phone,
      customer.whatsapp,
    );
    if (whatsapp == null && sms == null) {
      return 'Customer has no WhatsApp or phone number.';
    }
    if (channelPolicy.whatsapp && whatsapp != null) {
      await recordDispatch(
        eventId: prepared.eventId,
        channel: OutboundChannel.whatsapp,
        recipientKind: OutboundRecipientKind.customer,
        recipientKey: 'customer:${customer.id}',
        address: whatsapp,
        status: OutboundDispatchStatus.prepared,
      );
      actions.add(
        OrderConfirmationAction(
          channel: OutboundChannel.whatsapp,
          recipientKind: OutboundRecipientKind.customer,
          recipientKey: 'customer:${customer.id}',
          recipientName: customer.name,
          address: whatsapp,
          label: 'WhatsApp customer',
          launchUri: OrderConfirmationMessage.whatsappUri(
            digits: whatsapp,
            body: body,
          ),
          duplicate: prepared.alreadyPrepared,
        ),
      );
    }
    if (channelPolicy.sms) {
      await _deliverSms(
        eventId: prepared.eventId,
        kind: OutboundRecipientKind.customer,
        key: 'customer:${customer.id}',
        recipient: sms,
        body: body,
      );
    }
    return null;
  }

  Future<void> _addHubActions({
    required CollectionAcknowledgementPrepareResult prepared,
    required List<OrderConfirmationAction> actions,
    required String body,
    required OutboundChannelPolicy channelPolicy,
  }) async {
    for (final hub in prepared.hubRecipients) {
      final digits = MessagingPhone.digits(hub.phone);
      if (digits == null) continue;
      if (channelPolicy.whatsapp) {
        await recordDispatch(
          eventId: prepared.eventId,
          channel: OutboundChannel.whatsapp,
          recipientKind: OutboundRecipientKind.hub,
          recipientKey: 'employee:${hub.id}',
          address: digits,
          status: OutboundDispatchStatus.prepared,
        );
        actions.add(
          OrderConfirmationAction(
            channel: OutboundChannel.whatsapp,
            recipientKind: OutboundRecipientKind.hub,
            recipientKey: 'employee:${hub.id}',
            recipientName: hub.name,
            address: digits,
            label: 'WhatsApp ${hub.role == 'owner' ? 'Owner' : 'Manager'}',
            launchUri: OrderConfirmationMessage.whatsappUri(
              digits: digits,
              body: body,
            ),
            duplicate: prepared.alreadyPrepared,
          ),
        );
      }
      if (channelPolicy.sms) {
        await _deliverSms(
          eventId: prepared.eventId,
          kind: OutboundRecipientKind.hub,
          key: 'employee:${hub.id}',
          recipient: MessagingPhone.international(hub.phone),
          body: body,
        );
      }
    }
  }

  Future<void> _deliverSms({
    required String eventId,
    required OutboundRecipientKind kind,
    required String key,
    required String? recipient,
    required String body,
  }) async {
    final sender = smsSender;
    if (sender == null) return;
    if (recipient == null || recipient.isEmpty) {
      await recordDispatch(
        eventId: eventId,
        channel: OutboundChannel.sms,
        recipientKind: kind,
        recipientKey: key,
        address: null,
        status: OutboundDispatchStatus.skipped,
        skipReason: 'No usable SMS number.',
      );
      return;
    }
    try {
      final result = await sender.send(
        OutboundSmsRequest(
          eventId: eventId,
          recipientKind: kind,
          recipientKey: key,
          recipient: recipient,
          message: body,
        ),
      );
      if (result.status == OutboundSmsStatus.skippedMissingSender) {
        await recordDispatch(
          eventId: eventId,
          channel: OutboundChannel.sms,
          recipientKind: kind,
          recipientKey: key,
          address: recipient,
          status: OutboundDispatchStatus.skipped,
          skipReason: 'SMS Sender ID is not configured.',
        );
      }
    } catch (_) {}
  }
}

class CollectionAcknowledgementPrepareResult {
  const CollectionAcknowledgementPrepareResult({
    required this.alreadyPrepared,
    required this.eventId,
    required this.token,
    required this.paymentNumber,
    required this.amount,
    required this.currency,
    required this.methodLabel,
    required this.companyName,
    required this.customerName,
    required this.receivedAt,
    this.salesRepName,
    this.customer,
    this.hubRecipients = const [],
  });

  final bool alreadyPrepared;
  final String eventId;
  final String token;
  final String paymentNumber;
  final num amount;
  final String currency;
  final String methodLabel;
  final String companyName;
  final String customerName;
  final DateTime receivedAt;
  final String? salesRepName;
  final OrderConfirmationContact? customer;
  final List<OrderConfirmationHubRecipient> hubRecipients;

  factory CollectionAcknowledgementPrepareResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final payment = json['payment'];
    final paymentMap = payment is Map
        ? Map<String, dynamic>.from(payment)
        : <String, dynamic>{};
    final hubJson = json['hub_recipients'];
    final customerJson = json['customer'];
    final method = paymentMap['method']?.toString() ?? 'cash';
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

    return CollectionAcknowledgementPrepareResult(
      alreadyPrepared: json['already_prepared'] == true,
      eventId: json['event_id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      paymentNumber: paymentMap['number']?.toString() ?? '',
      amount: paymentMap['amount'] is num
          ? paymentMap['amount'] as num
          : num.tryParse('${paymentMap['amount']}') ?? 0,
      currency: paymentMap['currency']?.toString() ?? 'USD',
      methodLabel: method.replaceAll('_', ' '),
      companyName: paymentMap['company_name']?.toString() ?? 'Sello',
      customerName: paymentMap['customer_name']?.toString() ?? 'Customer',
      receivedAt: DateTime.tryParse(paymentMap['received_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      salesRepName: paymentMap['sales_rep_name']?.toString(),
      customer: parseContact(customerJson),
      hubRecipients: [
        if (hubJson is List)
          for (final row in hubJson)
            if (row is Map)
              OrderConfirmationHubRecipient.fromJson(
                Map<String, dynamic>.from(row),
              ),
      ],
    );
  }
}
