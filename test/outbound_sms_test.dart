import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/document_link_factory.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

void main() {
  group('MessagingPhone', () {
    test('does not blindly prefix 94 when a country code is present', () {
      expect(MessagingPhone.international('0765644465'), '94765644465');
      expect(MessagingPhone.international('076 564 4465'), '94765644465');
      expect(MessagingPhone.international('+94 76 564 4465'), '94765644465');
      expect(MessagingPhone.international('94765644465'), '94765644465');
      expect(MessagingPhone.international('0771234567'), '94771234567');
      expect(MessagingPhone.international('94771234567'), '94771234567');
      expect(MessagingPhone.international('+94 77 123 4567'), '94771234567');
      expect(MessagingPhone.international('0094771234567'), '94771234567');
      expect(MessagingPhone.international('+14155552671'), '14155552671');
    });

    test('returns null for unusable values', () {
      expect(MessagingPhone.international(null), isNull);
      expect(MessagingPhone.international(''), isNull);
      expect(MessagingPhone.international('123'), isNull);
    });
  });

  group('SmsSenderId', () {
    test('keeps registered casing and strips spaces', () {
      expect(SmsSenderId.normalize('AcmeSender'), 'AcmeSender');
      expect(SmsSenderId.normalize(' Acme Sender '), 'AcmeSender');
      expect(SmsSenderId.normalize('AB'), isNull);
      expect(SmsSenderId.normalize('THISISTOOLONG'), 'THISISTOOLO');
      expect(SmsSenderId.normalize('Bad-Id!'), 'BadId');
    });

    test('tryParse rejects invalid input instead of rewriting it', () {
      expect(SmsSenderId.tryParse('AcmeCo'), 'AcmeCo');
      expect(SmsSenderId.tryParse('AB'), isNull);
      expect(SmsSenderId.tryParse('Bad-Id!'), isNull);
      expect(SmsSenderId.tryParse(' AcmeCo '), 'AcmeCo');
    });
  });

  group('OutboundSmsRequest', () {
    test('never includes Sender ID, API token, or Text.lk fields', () {
      const request = OutboundSmsRequest(
        eventId: 'event-1',
        recipientKind: OutboundRecipientKind.customer,
        recipientKey: 'customer:cust-1',
        recipient: '94771234567',
        message: 'Hello',
      );
      final json = request.toJson();
      expect(
        json.keys,
        unorderedEquals([
          'event_id',
          'recipient_kind',
          'recipient_key',
          'recipient',
          'message',
        ]),
      );
      expect(json.containsKey('sender_id'), isFalse);
      expect(json.containsKey('senderId'), isFalse);
      expect(json.toString().toLowerCase(), isNot(contains('token')));
      expect(json.toString().toLowerCase(), isNot(contains('text.lk')));
    });
  });

  group('configured Sender ID', () {
    test('defaults to read-only with no Sender ID', () {
      expect(CompanySettings.defaults.smsSenderId, isNull);
      expect(CompanySettings.defaults.smsSenderIdEditable, isFalse);
    });

    test('fromJson treats a missing editable flag as false', () {
      final settings = CompanySettings.fromJson(
        _settingsRow({'sms_sender_id': 'AcmeCo'}),
      );
      expect(settings.smsSenderId, 'AcmeCo');
      expect(settings.smsSenderIdEditable, isFalse);
    });

    test('each company keeps its own configured Sender ID', () {
      final tenantA = CompanySettings.fromJson(
        _settingsRow({'company_id': 'company-a', 'sms_sender_id': 'AcmeCo'}),
      );
      final tenantB = CompanySettings.fromJson(
        _settingsRow({'company_id': 'company-b', 'sms_sender_id': 'OtherCo'}),
      );
      expect(tenantA.smsSenderId, 'AcmeCo');
      expect(tenantB.smsSenderId, 'OtherCo');
    });

    test('read-only Sender ID is omitted from the client update payload', () {
      final settings = CompanySettings.fromJson(
        _settingsRow({
          'sms_sender_id': 'AcmeCo',
          'sms_sender_id_editable': false,
        }),
      );
      final payload = settings.toUpdatePayload(employeeId: 'emp-a');
      expect(payload.containsKey('sms_sender_id'), isFalse);
      expect(payload.containsKey('sms_sender_id_editable'), isFalse);
      expect(payload.keys, isNot(contains('textlk_api_token')));
    });

    test('copyWith cannot change Sender ID when editing is disabled', () {
      final settings = CompanySettings.fromJson(
        _settingsRow({
          'sms_sender_id': 'AcmeCo',
          'sms_sender_id_editable': false,
        }),
      );
      expect(settings.copyWith(smsSenderId: 'HackedId').smsSenderId, 'AcmeCo');
      expect(settings.copyWith(clearSmsSenderId: true).smsSenderId, 'AcmeCo');
      expect(settings.copyWith(currency: 'LKR').smsSenderIdEditable, isFalse);
    });

    test('editable Sender ID is included in the client update payload', () {
      final settings = CompanySettings.fromJson(
        _settingsRow({
          'sms_sender_id': 'AcmeCo',
          'sms_sender_id_editable': true,
        }),
      );
      final payload = settings.toUpdatePayload(employeeId: 'emp-a');
      expect(payload['sms_sender_id'], 'AcmeCo');
      expect(payload.containsKey('sms_sender_id_editable'), isFalse);
    });

    test('copyWith can change Sender ID when editing is enabled', () {
      final settings = CompanySettings.fromJson(
        _settingsRow({
          'sms_sender_id': 'AcmeCo',
          'sms_sender_id_editable': true,
        }),
      );
      expect(
        settings.copyWith(smsSenderId: 'NewSender').smsSenderId,
        'NewSender',
      );
      expect(settings.copyWith(clearSmsSenderId: true).smsSenderId, isNull);
      expect(
        settings.copyWith(smsSenderId: 'NewSender').smsSenderIdEditable,
        isTrue,
      );
    });
  });

  group('Sender ID permissions', () {
    PermissionService service(String role) =>
        PermissionService(profile: RolePermissionProfile.forRoleCode(role));

    test('Owner cannot edit Sender ID while it is managed by Sello', () {
      expect(service('owner').canEditSmsSenderId(false), isFalse);
      expect(service('manager').canEditSmsSenderId(false), isFalse);
      expect(service('administrator').canEditSmsSenderId(false), isFalse);
    });

    test('Owner and Manager can edit Sender ID when Sello enables it', () {
      expect(service('owner').canEditSmsSenderId(true), isTrue);
      expect(service('manager').canEditSmsSenderId(true), isTrue);
      expect(service('administrator').canEditSmsSenderId(true), isTrue);
      expect(service('sales_representative').canEditSmsSenderId(true), isFalse);
    });

    test('Owner and Manager can send a test SMS; Sales cannot', () {
      expect(service('owner').canSendTestSms, isTrue);
      expect(service('manager').canSendTestSms, isTrue);
      expect(service('administrator').canSendTestSms, isTrue);
      expect(service('sales_representative').canSendTestSms, isFalse);
    });
  });

  group('OrderConfirmationDispatcher SMS', () {
    OrderConfirmationPrepareResult snapshot({
      OrderConfirmationContact? customer,
      List<OrderConfirmationHubRecipient>? hub,
    }) {
      return OrderConfirmationPrepareResult(
        alreadyPrepared: false,
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
        customer:
            customer ??
            const OrderConfirmationContact(
              id: 'cust-1',
              name: 'City Mart',
              phone: '0771234567',
              whatsapp: '0771234567',
            ),
        hubRecipients:
            hub ??
            const [
              OrderConfirmationHubRecipient(
                id: 'own-1',
                name: 'Owner',
                role: 'owner',
                phone: '0779999999',
              ),
            ],
      );
    }

    test(
      'SMS disabled → no Text.lk request; WhatsApp still prefills',
      () async {
        final sms = _RecordingSmsSender();
        final gateway = _RecordingGateway(snapshot());
        final dispatcher = OrderConfirmationDispatcher(
          gateway: gateway,
          smsSender: sms,
          policies: OutboundNotificationPolicies.defaults.copyWith(
            smsEnabled: false,
          ),
          links: const DocumentLinkFactory(
            overrideOrigin: 'https://app.sello.test',
          ),
        );

        final outcome = await dispatcher.dispatch('order-1');

        expect(sms.requests, isEmpty);
        expect(sms.providerPosts, 0);
        expect(outcome, isNotNull);
        expect(outcome!.actions, isNotEmpty);
        expect(
          outcome.actions.every((a) => a.channel == OutboundChannel.whatsapp),
          isTrue,
        );
        expect(outcome.customerActions.first.launchUri, contains('wa.me'));
        expect(
          outcome.customerActions.first.launchUri,
          isNot(contains('sms:')),
        );
      },
    );

    test('message disabled → no Text.lk request to that audience', () async {
      final sms = _RecordingSmsSender();
      final dispatcher = OrderConfirmationDispatcher(
        gateway: _RecordingGateway(snapshot()),
        smsSender: sms,
        policies: OutboundNotificationPolicies.defaults.copyWithType(
          OutboundNotificationType.orderConfirmation,
          OutboundNotificationPolicies.defaults
              .policyFor(OutboundNotificationType.orderConfirmation)
              .copyWith(enabled: false),
        ),
        links: const DocumentLinkFactory(
          overrideOrigin: 'https://app.sello.test',
        ),
      );

      await dispatcher.dispatch('order-1');

      expect(
        sms.requests.where(
          (r) => r.recipientKind == OutboundRecipientKind.customer,
        ),
        isEmpty,
      );
      expect(
        sms.requests.where((r) => r.recipientKind == OutboundRecipientKind.hub),
        isNotEmpty,
      );
    });

    test('missing Sender ID → no provider send and graceful skip', () async {
      final sms = _RecordingSmsSender(
        result: const OutboundSmsResult(
          OutboundSmsStatus.skippedMissingSender,
          reason: 'missing_sender_id',
        ),
      );
      final gateway = _RecordingGateway(snapshot());
      final dispatcher = OrderConfirmationDispatcher(
        gateway: gateway,
        smsSender: sms,
        policies: OutboundNotificationPolicies.defaults.copyWith(
          whatsappEnabled: false,
        ),
        links: const DocumentLinkFactory(
          overrideOrigin: 'https://app.sello.test',
        ),
      );

      final outcome = await dispatcher.dispatch('order-1');

      expect(outcome, isNotNull);
      expect(sms.providerPosts, 0);
      expect(
        gateway.records.any(
          (row) =>
              row['channel'] == OutboundChannel.sms &&
              row['status'] == OutboundDispatchStatus.skipped &&
              '${row['skipReason']}'.contains('Sender ID'),
        ),
        isTrue,
      );
    });

    test('missing recipient phone → no Text.lk request', () async {
      final sms = _RecordingSmsSender();
      final gateway = _RecordingGateway(
        snapshot(
          customer: const OrderConfirmationContact(
            id: 'cust-1',
            name: 'City Mart',
          ),
          hub: const [],
        ),
      );
      final dispatcher = OrderConfirmationDispatcher(
        gateway: gateway,
        smsSender: sms,
        policies: OutboundNotificationPolicies.defaults.copyWith(
          whatsappEnabled: false,
        ),
      );

      final outcome = await dispatcher.dispatch('order-1');

      expect(sms.requests, isEmpty);
      expect(outcome!.customerWasSkipped, isTrue);
    });

    test(
      'uses international recipient and rendered template with invoice link',
      () async {
        final sms = _RecordingSmsSender();
        const template =
            'Hi {{customer_name}},\nYour order {{order_number}} has been confirmed.\nTotal: {{order_total}}\n\nView invoice:\n{{invoice_link}}';
        final dispatcher = OrderConfirmationDispatcher(
          gateway: _RecordingGateway(snapshot()),
          smsSender: sms,
          policies: OutboundNotificationPolicies.defaults
              .copyWith(whatsappEnabled: false)
              .copyWithTemplate(
                OutboundNotificationType.orderConfirmation,
                template,
              ),
          links: const DocumentLinkFactory(
            overrideOrigin: 'https://app.sello.test',
          ),
        );

        await dispatcher.dispatch('order-1');

        final buyer = sms.requests.firstWhere(
          (r) => r.recipientKind == OutboundRecipientKind.customer,
        );
        expect(buyer.recipient, '94771234567');
        expect(buyer.message, contains('Hi City Mart'));
        expect(buyer.message, contains('SO-9'));
        expect(buyer.message, contains('View invoice:'));
        expect(
          buyer.message,
          contains(
            'https://app.sello.test/d/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        );
        expect(buyer.toJson().containsKey('sender_id'), isFalse);
      },
    );

    test(
      'records Text.lk success without creating an SMS share action',
      () async {
        final sms = _RecordingSmsSender();
        final dispatcher = OrderConfirmationDispatcher(
          gateway: _RecordingGateway(snapshot()),
          smsSender: sms,
          links: const DocumentLinkFactory(
            overrideOrigin: 'https://app.sello.test',
          ),
        );

        final outcome = await dispatcher.dispatch('order-1');

        expect(sms.providerPosts, greaterThan(0));
        expect(
          sms.requests.any(
            (r) => r.recipientKind == OutboundRecipientKind.customer,
          ),
          isTrue,
        );
        expect(
          outcome!.actions.every((a) => a.channel == OutboundChannel.whatsapp),
          isTrue,
        );
        expect(outcome.customerActions.first.launchUri, contains('wa.me'));
      },
    );

    test('Text.lk failure is recorded without failing dispatch', () async {
      final sms = _RecordingSmsSender(
        result: const OutboundSmsResult(OutboundSmsStatus.failed),
      );
      final dispatcher = OrderConfirmationDispatcher(
        gateway: _RecordingGateway(snapshot()),
        smsSender: sms,
      );

      final outcome = await dispatcher.dispatch('order-1');
      expect(outcome, isNotNull);
      expect(sms.providerPosts, greaterThan(0));
    });

    test('thrown SMS errors do not fail the order confirmation', () async {
      final sms = _RecordingSmsSender(throwError: true);
      final dispatcher = OrderConfirmationDispatcher(
        gateway: _RecordingGateway(snapshot()),
        smsSender: sms,
      );

      final outcome = await dispatcher.dispatch('order-1');
      expect(outcome, isNotNull);
      expect(outcome!.customerActions, isNotEmpty);
    });

    test('retry does not duplicate the SMS provider send', () async {
      final sms = _RecordingSmsSender();
      final dispatcher = OrderConfirmationDispatcher(
        gateway: _RecordingGateway(snapshot()),
        smsSender: sms,
        policies: OutboundNotificationPolicies.defaults.copyWith(
          whatsappEnabled: false,
        ),
      );

      await dispatcher.dispatch('order-1');
      final firstPosts = sms.providerPosts;
      await dispatcher.dispatch('order-1');

      expect(firstPosts, greaterThan(0));
      expect(sms.providerPosts, firstPosts);
      expect(
        sms.results.where((s) => s == OutboundSmsStatus.alreadySent),
        isNotEmpty,
      );
    });
  });

  group('CollectionAcknowledgementDispatcher SMS', () {
    CollectionAcknowledgementPrepareResult collection() {
      return CollectionAcknowledgementPrepareResult(
        alreadyPrepared: false,
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
        customer: const OrderConfirmationContact(
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

    test(
      'sends SMS for buyer and hub with receipt link; WhatsApp unchanged',
      () async {
        final sms = _RecordingSmsSender();
        final dispatcher = CollectionAcknowledgementDispatcher(
          prepare: (_) async => collection(),
          recordDispatch: _alwaysRecord,
          smsSender: sms,
          links: const DocumentLinkFactory(
            overrideOrigin: 'https://app.sello.test',
          ),
        );

        final outcome = await dispatcher.dispatch('pay-1');

        expect(
          sms.requests.any(
            (r) => r.recipientKind == OutboundRecipientKind.customer,
          ),
          isTrue,
        );
        expect(
          sms.requests.any((r) => r.recipientKind == OutboundRecipientKind.hub),
          isTrue,
        );
        expect(
          sms.requests
              .firstWhere(
                (r) => r.recipientKind == OutboundRecipientKind.customer,
              )
              .recipient,
          '94771111111',
        );
        expect(
          sms.requests
              .firstWhere(
                (r) => r.recipientKind == OutboundRecipientKind.customer,
              )
              .message,
          contains('/d/cccccccccccccccccccccccccccccccccccccccccccccccc'),
        );
        expect(outcome!.customerActions.first.launchUri, contains('wa.me'));
        expect(
          outcome.customerActions.first.launchUri,
          isNot(contains('sms:')),
        );
      },
    );

    test('collection SMS disabled → no Text.lk request', () async {
      final sms = _RecordingSmsSender();
      final dispatcher = CollectionAcknowledgementDispatcher(
        prepare: (_) async => collection(),
        recordDispatch: _alwaysRecord,
        smsSender: sms,
        policies: OutboundNotificationPolicies.defaults.copyWith(
          smsEnabled: false,
        ),
      );

      await dispatcher.dispatch('pay-1');
      expect(sms.requests, isEmpty);
    });
  });

  group('Test SMS', () {
    test('client payload has no token, Sender ID, or message body', () {
      final json = OutboundSmsTest.requestJson('94771234567');
      expect(json.keys, unorderedEquals(['purpose', 'recipient']));
      expect(json['purpose'], 'test');
      expect(json['recipient'], '94771234567');
      expect(json.containsKey('sender_id'), isFalse);
      expect(json.containsKey('message'), isFalse);
      expect(json.toString().toLowerCase(), isNot(contains('token')));
      expect(json.toString().toLowerCase(), isNot(contains('text.lk')));
    });

    test('blocks when SMS is off or Sender ID is missing', () {
      expect(
        OutboundSmsTest.tenantBlockReason(
          smsEnabled: false,
          senderId: 'AcmeCo',
        ),
        'Turn on SMS and save.',
      );
      expect(
        OutboundSmsTest.tenantBlockReason(smsEnabled: true, senderId: null),
        'SMS Sender ID is not configured yet.',
      );
      expect(
        OutboundSmsTest.tenantBlockReason(smsEnabled: true, senderId: 'AcmeCo'),
        isNull,
      );
    });

    test('does not call Text.lk when the number is invalid', () async {
      final sms = _RecordingSmsSender();
      final recipient = MessagingPhone.international('12');
      expect(recipient, isNull);
      expect(sms.testRecipients, isEmpty);
      expect(sms.providerPosts, 0);
    });

    test(
      'uses the same Edge Function path as order SMS, without a Sender ID',
      () async {
        final sms = _RecordingSmsSender();
        final recipient = MessagingPhone.international('0771234567');
        expect(recipient, '94771234567');
        final result = await sms.sendTest(recipient: recipient!);
        expect(result.didSend, isTrue);
        expect(sms.testRecipients, ['94771234567']);
        expect(sms.requests, isEmpty);
        expect(
          OutboundSmsTest.requestJson(recipient).containsKey('sender_id'),
          isFalse,
        );
      },
    );

    test('reports Text.lk success and failure without a second path', () {
      expect(
        OutboundSmsTest.feedback(
          const OutboundSmsResult(OutboundSmsStatus.sent),
        ),
        'Test SMS sent.',
      );
      expect(
        OutboundSmsTest.feedback(
          const OutboundSmsResult(
            OutboundSmsStatus.skippedMissingSender,
            reason: 'missing_sender_id',
          ),
        ),
        'SMS Sender ID is not configured yet.',
      );
      expect(
        OutboundSmsTest.feedback(
          const OutboundSmsResult(
            OutboundSmsStatus.failed,
            reason: 'provider_error',
          ),
        ),
        'The SMS provider did not accept the message. Check the Sender ID.',
      );
      expect(
        OutboundSmsTest.feedback(
          const OutboundSmsResult(
            OutboundSmsStatus.failed,
            reason: 'claim_failed',
          ),
        ),
        contains('migration 049'),
      );
    });

    test('ignores a second send while a request is in progress', () async {
      final sender = _LatchSmsSender();
      var sending = false;
      Future<void> send() async {
        if (sending) return;
        sending = true;
        try {
          await sender.sendTest(recipient: '94771234567');
        } finally {
          sending = false;
        }
      }

      final first = send();
      await send();
      expect(sender.sendTestCalls, 1);
      sender.completer.complete(
        const OutboundSmsResult(OutboundSmsStatus.sent),
      );
      await first;
      expect(sender.sendTestCalls, 1);
    });
  });

  group('onboarding Sender ID verification', () {
    test('tenant-facing copy does not name the SMS provider', () {
      expect(OutboundSmsVerify.title, 'Set up SMS notifications');
      expect(OutboundSmsVerify.explanation.toLowerCase(), isNot(contains('text.lk')));
      expect(OutboundSmsVerify.rejectedMessage.toLowerCase(), isNot(contains('text.lk')));
      expect(
        OutboundSmsVerify.explanation,
        contains('Sender ID registered for your business'),
      );
    });

    test('Sender ID can be entered during onboarding', () {
      expect(SmsSenderId.tryParse('AcmeCo'), 'AcmeCo');
      final json = OutboundSmsVerify.requestJson(
        recipient: '94765644465',
        senderId: 'AcmeCo',
      );
      expect(json['purpose'], 'verify_sender');
      expect(json['sender_id'], 'AcmeCo');
      expect(json['recipient'], '94765644465');
    });

    test('valid Sender ID plus successful Text.lk test is saved', () async {
      final sms = _RecordingSmsSender(
        result: const OutboundSmsResult(
          OutboundSmsStatus.sent,
          activated: true,
        ),
      );
      final recipient = MessagingPhone.international('0765644465');
      expect(recipient, '94765644465');
      final result = await sms.verifySender(
        recipient: recipient!,
        senderId: 'AcmeCo',
      );
      expect(result.senderActivated, isTrue);
      expect(sms.verifyCalls, [
        ('94765644465', 'AcmeCo'),
      ]);
      expect(
        OutboundSmsVerify.feedback(result),
        OutboundSmsVerify.successBody,
      );
    });

    test('rejected Sender ID is not saved', () async {
      final sms = _RecordingSmsSender(
        result: const OutboundSmsResult(
          OutboundSmsStatus.failed,
          reason: 'sender_id_rejected',
        ),
      );
      final result = await sms.verifySender(
        recipient: '94765644465',
        senderId: 'FakeId',
      );
      expect(result.senderActivated, isFalse);
      expect(result.didSend, isFalse);
      expect(
        OutboundSmsVerify.feedback(result),
        OutboundSmsVerify.rejectedMessage,
      );
    });

    test('test phone number is validated before send', () {
      expect(
        OutboundSmsVerify.blockReason(senderId: 'AcmeCo', phone: '12'),
        'Enter a valid phone number.',
      );
      expect(
        OutboundSmsVerify.blockReason(senderId: 'AB', phone: '0765644465'),
        'Enter a valid Sender ID (3 to 11 letters or digits).',
      );
      expect(
        OutboundSmsVerify.blockReason(
          senderId: 'AcmeCo',
          phone: '0765644465',
        ),
        isNull,
      );
    });

    test('Text.lk token is never exposed to Flutter', () {
      final json = OutboundSmsVerify.requestJson(
        recipient: '94765644465',
        senderId: 'AcmeCo',
      );
      expect(json.containsKey('token'), isFalse);
      expect(json.containsKey('api_token'), isFalse);
      expect(json.containsKey('message'), isFalse);
      expect(json.toString().toLowerCase(), isNot(contains('token')));
      expect(json.toString().toLowerCase(), isNot(contains('text.lk')));
      expect(json.toString().toLowerCase(), isNot(contains('textlk')));
    });

    test('manually configured Sender IDs stay ready without overwrite', () {
      expect(
        OutboundSmsVerify.canActivateCandidate(
          storedSenderId: 'AcmeCo',
          editable: false,
          candidate: 'AcmeCo',
        ),
        isTrue,
      );
      expect(
        OutboundSmsVerify.canActivateCandidate(
          storedSenderId: 'AcmeCo',
          editable: false,
          candidate: 'HackedId',
        ),
        isFalse,
      );
      expect(
        OutboundSmsVerify.canActivateCandidate(
          storedSenderId: null,
          editable: false,
          candidate: 'AcmeCo',
        ),
        isTrue,
      );
    });

    test('Settings Test SMS still uses the saved Sender ID path', () {
      expect(
        OutboundSmsTest.requestJson('94765644465').containsKey('sender_id'),
        isFalse,
      );
    });
  });

  group('no hardcoded Sender ID', () {
    test('lib and Edge Function do not hardcode a Text.lk Sender ID', () {
      const banned = 'NamsonLanka';
      final hits = <String>[];
      for (final root in [Directory('lib'), Directory('supabase/functions')]) {
        if (!root.existsSync()) continue;
        for (final entity in root.listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!(entity.path.endsWith('.dart') ||
              entity.path.endsWith('.ts') ||
              entity.path.endsWith('.js'))) {
            continue;
          }
          if (entity.readAsStringSync().contains(banned)) {
            hits.add(entity.path);
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });

    test('Flutter never contains the Text.lk API token', () {
      final hits = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('TEXTLK_API_TOKEN') ||
            text.contains('textlk_api_token')) {
          hits.add(entity.path);
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });
  });
}

Future<bool> _alwaysRecord({
  required String eventId,
  required OutboundChannel channel,
  required OutboundRecipientKind recipientKind,
  required String recipientKey,
  String? address,
  OutboundDispatchStatus status = OutboundDispatchStatus.prepared,
  String? skipReason,
}) async => true;

class _RecordingSmsSender implements OutboundSmsSender {
  _RecordingSmsSender({
    this.result = const OutboundSmsResult(OutboundSmsStatus.sent),
    this.throwError = false,
  });

  final OutboundSmsResult result;
  final bool throwError;
  final List<OutboundSmsRequest> requests = [];
  final List<String> testRecipients = [];
  final List<(String recipient, String senderId)> verifyCalls = [];
  final List<OutboundSmsStatus> results = [];
  final Set<String> _claimed = {};
  int providerPosts = 0;

  @override
  Future<OutboundSmsResult> send(OutboundSmsRequest request) async {
    if (throwError) {
      throw StateError('Text.lk unreachable');
    }
    requests.add(request);
    final key =
        '${request.eventId}|${request.recipientKind.dbValue}|${request.recipientKey}';
    if (_claimed.contains(key)) {
      results.add(OutboundSmsStatus.alreadySent);
      return const OutboundSmsResult(OutboundSmsStatus.alreadySent);
    }
    if (result.status == OutboundSmsStatus.sent ||
        result.status == OutboundSmsStatus.failed) {
      _claimed.add(key);
      providerPosts++;
    }
    results.add(result.status);
    return result;
  }

  @override
  Future<OutboundSmsResult> sendTest({required String recipient}) async {
    if (throwError) {
      throw StateError('Text.lk unreachable');
    }
    testRecipients.add(recipient);
    if (result.status == OutboundSmsStatus.sent ||
        result.status == OutboundSmsStatus.failed) {
      providerPosts++;
    }
    results.add(result.status);
    return result;
  }

  @override
  Future<OutboundSmsResult> verifySender({
    required String recipient,
    required String senderId,
  }) async {
    if (throwError) {
      throw StateError('Text.lk unreachable');
    }
    verifyCalls.add((recipient, senderId));
    if (result.status == OutboundSmsStatus.sent ||
        result.status == OutboundSmsStatus.failed) {
      providerPosts++;
    }
    results.add(result.status);
    return result;
  }
}

class _LatchSmsSender implements OutboundSmsSender {
  final completer = Completer<OutboundSmsResult>();
  var sendTestCalls = 0;

  @override
  Future<OutboundSmsResult> send(OutboundSmsRequest request) async {
    return const OutboundSmsResult(OutboundSmsStatus.failed);
  }

  @override
  Future<OutboundSmsResult> sendTest({required String recipient}) {
    sendTestCalls++;
    return completer.future;
  }

  @override
  Future<OutboundSmsResult> verifySender({
    required String recipient,
    required String senderId,
  }) {
    return completer.future;
  }
}

class _RecordingGateway implements OrderConfirmationGateway {
  _RecordingGateway(this.prepared);

  final OrderConfirmationPrepareResult prepared;
  final List<Map<String, Object?>> records = [];

  @override
  Future<OrderConfirmationPrepareResult> prepare(String orderId) async =>
      prepared;

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
    records.add({
      'channel': channel,
      'status': status,
      'skipReason': skipReason,
      'kind': recipientKind,
      'key': recipientKey,
    });
    return true;
  }
}

Map<String, dynamic> _settingsRow([Map<String, dynamic> extras = const {}]) {
  return {
    'id': 'settings-1',
    'company_id': 'company-1',
    'currency': 'USD',
    ...extras,
  };
}
