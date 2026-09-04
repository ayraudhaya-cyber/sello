import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/hub/settings/presentation/widgets/settings_chrome.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/outbound_message_template.dart';
import 'package:sello/services/notifications/outbound/outbound_placeholders.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Company-scoped outbound messaging (automatic SMS + WhatsApp share intents).
///
/// Lives under Settings → Notifications. Personal inbox prefs stay separate.
class OutboundMessagingSettingsCard extends ConsumerWidget {
  const OutboundMessagingSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hubSettingsProvider);
    final draft = state.effective;
    final policies = draft.outboundNotificationPolicies;
    final canEditSenderId =
        ref
            .watch(permissionServiceProvider)
            ?.canEditSmsSenderId(draft.smsSenderIdEditable) ??
        false;
    final canSendTest =
        ref.watch(permissionServiceProvider)?.canSendTestSms ?? false;
    final saved = state.settings ?? draft;
    final testBlockReason = OutboundSmsTest.tenantBlockReason(
      smsEnabled: saved.outboundNotificationPolicies.smsEnabled,
      senderId: saved.smsSenderId,
    );

    return SettingsGroupCard(
      title: 'Customer & team messaging',
      description:
          'Choose what gets sent, to whom, and through which channel. '
          'SMS is sent automatically. WhatsApp still opens on the device '
          'with a prefilled message. Owner / Manager also receive the in-app '
          'inbox when an order is completed or a collection is submitted.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSubgroup(
            title: 'Channels',
            child: SettingsTwoUp(
              children: [
                SelloStatusToggle(
                  value: policies.whatsappEnabled,
                  label: 'WhatsApp',
                  helper:
                      'Opens WhatsApp with a prefilled confirmation or acknowledgement.',
                  onChanged: (value) => ref
                      .read(hubSettingsProvider.notifier)
                      .patchDraft(
                        (c) => c.copyWith(
                          outboundNotificationPolicies: policies.copyWith(
                            whatsappEnabled: value,
                          ),
                        ),
                      ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelloStatusToggle(
                      value: policies.smsEnabled,
                      label: 'SMS',
                      helper: 'Sent automatically when a message is enabled.',
                      onChanged: (value) => ref
                          .read(hubSettingsProvider.notifier)
                          .patchDraft(
                            (c) => c.copyWith(
                              outboundNotificationPolicies: policies.copyWith(
                                smsEnabled: value,
                              ),
                            ),
                          ),
                    ),
                    const SizedBox(height: 14),
                    SettingsCompactField(
                      label: 'SMS Sender ID',
                      helper: canEditSenderId
                          ? 'The name customers see when they receive SMS from '
                                'your business.'
                          : 'This Sender ID is managed by Sello.',
                      child: _SmsSenderIdField(
                        value: draft.smsSenderId,
                        isDirty: state.isDirty,
                        enabled: canEditSenderId,
                        onChanged: canEditSenderId
                            ? (normalized) {
                                ref
                                    .read(hubSettingsProvider.notifier)
                                    .patchDraft(
                                      (c) => c.copyWith(
                                        smsSenderId: normalized,
                                        clearSmsSenderId: normalized == null,
                                      ),
                                    );
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canSendTest) ...[
            const SizedBox(height: 22),
            SettingsSubgroup(
              title: 'Test SMS',
              helper: 'Sends a real SMS using the configured Sender ID.',
              child: _TestSmsSection(blockReason: testBlockReason),
            ),
          ],
          const SizedBox(height: 22),
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: 22),
          for (
            var i = 0;
            i < OutboundNotificationType.settingsOrder.length;
            i++
          ) ...[
            if (i > 0) ...[
              const SizedBox(height: 18),
              const Divider(height: 1, color: AppColors.outlinePanel),
              const SizedBox(height: 18),
            ],
            _MessageTypeEditor(
              type: OutboundNotificationType.settingsOrder[i],
              policies: policies,
              isDirty: state.isDirty,
              masterWhatsapp: policies.whatsappEnabled,
              masterSms: policies.smsEnabled,
              onChanged: (next) => ref
                  .read(hubSettingsProvider.notifier)
                  .patchDraft(
                    (c) => c.copyWith(outboundNotificationPolicies: next),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SmsSenderIdField extends StatefulWidget {
  const _SmsSenderIdField({
    required this.value,
    required this.isDirty,
    required this.enabled,
    this.onChanged,
  });

  final String? value;
  final bool isDirty;
  final bool enabled;
  final ValueChanged<String?>? onChanged;

  @override
  State<_SmsSenderIdField> createState() => _SmsSenderIdFieldState();
}

class _SmsSenderIdFieldState extends State<_SmsSenderIdField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(covariant _SmsSenderIdField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value ?? '';
    if (_controller.text == next) return;
    // Reset after Save/Discard, or whenever the field is locked so the
    // displayed value always matches server configuration.
    if (!widget.enabled || (oldWidget.isDirty && !widget.isDirty)) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelloTextField(
      controller: _controller,
      enabled: widget.enabled,
      hint: widget.enabled ? '3 to 11 letters or digits' : null,
      helperText: widget.enabled
          ? 'Must match the Sender ID registered for your business. 3 to 11 letters or digits.'
          : null,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        LengthLimitingTextInputFormatter(SmsSenderId.maxLength),
      ],
      suffixIcon: widget.enabled
          ? null
          : IconButton(
              icon: const Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
              tooltip: 'This Sender ID is managed by Sello.',
              onPressed: null,
            ),
      onChanged: widget.enabled && widget.onChanged != null
          ? (value) => widget.onChanged!(SmsSenderId.normalize(value))
          : null,
    );
  }
}

class _TestSmsSection extends ConsumerStatefulWidget {
  const _TestSmsSection({this.blockReason});

  final String? blockReason;

  @override
  ConsumerState<_TestSmsSection> createState() => _TestSmsSectionState();
}

class _TestSmsSectionState extends ConsumerState<_TestSmsSection> {
  final _phone = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final blocked = widget.blockReason;
    if (blocked != null) return;
    final recipient = MessagingPhone.international(_phone.text);
    if (recipient == null) {
      SelloSnackbars.error(context, 'Enter a valid phone number.');
      return;
    }

    setState(() => _sending = true);
    try {
      final result = await ref
          .read(outboundSmsSenderProvider)
          .sendTest(recipient: recipient);
      if (!mounted) return;
      final message = OutboundSmsTest.feedback(result);
      final succeeded =
          result.didSend || result.status == OutboundSmsStatus.alreadySent;
      if (succeeded) {
        SelloSnackbars.success(context, message);
      } else {
        SelloSnackbars.error(context, message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.blockReason;
    final canSend = blocked == null && !_sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCompactField(
          label: 'Phone number',
          helper: blocked ?? 'Sends a real SMS to this number.',
          child: SelloTextField(
            controller: _phone,
            hint: '0771234567',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            enabled: !_sending,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: SelloButton(
            label: 'Send test SMS',
            size: SelloButtonSize.small,
            loading: _sending,
            onPressed:
                canSend && MessagingPhone.international(_phone.text) != null
                ? _send
                : null,
          ),
        ),
      ],
    );
  }
}

class _MessageTypeEditor extends StatefulWidget {
  const _MessageTypeEditor({
    required this.type,
    required this.policies,
    required this.isDirty,
    required this.masterWhatsapp,
    required this.masterSms,
    required this.onChanged,
  });

  final OutboundNotificationType type;
  final OutboundNotificationPolicies policies;
  final bool isDirty;
  final bool masterWhatsapp;
  final bool masterSms;
  final ValueChanged<OutboundNotificationPolicies> onChanged;

  @override
  State<_MessageTypeEditor> createState() => _MessageTypeEditorState();
}

class _MessageTypeEditorState extends State<_MessageTypeEditor> {
  late final TextEditingController _controller;

  OutboundTypePolicy get _policy => widget.policies.policyFor(widget.type);

  String _sourceText() =>
      widget.policies.templateOverride(widget.type) ??
      OutboundMessageTemplate.defaultFor(widget.type);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _sourceText());
  }

  @override
  void didUpdateWidget(covariant _MessageTypeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isDirty && _controller.text != _sourceText()) {
      _controller.text = _sourceText();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _patchPolicy(OutboundTypePolicy next) {
    widget.onChanged(widget.policies.copyWithType(widget.type, next));
  }

  void _insertPlaceholder(OutboundPlaceholder field) {
    final insertion = field.insertion;
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, insertion);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    widget.onChanged(widget.policies.copyWithTemplate(widget.type, next));
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final preview = OutboundMessageTemplate.render(
      _controller.text,
      values: OutboundPlaceholders.previewValues(
        widget.type,
        includeDocumentLink: policy.includeDocumentLink,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.type.label} — ${widget.type.audienceLabel}',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.type.hint,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            height: 1.4,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        SettingsTwoUp(
          children: [
            SelloStatusToggle(
              value: policy.enabled,
              label: 'Send this message',
              helper: 'When off, this event does not prepare a message.',
              onChanged: (value) =>
                  _patchPolicy(policy.copyWith(enabled: value)),
            ),
            SelloStatusToggle(
              value: policy.includeDocumentLink,
              label: widget.type.isOrderFamily
                  ? 'Include invoice link'
                  : 'Include receipt link',
              helper:
                  'Adds a secure link so the recipient can open the document in a browser.',
              onChanged: (value) =>
                  _patchPolicy(policy.copyWith(includeDocumentLink: value)),
            ),
          ],
        ),
        if (policy.enabled) ...[
          const SizedBox(height: 14),
          Text(
            'Send to',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final target in _allowedRecipients(widget.type))
                FilterChip(
                  label: Text(
                    target.label,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: policy.sendsTo(target)
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  selected: policy.sendsTo(target),
                  showCheckmark: false,
                  selectedColor: AppColors.primary.withValues(alpha: 0.12),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: policy.sendsTo(target)
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : AppColors.outlinePanel,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  onSelected: (selected) {
                    final next = [...policy.recipients];
                    if (selected) {
                      if (!next.contains(target)) next.add(target);
                    } else {
                      next.remove(target);
                    }
                    if (next.isEmpty) return;
                    _patchPolicy(policy.copyWith(recipients: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          SettingsExpandable(
            title: 'Channels for this message',
            subtitle: 'Uses the company WhatsApp and SMS switches above.',
            child: SettingsTwoUp(
              children: [
                SelloStatusToggle(
                  value: policy.whatsapp && widget.masterWhatsapp,
                  label: 'WhatsApp',
                  helper: widget.masterWhatsapp
                      ? 'Uses the company WhatsApp channel.'
                      : 'Enable WhatsApp under Channels first.',
                  onChanged: widget.masterWhatsapp
                      ? (value) =>
                            _patchPolicy(policy.copyWith(whatsapp: value))
                      : (_) {},
                ),
                SelloStatusToggle(
                  value: policy.sms && widget.masterSms,
                  label: 'SMS',
                  helper: widget.masterSms
                      ? 'Sent automatically using the company SMS channel.'
                      : 'Enable SMS under Channels first.',
                  onChanged: widget.masterSms
                      ? (value) => _patchPolicy(policy.copyWith(sms: value))
                      : (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MessageAndPreviewPane(
            controller: _controller,
            placeholders: OutboundPlaceholders.forType(widget.type),
            previewText: preview,
            onInsertPlaceholder: _insertPlaceholder,
            onMessageChanged: (value) => widget.onChanged(
              widget.policies.copyWithTemplate(widget.type, value),
            ),
          ),
        ],
      ],
    );
  }

  List<OutboundRecipientTarget> _allowedRecipients(
    OutboundNotificationType type,
  ) {
    return switch (type) {
      OutboundNotificationType.orderConfirmation ||
      OutboundNotificationType.orderNotification =>
        OutboundRecipientTarget.values,
      OutboundNotificationType.collectionAcknowledgement ||
      OutboundNotificationType.collectionSubmitted => const [
        OutboundRecipientTarget.customer,
        OutboundRecipientTarget.hub,
      ],
      _ => const [
        OutboundRecipientTarget.customer,
        OutboundRecipientTarget.hub,
      ],
    };
  }
}

/// Message editor + live recipient preview — side-by-side on wide layouts.
class _MessageAndPreviewPane extends StatelessWidget {
  const _MessageAndPreviewPane({
    required this.controller,
    required this.placeholders,
    required this.previewText,
    required this.onInsertPlaceholder,
    required this.onMessageChanged,
  });

  final TextEditingController controller;
  final List<OutboundPlaceholder> placeholders;
  final String previewText;
  final ValueChanged<OutboundPlaceholder> onInsertPlaceholder;
  final ValueChanged<String> onMessageChanged;

  static const _sideBySideMinWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= _sideBySideMinWidth;
        final editor = _MessageEditorColumn(
          controller: controller,
          placeholders: placeholders,
          onInsertPlaceholder: onInsertPlaceholder,
          onMessageChanged: onMessageChanged,
          maxLines: sideBySide ? 10 : 6,
        );
        final preview = _MessagePreviewCard(
          text: previewText,
          compact: !sideBySide,
        );

        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 63, child: editor),
              const SizedBox(width: 16),
              Expanded(flex: 37, child: preview),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            editor,
            const SizedBox(height: 12),
            preview,
          ],
        );
      },
    );
  }
}

class _MessageEditorColumn extends StatelessWidget {
  const _MessageEditorColumn({
    required this.controller,
    required this.placeholders,
    required this.onInsertPlaceholder,
    required this.onMessageChanged,
    required this.maxLines,
  });

  final TextEditingController controller;
  final List<OutboundPlaceholder> placeholders;
  final ValueChanged<OutboundPlaceholder> onInsertPlaceholder;
  final ValueChanged<String> onMessageChanged;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Message',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final field in placeholders)
              ActionChip(
                label: Text(
                  field.label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => onInsertPlaceholder(field),
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.outlinePanel),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
        const SizedBox(height: 10),
        SelloTextField(
          controller: controller,
          maxLines: maxLines,
          hint: 'Write the message. Tap a field above to personalize it.',
          onChanged: onMessageChanged,
        ),
      ],
    );
  }
}

class _MessagePreviewCard extends StatelessWidget {
  const _MessagePreviewCard({
    required this.text,
    this.compact = false,
  });

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        14,
        compact ? 12 : 14,
        14,
        compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.veil,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Preview',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.outlinePanel),
                ),
                child: const Text(
                  'Read only',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'How the message will appear to the recipient',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11.5,
              height: 1.35,
              color: AppColors.textFaint,
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Text(
            text.isEmpty ? 'Nothing to preview yet.' : text,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: compact ? 12.5 : 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
