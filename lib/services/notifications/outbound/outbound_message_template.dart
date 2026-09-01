import 'package:sello/shared/models/outbound_notification_policies.dart';

/// Renders outbound message templates with `{{placeholder}}` tokens.
///
/// Defaults live in code; tenants may override via
/// [OutboundNotificationPolicies.templates] without rebuilding the app.
///
/// Legacy tokens (`company_name`, `amount`, `document_link`) still resolve so
/// existing custom templates keep working.
abstract final class OutboundMessageTemplate {
  static const orderConfirmationDefault =
      '{{business_name}}\n'
      'Order {{order_number}} confirmed\n'
      '\n'
      'Hi {{customer_name}}, your order totalling {{order_total}} has been placed.'
      '{{#sales_rep_name}}\nSales Rep: {{sales_rep_name}}{{/sales_rep_name}}'
      '{{#invoice_link}}\n\nView invoice: {{invoice_link}}{{/invoice_link}}';

  static const orderNotificationDefault =
      '{{business_name}}\n'
      'New order {{order_number}}\n'
      '\n'
      'Customer: {{customer_name}}'
      '{{#sales_rep_name}}\nSales Rep: {{sales_rep_name}}{{/sales_rep_name}}\n'
      'Total: {{order_total}}'
      '{{#invoice_link}}\n\nView invoice: {{invoice_link}}{{/invoice_link}}';

  static const collectionAcknowledgementDefault =
      '{{business_name}}\n'
      'Collection {{collection_number}} received\n'
      '\n'
      'Hi {{customer_name}}, we recorded {{collection_amount}}.\n'
      'This is pending owner/manager review — your balance is not updated yet.'
      '{{#sales_rep_name}}\nSales Rep: {{sales_rep_name}}{{/sales_rep_name}}'
      '{{#receipt_link}}\n\nView receipt: {{receipt_link}}{{/receipt_link}}';

  static const collectionSubmittedDefault =
      '{{business_name}}\n'
      'Collection submitted for review\n'
      '\n'
      'Customer: {{customer_name}}'
      '{{#sales_rep_name}}\nSales Rep: {{sales_rep_name}}{{/sales_rep_name}}\n'
      'Amount: {{collection_amount}}\n'
      'Status: Pending Review\n'
      '\n'
      'Balances update only after owner/manager approval.'
      '{{#receipt_link}}\n\nView receipt: {{receipt_link}}{{/receipt_link}}';

  static const invoiceDefault =
      '{{business_name}}\n'
      'Invoice {{invoice_number}}\n'
      '\n'
      'Customer: {{customer_name}}\n'
      'Amount: {{order_total}}'
      '{{#invoice_link}}\n\nView invoice: {{invoice_link}}{{/invoice_link}}';

  static const receiptDefault =
      '{{business_name}}\n'
      'Payment receipt {{collection_number}}\n'
      '\n'
      'Customer: {{customer_name}}\n'
      'Amount: {{collection_amount}}'
      '{{#receipt_link}}\n\nView receipt: {{receipt_link}}{{/receipt_link}}';

  static String defaultFor(OutboundNotificationType type) => switch (type) {
        OutboundNotificationType.orderConfirmation => orderConfirmationDefault,
        OutboundNotificationType.orderNotification => orderNotificationDefault,
        OutboundNotificationType.collectionAcknowledgement =>
          collectionAcknowledgementDefault,
        OutboundNotificationType.collectionSubmitted =>
          collectionSubmittedDefault,
        OutboundNotificationType.invoice => invoiceDefault,
        OutboundNotificationType.receipt => receiptDefault,
      };

  static String render(
    String template, {
    required Map<String, String?> values,
  }) {
    final resolved = _withAliases(values);
    var output = template;

    // Optional blocks: {{#key}}...{{/key}} — kept when value is non-empty.
    final block = RegExp(r'\{\{#(\w+)\}\}(.*?)\{\{/\1\}\}', dotAll: true);
    output = output.replaceAllMapped(block, (match) {
      final key = match.group(1)!;
      final inner = match.group(2)!;
      final value = resolved[key]?.trim();
      if (value == null || value.isEmpty) return '';
      return inner.replaceAll('{{$key}}', value);
    });

    for (final entry in resolved.entries) {
      final value = entry.value ?? '';
      output = output.replaceAll('{{${entry.key}}}', value);
    }

    // Drop leftover unknown tokens.
    output = output.replaceAll(RegExp(r'\{\{/?\w+\}\}'), '');
    return output
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }

  /// Copies equivalent tokens so old and new placeholder names both work.
  static Map<String, String?> _withAliases(Map<String, String?> values) {
    final next = Map<String, String?>.from(values);
    void alias(String a, String b) {
      final av = next[a]?.trim();
      final bv = next[b]?.trim();
      if ((av == null || av.isEmpty) && bv != null && bv.isNotEmpty) {
        next[a] = bv;
      } else if ((bv == null || bv.isEmpty) && av != null && av.isNotEmpty) {
        next[b] = av;
      }
    }

    alias('business_name', 'company_name');
    alias('order_total', 'amount');
    alias('collection_amount', 'amount');
    alias('invoice_link', 'document_link');
    alias('receipt_link', 'document_link');
    alias('invoice_number', 'order_number');
    alias('collection_number', 'payment_number');
    return next;
  }
}
