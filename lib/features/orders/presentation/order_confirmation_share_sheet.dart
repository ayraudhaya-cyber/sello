import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// After a completed order: toast + optional WhatsApp prefill actions.
/// SMS is sent automatically on complete and does not appear here.
/// Use [showOrderInvoiceShareSheet] from Order View for WhatsApp + SMS.
Future<void> presentOrderConfirmation(
  BuildContext context,
  OrderConfirmationOutcome? outcome, {
  required bool completed,
}) async {
  if (!completed || !context.mounted) return;

  if (outcome == null) {
    SelloSnackbars.success(context, 'Order completed. Stock updated.');
    return;
  }

  if (outcome.customerWasSkipped && !outcome.hasShareActions) {
    SelloSnackbars.warning(
      context,
      outcome.customerSkippedReason ??
          'Order completed. No customer contact to send a confirmation.',
      title: 'Order completed',
    );
    return;
  }

  SelloSnackbars.success(
    context,
    outcome.hasShareActions
        ? 'Order ${outcome.orderNumber} completed. Send the confirmation.'
        : 'Order ${outcome.orderNumber} completed.',
  );

  if (!outcome.hasShareActions) return;
  if (!context.mounted) return;
  await showOrderConfirmationShareSheet(context, outcome);
}

/// Order View — View invoice / WhatsApp / SMS without the "completed" toast.
Future<void> showOrderInvoiceShareSheet(
  BuildContext context,
  OrderConfirmationOutcome outcome, {
  Future<void> Function(OrderConfirmationAction action)? onSendSms,
}) {
  return showOrderConfirmationShareSheet(
    context,
    outcome,
    title: 'Send invoice',
    description:
        'Open WhatsApp with a prefilled message, or send SMS to the customer. '
        'SMS uses your company Sender ID when configured.',
    copyLinkLabel: 'Copy invoice link',
    onSendSms: onSendSms,
  );
}

/// After a pending collection: toast + optional buyer / hub share intents.
Future<void> presentCollectionAcknowledgement(
  BuildContext context,
  OrderConfirmationOutcome? outcome,
) async {
  if (!context.mounted) return;

  if (outcome == null || !outcome.hasShareActions) {
    SelloSnackbars.success(context, 'Collection submitted for review.');
    return;
  }

  SelloSnackbars.success(
    context,
    'Collection submitted for review. Send the acknowledgement.',
  );
  if (!context.mounted) return;
  await showOrderConfirmationShareSheet(
    context,
    outcome,
    title: 'Send acknowledgement',
    description:
        'Share a short acknowledgement with a receipt link. '
        'Balances update only after owner/manager approval — not when this message is sent.',
    copyLinkLabel: 'Copy receipt link',
  );
}

Future<void> showOrderConfirmationShareSheet(
  BuildContext context,
  OrderConfirmationOutcome outcome, {
  String title = 'Send confirmation',
  String description =
      'Share a short confirmation with a link to view the order. '
      'SMS is sent automatically when enabled in Notifications.',
  String copyLinkLabel = 'Copy link',
  Future<void> Function(OrderConfirmationAction action)? onSendSms,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _OrderConfirmationShareDialog(
      outcome: outcome,
      title: title,
      description: description,
      copyLinkLabel: copyLinkLabel,
      onSendSms: onSendSms,
    ),
  );
}

class _OrderConfirmationShareDialog extends StatefulWidget {
  const _OrderConfirmationShareDialog({
    required this.outcome,
    required this.title,
    required this.description,
    required this.copyLinkLabel,
    this.onSendSms,
  });

  final OrderConfirmationOutcome outcome;
  final String title;
  final String description;
  final String copyLinkLabel;
  final Future<void> Function(OrderConfirmationAction action)? onSendSms;

  @override
  State<_OrderConfirmationShareDialog> createState() =>
      _OrderConfirmationShareDialogState();
}

class _OrderConfirmationShareDialogState
    extends State<_OrderConfirmationShareDialog> {
  String? _sendingSmsKey;

  Future<void> _launch(BuildContext context, String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) {
      SelloSnackbars.error(context, 'Unable to open that message.');
      return;
    }
    final ok = await launchUrl(parsed, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      SelloSnackbars.error(context, 'Unable to open that message.');
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    final url = widget.outcome.documentUrl.trim();
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    SelloSnackbars.success(context, 'Link copied.');
  }

  Future<void> _onSmsPressed(OrderConfirmationAction action) async {
    final handler = widget.onSendSms;
    if (handler == null) {
      SelloSnackbars.warning(
        context,
        'SMS sending is not available here.',
      );
      return;
    }
    setState(() => _sendingSmsKey = action.recipientKey);
    try {
      await handler(action);
    } finally {
      if (mounted) setState(() => _sendingSmsKey = null);
    }
  }

  Widget _actionButton(OrderConfirmationAction action) {
    final isSms = action.channel == OutboundChannel.sms;
    final busy = isSms && _sendingSmsKey == action.recipientKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelloButton(
        label: action.label,
        icon: isSms
            ? Icons.sms_outlined
            : Icons.chat_bubble_outline_rounded,
        variant: action.channel == OutboundChannel.whatsapp &&
                action.recipientKind == OutboundRecipientKind.customer
            ? SelloButtonVariant.primary
            : action.channel == OutboundChannel.whatsapp
                ? SelloButtonVariant.outline
                : SelloButtonVariant.secondary,
        expanded: true,
        loading: busy,
        onPressed: () {
          if (isSms) {
            _onSmsPressed(action);
          } else {
            _launch(context, action.launchUri);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    final customer = outcome.customerActions;
    final hub = outcome.hubActions;
    final salesRep = outcome.salesRepActions;
    final showCopy = outcome.documentUrl.trim().isNotEmpty &&
        outcome.includeDocumentLink;

    return AlertDialog(
      title: Text(widget.title),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            if (outcome.customerWasSkipped) ...[
              const SizedBox(height: 10),
              Text(
                outcome.customerSkippedReason!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
            if (customer.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _ShareGroupLabel('Customer'),
              const SizedBox(height: 8),
              for (final action in customer) _actionButton(action),
            ],
            if (hub.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _ShareGroupLabel('Owner / Manager'),
              const SizedBox(height: 8),
              for (final action in hub) _actionButton(action),
            ],
            if (salesRep.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _ShareGroupLabel('Sales representative'),
              const SizedBox(height: 8),
              for (final action in salesRep) _actionButton(action),
            ],
          ],
        ),
      ),
      actions: [
        if (showCopy)
          SelloButton(
            label: widget.copyLinkLabel,
            variant: SelloButtonVariant.ghost,
            onPressed: () => _copyLink(context),
          ),
        SelloButton(
          label: 'Done',
          variant: SelloButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ShareGroupLabel extends StatelessWidget {
  const _ShareGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
      ),
    );
  }
}
