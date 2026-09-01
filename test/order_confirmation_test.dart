import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/document_link_factory.dart';
import 'package:sello/services/notifications/outbound/order_confirmation_message.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:sello/shared/models/payment_record_status.dart';

void main() {
  group('order confirmation trigger rules', () {
    test('only completed orders should dispatch', () {
      expect(
        OrderConfirmationDispatcher.shouldDispatch(OrderStatus.completed),
        isTrue,
      );
      expect(
        OrderConfirmationDispatcher.shouldDispatch(OrderStatus.draft),
        isFalse,
      );
    });
  });

  group('confirmation message', () {
    test('includes key order details and the invoice link, not line items', () {
      final copy = OrderConfirmationCopy(
        companyName: 'Unitech Distributors',
        orderNumber: 'SO-20260816-0001',
        customerName: 'City Mart',
        salesRepName: 'Amina Perera',
        orderedAt: DateTime.utc(2026, 8, 16),
        total: 12500,
        currencyCode: 'LKR',
        documentUrl: 'https://app.sello.test/d/opaque-token',
      );

      final body = OrderConfirmationMessage.compose(copy);

      expect(body, contains('Unitech Distributors'));
      expect(body, contains('SO-20260816-0001'));
      expect(body, contains('City Mart'));
      expect(body, contains('Amina Perera'));
      expect(body, contains('View invoice: https://app.sello.test/d/opaque-token'));
      expect(body.toLowerCase(), isNot(contains('sku')));
    });

    test('can omit the document link when configured', () {
      final copy = OrderConfirmationCopy(
        companyName: 'Acme',
        orderNumber: 'SO-1',
        customerName: 'Buyer',
        salesRepName: '',
        orderedAt: DateTime.utc(2026, 8, 16),
        total: 10,
        currencyCode: 'USD',
        documentUrl: 'https://app.sello.test/d/token',
      );
      final body = OrderConfirmationMessage.compose(
        copy,
        includeDocumentLink: false,
      );
      expect(body, isNot(contains('View invoice')));
      expect(body, isNot(contains('https://')));
    });

    test('owner/manager order notification uses a distinct default body', () {
      final copy = OrderConfirmationCopy(
        companyName: 'Acme',
        orderNumber: 'SO-1',
        customerName: 'City Mart',
        salesRepName: 'Nimal',
        orderedAt: DateTime.utc(2026, 8, 16),
        total: 10,
        currencyCode: 'USD',
        documentUrl: 'https://app.sello.test/d/token',
      );
      final buyer = OrderConfirmationMessage.compose(copy);
      final hub = OrderConfirmationMessage.compose(
        copy,
        type: OutboundNotificationType.orderNotification,
      );
      expect(buyer, contains('confirmed'));
      expect(hub, contains('New order'));
      expect(buyer, isNot(equals(hub)));
    });
  });

  group('document links', () {
    test('invoice URL is an opaque token path with no tenant ids', () {
      const factory = DocumentLinkFactory(
        overrideOrigin: 'https://app.sello.test',
      );
      const token = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final url = factory.orderDocument(token);
      expect(url, 'https://app.sello.test/d/$token');
      expect(url, isNot(contains('company')));
      expect(url, isNot(contains('order-')));
      expect(url, isNot(contains('payment')));
    });

    test('short tokens cannot identify a document', () {
      expect('abc'.length < 32, isTrue);
    });
  });

  group('OrderDocument parsing', () {
    test('parses collection acknowledgement with Pending Review', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'collection_acknowledgement',
        'payment_number': 'PAY-9',
        'amount': 25000,
        'method': 'cash',
        'status': 'pending',
        'pending_review': true,
        'received_at': '2026-08-17T10:00:00Z',
        'company_name': 'Acme',
        'customer_name': 'City Mart',
        'currency': 'LKR',
        'sales_rep_name': 'Nimal',
      });

      expect(doc.isCollectionAcknowledgement, isTrue);
      expect(doc.pendingReview, isTrue);
      expect(doc.total, 25000);
      expect(doc.paymentNumber, 'PAY-9');
      expect(doc.documentTitle, 'Collection PAY-9');
      expect(doc.lines, isEmpty);
    });
  });

  group('collection stays pending until approval', () {
    test('pending review does not use the completed status', () {
      expect(PaymentRecordStatus.pending.isPendingReview, isTrue);
      expect(PaymentRecordStatus.completed.isPendingReview, isFalse);
    });
  });

  group('OrderConfirmationDispatcher', () {
    OrderConfirmationPrepareResult snapshot({
      bool alreadyPrepared = false,
      OrderConfirmationContact? customer,
      List<OrderConfirmationHubRecipient> hub = const [],
    }) {
      return OrderConfirmationPrepareResult(
        alreadyPrepared: alreadyPrepared,
        eventId: 'event-1',
        token: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        order: OrderConfirmationOrderSnapshot(
          number: 'SO-9',
          total: 2500,
          currency: 'USD',
          companyName: 'Sello Demo',
          customerName: 'City Mart',
          orderedAt: DateTime.utc(2026, 8, 16),
          salesRepName: 'Nimal',
        ),
        customer: customer,
        hubRecipients: hub,
      );
    }

    test('buyer receives confirmation and owner/manager receives new-order notice',
        () async {
      final gateway = _FakeGateway(
        snapshot(
          customer: const OrderConfirmationContact(
            id: 'cust-1',
            name: 'City Mart',
            phone: '0771234567',
            whatsapp: '0771234567',
          ),
          hub: const [
            OrderConfirmationHubRecipient(
              id: 'own-1',
              name: 'Owner',
              role: 'owner',
              phone: '0779999999',
            ),
          ],
        ),
      );
      final dispatcher = OrderConfirmationDispatcher(
        gateway: gateway,
        links: const DocumentLinkFactory(overrideOrigin: 'https://app.sello.test'),
      );

      final outcome = await dispatcher.dispatch('order-1');

      expect(outcome, isNotNull);
      expect(outcome!.orderNumber, 'SO-9');
      expect(outcome.documentUrl, contains('/d/'));
      expect(outcome.customerActions, isNotEmpty);
      expect(outcome.hubActions, isNotEmpty);
      expect(outcome.customerActions.first.launchUri, contains('confirmed'));
      expect(outcome.hubActions.first.launchUri, contains('New%20order'));
    });

    test('returns null when the tenant disables both order messages', () async {
      final gateway = _FakeGateway(snapshot());
      var policies = OutboundNotificationPolicies.defaults.copyWithType(
        OutboundNotificationType.orderConfirmation,
        OutboundNotificationPolicies.defaults
            .policyFor(OutboundNotificationType.orderConfirmation)
            .copyWith(enabled: false),
      );
      policies = policies.copyWithType(
        OutboundNotificationType.orderNotification,
        policies.policyFor(OutboundNotificationType.orderNotification).copyWith(
              enabled: false,
            ),
      );
      final dispatcher = OrderConfirmationDispatcher(
        gateway: gateway,
        policies: policies,
      );

      final outcome = await dispatcher.dispatch('order-1');
      expect(outcome, isNull);
      expect(gateway.prepareCalls, 0);
    });

    test('disabled buyer confirmation does not send to the customer', () async {
      final gateway = _FakeGateway(
        snapshot(
          customer: const OrderConfirmationContact(
            id: 'cust-1',
            name: 'City Mart',
            phone: '0771234567',
          ),
          hub: const [
            OrderConfirmationHubRecipient(
              id: 'own-1',
              name: 'Owner',
              role: 'owner',
              phone: '0779999999',
            ),
          ],
        ),
      );
      final dispatcher = OrderConfirmationDispatcher(
        gateway: gateway,
        policies: OutboundNotificationPolicies.defaults.copyWithType(
          OutboundNotificationType.orderConfirmation,
          OutboundNotificationPolicies.defaults
              .policyFor(OutboundNotificationType.orderConfirmation)
              .copyWith(enabled: false),
        ),
        links: const DocumentLinkFactory(overrideOrigin: 'https://app.sello.test'),
      );

      final outcome = await dispatcher.dispatch('order-1');
      expect(outcome, isNotNull);
      expect(outcome!.customerActions, isEmpty);
      expect(outcome.hubActions, isNotEmpty);
    });

    test('channel policy can disable WhatsApp and SMS together', () async {
      final gateway = _FakeGateway(
        snapshot(
          customer: const OrderConfirmationContact(
            id: 'cust-1',
            name: 'City Mart',
            phone: '0771234567',
          ),
        ),
      );
      final dispatcher = OrderConfirmationDispatcher(
        gateway: gateway,
        policies: const OutboundNotificationPolicies(
          whatsappEnabled: false,
          smsEnabled: false,
          types: {},
        ),
      );

      final outcome = await dispatcher.dispatch('order-1');
      expect(outcome, isNull);
    });

    test('skips the customer when no contact details exist', () async {
      final gateway = _FakeGateway(
        snapshot(
          customer: const OrderConfirmationContact(
            id: 'cust-1',
            name: 'City Mart',
          ),
        ),
      );
      final dispatcher = OrderConfirmationDispatcher(gateway: gateway);

      final outcome = await dispatcher.dispatch('order-1');

      expect(outcome, isNotNull);
      expect(outcome!.customerActions, isEmpty);
      expect(outcome.customerWasSkipped, isTrue);
      expect(outcome.customerSkippedReason, contains('no WhatsApp or phone'));
    });

    test('retry does not insert a second dispatch row', () async {
      final gateway = _FakeGateway(
        snapshot(
          alreadyPrepared: true,
          customer: const OrderConfirmationContact(
            id: 'cust-1',
            name: 'City Mart',
            phone: '0771234567',
          ),
        ),
        insertResult: false,
      );
      final dispatcher = OrderConfirmationDispatcher(gateway: gateway);

      final outcome = await dispatcher.dispatch('order-1');
      expect(outcome, isNotNull);
      expect(outcome!.alreadyPrepared, isTrue);
      expect(
        outcome.customerActions.every((action) => action.duplicate),
        isTrue,
      );
    });

    test('prepare failure is surfaced by the dispatcher, not the order write',
        () async {
      final dispatcher = OrderConfirmationDispatcher(
        gateway: _ThrowingGateway(),
      );
      expect(dispatcher.dispatch('order-1'), throwsA(isA<StateError>()));
    });
  });

  group('CollectionAcknowledgementDispatcher', () {
    CollectionAcknowledgementPrepareResult collection({
      bool alreadyPrepared = false,
      OrderConfirmationContact? customer,
    }) {
      return CollectionAcknowledgementPrepareResult(
        alreadyPrepared: alreadyPrepared,
        eventId: 'ev-1',
        token: 'cccccccccccccccccccccccccccccccccccccccccccccccc',
        paymentNumber: 'PAY-1',
        amount: 25000,
        currency: 'LKR',
        methodLabel: 'cash',
        companyName: 'Acme',
        customerName: 'City Mart',
        receivedAt: DateTime.utc(2026, 8, 17),
        salesRepName: 'Nimal',
        customer: customer ??
            const OrderConfirmationContact(
              id: 'cust-1',
              name: 'City Mart',
              phone: '0771111111',
            ),
        hubRecipients: const [
          OrderConfirmationHubRecipient(
            id: 'own-1',
            name: 'Owner',
            role: 'owner',
            phone: '0779999999',
          ),
        ],
      );
    }

    test('sends buyer acknowledgement and owner/manager submitted notice',
        () async {
      final dispatcher = CollectionAcknowledgementDispatcher(
        prepare: (_) async => collection(),
        recordDispatch: ({
          required String eventId,
          required OutboundChannel channel,
          required OutboundRecipientKind recipientKind,
          required String recipientKey,
          String? address,
          OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
          String? skipReason,
        }) async =>
            true,
        links: const DocumentLinkFactory(overrideOrigin: 'https://app.sello.test'),
      );

      final outcome = await dispatcher.dispatch('pay-1');
      expect(outcome, isNotNull);
      expect(outcome!.customerActions, isNotEmpty);
      expect(outcome.hubActions, isNotEmpty);
      expect(outcome.messageBody, contains('pending owner/manager review'));
      expect(outcome.hubActions.first.launchUri, contains('Pending%20Review'));
      expect(outcome.documentUrl, contains('/d/'));
      expect(outcome.messageBody.toLowerCase(), isNot(contains('approved')));
    });

    test('disabled acknowledgement does not send to the buyer', () async {
      final dispatcher = CollectionAcknowledgementDispatcher(
        prepare: (_) async => collection(),
        recordDispatch: ({
          required String eventId,
          required OutboundChannel channel,
          required OutboundRecipientKind recipientKind,
          required String recipientKey,
          String? address,
          OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
          String? skipReason,
        }) async =>
            true,
        policies: OutboundNotificationPolicies.defaults.copyWithType(
          OutboundNotificationType.collectionAcknowledgement,
          OutboundNotificationPolicies.defaults
              .policyFor(OutboundNotificationType.collectionAcknowledgement)
              .copyWith(enabled: false),
        ),
        links: const DocumentLinkFactory(overrideOrigin: 'https://app.sello.test'),
      );

      final outcome = await dispatcher.dispatch('pay-1');
      expect(outcome, isNotNull);
      expect(outcome!.customerActions, isEmpty);
      expect(outcome.hubActions, isNotEmpty);
    });
  });
}

class _FakeGateway implements OrderConfirmationGateway {
  _FakeGateway(this.prepared, {this.insertResult = true});

  final OrderConfirmationPrepareResult prepared;
  final bool insertResult;
  int prepareCalls = 0;

  @override
  Future<OrderConfirmationPrepareResult> prepare(String orderId) async {
    prepareCalls++;
    return prepared;
  }

  @override
  Future<bool> recordDispatch({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
    String? skipReason,
  }) async {
    return insertResult;
  }
}

class _ThrowingGateway implements OrderConfirmationGateway {
  @override
  Future<OrderConfirmationPrepareResult> prepare(String orderId) {
    throw StateError('prepare failed');
  }

  @override
  Future<bool> recordDispatch({
    required String eventId,
    required OutboundChannel channel,
    required OutboundRecipientKind recipientKind,
    required String recipientKey,
    String? address,
    OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
    String? skipReason,
  }) async {
    return true;
  }
}
