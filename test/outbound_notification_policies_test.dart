import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/services/notifications/outbound/outbound_placeholders.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';

void main() {
  group('OutboundNotificationPolicies', () {
    test('defaults enable the four V1 messages and disable invoice + receipt', () {
      const policies = OutboundNotificationPolicies.defaults;
      expect(
        policies.isActive(OutboundNotificationType.orderConfirmation),
        isTrue,
      );
      expect(
        policies.isActive(OutboundNotificationType.orderNotification),
        isTrue,
      );
      expect(
        policies.isActive(OutboundNotificationType.collectionAcknowledgement),
        isTrue,
      );
      expect(
        policies.isActive(OutboundNotificationType.collectionSubmitted),
        isTrue,
      );
      expect(policies.isActive(OutboundNotificationType.invoice), isFalse);
      expect(policies.isActive(OutboundNotificationType.receipt), isFalse);
      expect(
        policies
            .policyFor(OutboundNotificationType.orderConfirmation)
            .recipients,
        [OutboundRecipientTarget.customer],
      );
      expect(
        policies
            .policyFor(OutboundNotificationType.orderNotification)
            .recipients,
        [OutboundRecipientTarget.hub],
      );
      expect(
        policies
            .policyFor(OutboundNotificationType.collectionAcknowledgement)
            .recipients,
        [OutboundRecipientTarget.customer],
      );
      expect(
        policies
            .policyFor(OutboundNotificationType.collectionSubmitted)
            .recipients,
        [OutboundRecipientTarget.hub],
      );
    });

    test('fromJson merges unknown shapes onto defaults', () {
      final policies = OutboundNotificationPolicies.fromJson({
        'channels': {'whatsapp': false, 'sms': true},
        'types': {
          'order_confirmation': {
            'enabled': true,
            'recipients': ['customer'],
          },
        },
      });

      expect(policies.whatsappEnabled, isFalse);
      expect(policies.smsEnabled, isTrue);
      expect(
        policies
            .policyFor(OutboundNotificationType.orderConfirmation)
            .recipients,
        [OutboundRecipientTarget.customer],
      );
      expect(
        policies.isActive(OutboundNotificationType.orderConfirmation),
        isTrue,
      );
      expect(
        policies.channelWhatsapp(OutboundNotificationType.orderConfirmation),
        isFalse,
      );
    });

    test('fromJson splits legacy combined order + collection recipients', () {
      final policies = OutboundNotificationPolicies.fromJson({
        'channels': {'whatsapp': true, 'sms': true},
        'types': {
          'order_confirmation': {
            'enabled': true,
            'whatsapp': true,
            'sms': true,
            'include_document_link': true,
            'recipients': ['customer', 'hub'],
          },
          'collection_acknowledgement': {
            'enabled': true,
            'whatsapp': true,
            'sms': true,
            'include_document_link': true,
            'recipients': ['hub'],
          },
        },
      });

      expect(
        policies
            .policyFor(OutboundNotificationType.orderConfirmation)
            .recipients,
        [OutboundRecipientTarget.customer],
      );
      expect(
        policies
            .policyFor(OutboundNotificationType.orderNotification)
            .recipients,
        [OutboundRecipientTarget.hub],
      );
      expect(
        policies
            .policyFor(OutboundNotificationType.collectionAcknowledgement)
            .recipients,
        [OutboundRecipientTarget.customer],
      );
      expect(
        policies
            .policyFor(OutboundNotificationType.collectionSubmitted)
            .recipients,
        [OutboundRecipientTarget.hub],
      );
    });

    test('existing clients without custom templates keep Sello defaults', () {
      final policies = OutboundNotificationPolicies.fromJson(null);
      expect(policies, OutboundNotificationPolicies.defaults);
      expect(policies.templateOverride(OutboundNotificationType.orderConfirmation), isNull);
    });

    test('disabled type is not active', () {
      final policies = OutboundNotificationPolicies.defaults.copyWithType(
        OutboundNotificationType.orderConfirmation,
        OutboundNotificationPolicies.defaults
            .policyFor(OutboundNotificationType.orderConfirmation)
            .copyWith(enabled: false),
      );
      expect(
        policies.isActive(OutboundNotificationType.orderConfirmation),
        isFalse,
      );
      expect(
        policies.isActive(OutboundNotificationType.orderNotification),
        isTrue,
      );
    });
  });

  group('OutboundMessageTemplate', () {
    test('resolves buyer order placeholders including invoice link', () {
      final body = OutboundMessageTemplate.render(
        OutboundMessageTemplate.orderConfirmationDefault,
        values: {
          'business_name': 'Acme',
          'customer_name': 'City Mart',
          'order_number': 'SO-9',
          'order_total': 'Rs 12,500.00',
          'sales_rep_name': 'Amina',
          'invoice_link': 'https://app.sello.test/d/token',
        },
      );

      expect(body, contains('Acme'));
      expect(body, contains('City Mart'));
      expect(body, contains('SO-9'));
      expect(body, contains('Rs 12,500.00'));
      expect(body, contains('Amina'));
      expect(body, contains('View invoice: https://app.sello.test/d/token'));
      expect(body.toLowerCase(), isNot(contains('sku')));
    });

    test('legacy company_name / amount / document_link aliases still resolve', () {
      final body = OutboundMessageTemplate.render(
        '{{company_name}} total {{amount}} {{document_link}}',
        values: {
          'business_name': 'Acme',
          'order_total': 'Rs 10.00',
          'invoice_link': 'https://app.sello.test/d/x',
        },
      );
      expect(body, 'Acme total Rs 10.00 https://app.sello.test/d/x');
    });

    test('renders collection buyer acknowledgement without implying approval', () {
      final body = OutboundMessageTemplate.render(
        OutboundMessageTemplate.collectionAcknowledgementDefault,
        values: {
          'business_name': 'Acme',
          'customer_name': 'City Mart',
          'sales_rep_name': null,
          'collection_amount': 'Rs 25,000.00',
          'collection_number': 'PAY-9',
          'receipt_link': 'https://app.sello.test/d/token',
        },
      );

      expect(body, contains('Acme'));
      expect(body, contains('PAY-9'));
      expect(body, contains('pending owner/manager review'));
      expect(body, isNot(contains('Sales Rep:')));
      expect(body, contains('View receipt: https://app.sello.test/d/token'));
      expect(body.toLowerCase(), isNot(contains('approved')));
    });

    test('hub collection template says submitted for review', () {
      final body = OutboundMessageTemplate.render(
        OutboundMessageTemplate.collectionSubmittedDefault,
        values: {
          'business_name': 'Acme',
          'customer_name': 'City Mart',
          'collection_amount': 'Rs 25,000.00',
          'receipt_link': 'https://app.sello.test/d/token',
        },
      );
      expect(body, contains('Pending Review'));
      expect(body, contains('submitted'));
      expect(body.toLowerCase(), isNot(contains('approved')));
    });

    test('only exposes placeholders that belong to the message family', () {
      expect(
        OutboundPlaceholders.forType(OutboundNotificationType.orderConfirmation)
            .map((f) => f.token),
        containsAll(['customer_name', 'order_number', 'invoice_link']),
      );
      expect(
        OutboundPlaceholders.forType(
          OutboundNotificationType.collectionAcknowledgement,
        ).map((f) => f.token),
        containsAll(['collection_amount', 'receipt_link']),
      );
      expect(
        OutboundPlaceholders.forType(
          OutboundNotificationType.collectionAcknowledgement,
        ).map((f) => f.token),
        isNot(contains('order_number')),
      );
    });
  });
}
