import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// After a completed order: toast + optional WhatsApp prefill actions.
/// SMS is sent automatically and does not appear here.
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
      'Share a short confirmation with a link to view the order.',
  String copyLinkLabel = 'Copy link',
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _OrderConfirmationShareDialog(
      outcome: outcome,
      title: title,
      description: description,
      copyLinkLabel: copyLinkLabel,
    ),
  );
}

class _OrderConfirmationShareDialog extends StatelessWidget {
  const _OrderConfirmationShareDialog({
    required this.outcome,
    required this.title,
    required this.description,
    required this.copyLinkLabel,
  });

  final OrderConfirmationOutcome outcome;
  final String title;
  final String description;
  final String copyLinkLabel;

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
    await Clipboard.setData(ClipboardData(text: outcome.documentUrl));
    if (!context.mounted) return;
    SelloSnackbars.success(context, 'Link copied.');
  }

  @override
  Widget build(BuildContext context) {
    final customer = outcome.customerActions;
    final hub = outcome.hubActions;
    final salesRep = outcome.salesRepActions;

    return AlertDialog(
      title: Text(title),
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
              description,
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
              for (final action in customer)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelloButton(
                    label: action.label,
                    icon: action.channel == OutboundChannel.whatsapp
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.sms_outlined,
                    variant: action.channel == OutboundChannel.whatsapp
                        ? SelloButtonVariant.primary
                        : SelloButtonVariant.secondary,
                    expanded: true,
                    onPressed: () => _launch(context, action.launchUri),
                  ),
                ),
            ],
            if (hub.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _ShareGroupLabel('Owner / Manager'),
              const SizedBox(height: 8),
              for (final action in hub)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelloButton(
                    label: action.label,
                    icon: action.channel == OutboundChannel.whatsapp
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.sms_outlined,
                    variant: SelloButtonVariant.outline,
                    expanded: true,
                    onPressed: () => _launch(context, action.launchUri),
                  ),
                ),
            ],
            if (salesRep.isNotEmpty) ...[
              const SizedBox(height: 8),
              const _ShareGroupLabel('Sales representative'),
              const SizedBox(height: 8),
              for (final action in salesRep)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelloButton(
                    label: action.label,
                    icon: action.channel == OutboundChannel.whatsapp
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.sms_outlined,
                    variant: SelloButtonVariant.outline,
                    expanded: true,
                    onPressed: () => _launch(context, action.launchUri),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (outcome.documentUrl.trim().isNotEmpty)
          SelloButton(
            label: copyLinkLabel,
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
