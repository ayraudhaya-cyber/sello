import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/notifications/order_delivery_dispatcher.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';

void main() {
  const prepared = OrderDeliveryPrepareResult(
    eventId: 'event-1',
    token: 'abcdefghijk',
    orderNumber: 'SO-1001',
    companyName: 'Namson Lanka',
    deliveryStatus: 'partially delivered',
    recordedByName: 'Ayaan',
    customer: OrderConfirmationContact(
      id: 'customer-1',
      name: 'SS Glass Point',
      phone: '0771234567',
    ),
    hubRecipients: [
      OrderConfirmationHubRecipient(
        id: 'owner-1',
        name: 'Owner',
        role: 'owner',
        phone: '0712345678',
      ),
    ],
  );

  test('delivery SMS includes status, quantity, and invoice link', () async {
    final sender = _FakeSmsSender();
    final dispatcher = OrderDeliveryDispatcher(
      prepare: (_) async => prepared,
      recordDispatch: _recordDispatch,
      policiesResolver: () async => OutboundNotificationPolicies.defaults,
      smsSender: sender,
    );

    await dispatcher.dispatch('order-1', deliveredQuantity: 12);

    expect(sender.requests, hasLength(1));
    expect(sender.requests.single.recipient, '94771234567');
    expect(sender.requests.single.message, contains('SO-1001'));
    expect(sender.requests.single.message, contains('partially delivered'));
    expect(sender.requests.single.message, contains('Quantity delivered: 12'));
    expect(sender.requests.single.message, contains('/d/abcdefghijk'));
  });

  test('disabled delivery message does not prepare or send', () async {
    var preparedCount = 0;
    final sender = _FakeSmsSender();
    final defaults = OutboundNotificationPolicies.defaults;
    final disabled = defaults.copyWithType(
      OutboundNotificationType.orderDelivery,
      defaults
          .policyFor(OutboundNotificationType.orderDelivery)
          .copyWith(enabled: false),
    );
    final dispatcher = OrderDeliveryDispatcher(
      prepare: (_) async {
        preparedCount++;
        return prepared;
      },
      recordDispatch: _recordDispatch,
      policiesResolver: () async => disabled,
      smsSender: sender,
    );

    await dispatcher.dispatch('order-1', deliveredQuantity: 12);

    expect(preparedCount, 0);
    expect(sender.requests, isEmpty);
  });

  test('delivery SMS can also be sent to Owner / Manager', () async {
    final sender = _FakeSmsSender();
    final defaults = OutboundNotificationPolicies.defaults;
    final withTeam = defaults.copyWithType(
      OutboundNotificationType.orderDelivery,
      defaults
          .policyFor(OutboundNotificationType.orderDelivery)
          .copyWith(
            recipients: const [
              OutboundRecipientTarget.customer,
              OutboundRecipientTarget.hub,
            ],
          ),
    );
    final dispatcher = OrderDeliveryDispatcher(
      prepare: (_) async => prepared,
      recordDispatch: _recordDispatch,
      policiesResolver: () async => withTeam,
      smsSender: sender,
    );

    await dispatcher.dispatch('order-1', deliveredQuantity: 12);

    expect(sender.requests, hasLength(2));
    expect(
      sender.requests.map((request) => request.recipientKind),
      containsAll([OutboundRecipientKind.customer, OutboundRecipientKind.hub]),
    );
    expect(sender.requests.last.recipient, '94712345678');
  });
}

Future<bool> _recordDispatch({
  required String eventId,
  required OutboundChannel channel,
  required OutboundRecipientKind recipientKind,
  required String recipientKey,
  String? address,
  OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
  String? skipReason,
}) async => true;

class _FakeSmsSender implements OutboundSmsSender {
  final requests = <OutboundSmsRequest>[];

  @override
  Future<OutboundSmsResult> send(OutboundSmsRequest request) async {
    requests.add(request);
    return const OutboundSmsResult(OutboundSmsStatus.sent);
  }

  @override
  Future<OutboundSmsResult> sendTest({required String recipient}) async {
    return const OutboundSmsResult(OutboundSmsStatus.sent);
  }

  @override
  Future<OutboundSmsResult> verifySender({
    required String recipient,
    required String senderId,
  }) async {
    return const OutboundSmsResult(OutboundSmsStatus.sent);
  }
}
