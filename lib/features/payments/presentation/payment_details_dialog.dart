import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/badges/sello_badge.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';
import 'package:sello/shared/widgets/feedback/entity_activity_panel.dart';
import 'package:sello/shared/widgets/feedback/sello_intelligence_banner.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Financial Workspace — payment profile with allocations and customer context.
class PaymentDetailsDialog extends StatefulWidget {
  const PaymentDetailsDialog({
    super.key,
    required this.detail,
    required this.currencySymbol,
    this.canReview = false,
    this.onApprove,
    this.onReject,
  });

  final PaymentDetail detail;
  final String currencySymbol;
  final bool canReview;
  final Future<void> Function()? onApprove;
  final Future<void> Function(String? reason)? onReject;

  @override
  State<PaymentDetailsDialog> createState() => _PaymentDetailsDialogState();
}

class _PaymentDetailsDialogState extends State<PaymentDetailsDialog> {
  bool _busy = false;

  PaymentDetail get detail => widget.detail;
  PaymentSummary get payment => detail.summary;

  Future<void> _approve() async {
    final action = widget.onApprove;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final action = widget.onReject;
    if (action == null || _busy) return;

    final confirmed = await showDialog<_RejectResult>(
      context: context,
      builder: (context) => const _RejectReasonDialog(),
    );
    if (!mounted || confirmed == null || !confirmed.submitted) return;

    setState(() => _busy = true);
    try {
      await action(confirmed.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final dash = '—';
    final reviewing = widget.canReview && payment.status.isPendingReview;

    return SelloFormDialog(
      header: _Hero(payment: payment),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 36,
        isMobile ? 16 : 20,
        isMobile ? 20 : 36,
        16,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payment.status.isPendingReview)
            const SelloIntelligenceBanner(
              message:
                  'This collection is awaiting review. Customer balances update '
                  'only after approval.',
            )
          else
            const SelloIntelligenceBanner(
              message:
                  'Late-payment patterns, collection trends, and method mix '
                  'insights will appear here.',
            ),
          const SizedBox(height: _gap),
          _Section(
            label: 'Payment',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Amount',
                    value: SelloFormatters.currency(
                      payment.amount,
                      symbol: widget.currencySymbol,
                    ),
                  ),
                  right: _Field(label: 'Method', value: payment.method.label),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _Field(
                    label: 'Reference',
                    value: payment.reference ?? dash,
                    mutedEmpty: payment.reference == null,
                  ),
                  right: _Field(
                    label: 'Submitted',
                    value: SelloFormatters.date(payment.receivedAt),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          _Section(
            label: 'Customer',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Name',
                    value: payment.customerName ?? dash,
                    mutedEmpty: payment.customerName == null,
                  ),
                  right: _Field(
                    label: 'Phone',
                    value: payment.customerPhone ?? dash,
                    mutedEmpty: payment.customerPhone == null,
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _Field(
                    label: 'Outstanding',
                    value: SelloFormatters.currency(
                      detail.customerOutstanding ?? 0,
                      symbol: widget.currencySymbol,
                    ),
                  ),
                  right: _Field(
                    label: 'Wallet',
                    value: SelloFormatters.currency(
                      detail.customerWallet ?? 0,
                      symbol: widget.currencySymbol,
                    ),
                  ),
                ),
                if (detail.customerCreditAllowed != null) ...[
                  const SizedBox(height: 18),
                  SelloFormRow(
                    left: _Field(
                      label: 'Credit limit',
                      value: detail.customerCreditAllowed == true
                          ? SelloFormatters.currency(
                              detail.customerCreditLimit ?? 0,
                              symbol: widget.currencySymbol,
                            )
                          : 'Not allowed',
                      mutedEmpty: detail.customerCreditAllowed != true,
                    ),
                    right: _Field(
                      label: 'Available credit',
                      value: detail.customerCreditAllowed == true
                          ? SelloFormatters.currency(
                              ((detail.customerCreditLimit ?? 0) -
                                      (detail.customerOutstanding ?? 0))
                                  .clamp(0, double.infinity),
                              symbol: widget.currencySymbol,
                            )
                          : dash,
                      mutedEmpty: detail.customerCreditAllowed != true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: _gap),
          _Section(
            label: 'Allocated orders',
            child: detail.allocations.isEmpty
                ? Text(
                    payment.status.isPendingReview
                        ? 'No order allocations — amount will apply to customer balance / wallet on approval.'
                        : 'No order allocations — amount applied to customer balance / wallet.',
                    style: _Type.label.copyWith(color: AppColors.textFaint),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < detail.allocations.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                detail.allocations[i].orderNumber ??
                                    detail.allocations[i].orderId,
                                style: _Type.value,
                              ),
                            ),
                            Text(
                              SelloFormatters.currency(
                                detail.allocations[i].amount,
                                symbol: widget.currencySymbol,
                              ),
                              style: _Type.value,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          if (payment.notes != null) ...[
            const SizedBox(height: _gap),
            _Section(
              label: 'Notes',
              child: Text(
                payment.notes!,
                style: _Type.value.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (payment.status == PaymentRecordStatus.rejected &&
              (payment.rejectionReason != null ||
                  payment.reviewerName != null)) ...[
            const SizedBox(height: _gap),
            _Section(
              label: 'Review',
              child: Column(
                children: [
                  SelloFormRow(
                    left: _Field(
                      label: 'Rejected by',
                      value: payment.reviewerName ?? dash,
                      mutedEmpty: payment.reviewerName == null,
                    ),
                    right: _Field(
                      label: 'Rejected',
                      value: payment.reviewedAt == null
                          ? dash
                          : SelloFormatters.date(payment.reviewedAt),
                      mutedEmpty: payment.reviewedAt == null,
                    ),
                  ),
                  if (payment.rejectionReason != null) ...[
                    const SizedBox(height: 18),
                    _Field(label: 'Reason', value: payment.rejectionReason!),
                  ],
                ],
              ),
            ),
          ],
          if (payment.status == PaymentRecordStatus.completed &&
              payment.reviewedAt != null) ...[
            const SizedBox(height: _gap),
            _Section(
              label: 'Review',
              child: SelloFormRow(
                left: _Field(
                  label: 'Approved by',
                  value: payment.reviewerName ?? dash,
                  mutedEmpty: payment.reviewerName == null,
                ),
                right: _Field(
                  label: 'Approved',
                  value: SelloFormatters.date(payment.reviewedAt),
                ),
              ),
            ),
          ],
          const SizedBox(height: _gap),
          _Section(
            label: 'Activity',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Recorded by',
                    value: payment.employeeName ?? dash,
                    mutedEmpty: payment.employeeName == null,
                  ),
                  right: _Field(
                    label: payment.refundedAt != null ? 'Refunded' : 'Status',
                    value: payment.refundedAt != null
                        ? SelloFormatters.date(payment.refundedAt)
                        : payment.status.label,
                  ),
                ),
                const SizedBox(height: 14),
                EntityActivityPanel(
                  referenceType: 'payment',
                  referenceId: payment.id,
                  emptyMessage: 'Payment activity will appear here.',
                ),
              ],
            ),
          ),
        ],
      ),
      footer: reviewing
          ? Row(
              children: [
                SelloButton(
                  label: 'Reject',
                  variant: SelloButtonVariant.outline,
                  onPressed: _busy ? null : _reject,
                ),
                const Spacer(),
                SelloButton(
                  label: _busy ? 'Working…' : 'Approve collection',
                  onPressed: _busy ? null : _approve,
                ),
              ],
            )
          : SelloDialogFooter(
              cancelLabel: 'Close',
              cancelVariant: SelloButtonVariant.outline,
              onCancel: () => Navigator.of(context).maybePop(),
              primaryLabel: 'Done',
              onPrimary: () => Navigator.of(context).maybePop(),
            ),
    );
  }
}

const double _gap = 36;

class _RejectResult {
  const _RejectResult({required this.submitted, this.reason});

  final bool submitted;
  final String? reason;
}

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Reject collection',
      subtitle: 'Balances will not change. The record stays for audit.',
      maxWidth: 480,
      body: SelloTextField(
        controller: _controller,
        label: 'Reason',
        hint: 'Why is this collection being rejected?',
        maxLines: 3,
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: () =>
            Navigator.of(context).pop(const _RejectResult(submitted: false)),
        primaryLabel: 'Reject',
        onPrimary: () => Navigator.of(context).pop(
          _RejectResult(
            submitted: true,
            reason: _controller.text.trim().isEmpty
                ? null
                : _controller.text.trim(),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.payment});

  final PaymentSummary payment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(payment.paymentNumber, style: _Type.title),
        const SizedBox(height: 8),
        Text(
          [
            if (payment.customerName != null) payment.customerName!,
            payment.method.label,
          ].join(' · '),
          style: _Type.subtitle,
        ),
        const SizedBox(height: 14),
        SelloStatusBadge(
          label: payment.status.label,
          tone: switch (payment.status) {
            PaymentRecordStatus.completed => SelloStatusTone.success,
            PaymentRecordStatus.pending => SelloStatusTone.warning,
            PaymentRecordStatus.refunded => SelloStatusTone.info,
            PaymentRecordStatus.cancelled ||
            PaymentRecordStatus.rejected => SelloStatusTone.danger,
          },
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        const SizedBox(height: 14),
        Text(label.toUpperCase(), style: _Type.section),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.mutedEmpty = false,
  });

  final String label;
  final String value;
  final bool mutedEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _Type.label),
        const SizedBox(height: 6),
        Text(
          value,
          style: mutedEmpty
              ? _Type.value.copyWith(
                  color: AppColors.textFaint.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                )
              : _Type.value,
        ),
      ],
    );
  }
}

abstract final class _Type {
  static const title = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.45,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const section = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.08 * 11,
    height: 1.2,
    color: AppColors.textFaint,
  );

  static const label = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  static const value = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: AppColors.textPrimary,
  );
}
