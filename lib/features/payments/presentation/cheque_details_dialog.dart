import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/features/payments/presentation/give_cheque_dialog.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Cheque instrument workspace — lifecycle actions for clearance management.
class ChequeDetailsDialog extends ConsumerStatefulWidget {
  const ChequeDetailsDialog({
    super.key,
    required this.cheque,
    required this.currencySymbol,
    this.canCollect = false,
    this.canManageClearance = false,
    this.onCollect,
    this.onApprove,
    this.onGive,
    this.onEditGiven,
    this.onRecallGiven,
    this.onReturnToCustomer,
    this.onDeposit,
    this.onClear,
    this.onBounce,
    this.onCancel,
    this.onEditDetails,
  });

  final ChequeSummary cheque;
  final String currencySymbol;
  final bool canCollect;
  final bool canManageClearance;
  final Future<String?> Function(CollectChequeInput input)? onCollect;
  final Future<String?> Function()? onApprove;
  final Future<String?> Function(GiveChequeInput input)? onGive;
  final Future<String?> Function(GiveChequeInput input)? onEditGiven;
  final Future<String?> Function()? onRecallGiven;
  final Future<String?> Function(String? reason)? onReturnToCustomer;
  final Future<String?> Function()? onDeposit;
  final Future<String?> Function()? onClear;
  final Future<String?> Function(String? reason)? onBounce;
  final Future<String?> Function(String? reason)? onCancel;
  final VoidCallback? onEditDetails;

  @override
  ConsumerState<ChequeDetailsDialog> createState() =>
      _ChequeDetailsDialogState();
}

class _ChequeDetailsDialogState extends ConsumerState<ChequeDetailsDialog> {
  bool _busy = false;
  String? _photoUrl;
  late ChequeSummary _cheque;
  PaymentDetail? _relatedPayment;

  @override
  void initState() {
    super.initState();
    _cheque = widget.cheque;
    Future.microtask(_loadExtras);
  }

  @override
  void didUpdateWidget(covariant ChequeDetailsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cheque.id != widget.cheque.id ||
        oldWidget.cheque.updatedKey != widget.cheque.updatedKey) {
      _cheque = widget.cheque;
      Future.microtask(_loadExtras);
    }
  }

  Future<void> _loadExtras() async {
    await Future.wait([_loadPhoto(), _loadRelatedPayment()]);
  }

  Future<void> _loadRelatedPayment() async {
    final paymentId = _cheque.paymentId;
    if (paymentId == null || paymentId.isEmpty) {
      if (mounted) setState(() => _relatedPayment = null);
      return;
    }
    try {
      final detail = await ref
          .read(paymentRepositoryProvider)
          .fetchById(paymentId);
      if (!mounted) return;
      setState(() => _relatedPayment = detail);
    } catch (_) {
      if (mounted) setState(() => _relatedPayment = null);
    }
  }

  Future<void> _loadPhoto() async {
    final path = _cheque.photoPath;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _photoUrl = null);
      return;
    }
    final url = await ref.read(chequeRepositoryProvider).signChequePhoto(path);
    if (!mounted) return;
    setState(() => _photoUrl = url);
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final error = await action();
      if (!mounted) return;
      if (error != null) {
        SelloSnackbars.error(context, error);
        return;
      }
      Navigator.of(context).maybePop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmApprove() async {
    final action = widget.onApprove;
    if (action == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SelloFormDialog(
        title: 'Approve this cheque',
        subtitle:
            'This will reduce what the customer still owes. Do this only once.',
        maxWidth: 440,
        body: const SizedBox.shrink(),
        footer: SelloDialogFooter(
          cancelLabel: 'Cancel',
          cancelVariant: SelloButtonVariant.outline,
          onCancel: () => Navigator.of(context).pop(false),
          primaryLabel: 'Approve',
          onPrimary: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(action);
  }

  Future<void> _bounce() async {
    final historical = _cheque.isTrackingOnly;
    final result = await showDialog<_ReasonResult>(
      context: context,
      builder: (context) => _ReasonDialog(
        title: 'Bank returned this cheque?',
        subtitle: historical
            ? 'This is an old record. What the customer owes will not change.'
            : 'What the customer owes will go back up. The payment record stays.',
        confirmLabel: 'Bank returned it',
      ),
    );
    if (!mounted || result == null || !result.submitted) return;
    final action = widget.onBounce;
    if (action == null) return;
    await _run(() => action(result.reason));
  }

  Future<void> _cancelCheque() async {
    final result = await showDialog<_ReasonResult>(
      context: context,
      builder: (context) => const _ReasonDialog(
        title: 'Cancel this cheque?',
        subtitle:
            'If this cheque already reduced what the customer owes, that amount will be added back.',
        confirmLabel: 'Cancel cheque',
      ),
    );
    if (!mounted || result == null || !result.submitted) return;
    final action = widget.onCancel;
    if (action == null) return;
    await _run(() => action(result.reason));
  }

  Future<void> _collect() async {
    final action = widget.onCollect;
    if (action == null) return;

    var allocations = const <PaymentAllocationInput>[];
    if (!chequeCollectPreservesExistingAllocation(_cheque)) {
      try {
        final orders = await ref
            .read(paymentRepositoryProvider)
            .fetchReceivableOrders(_cheque.customerId);
        allocations = fifoChequeAllocations(
          amount: _cheque.amount,
          orders: orders,
        );
      } on AppFailure catch (failure) {
        if (!mounted) return;
        SelloSnackbars.error(context, failure.message);
        return;
      }
    }

    await _run(
      () => action(
        CollectChequeInput(
          chequeId: _cheque.id,
          collectionDate: DateTime.now(),
          allocations: allocations,
          photoPath: _cheque.photoPath,
          notes: _cheque.notes,
        ),
      ),
    );
  }

  Future<void> _editGiven() async {
    final action = widget.onEditGiven;
    if (action == null) return;
    final input = await showDialog<GiveChequeInput>(
      context: context,
      builder: (context) => GiveChequeDialog(cheque: _cheque, editing: true),
    );
    if (!mounted || input == null) return;
    await _run(() => action(input));
  }

  Future<void> _recallGiven() async {
    final action = widget.onRecallGiven;
    if (action == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SelloFormDialog(
        title: 'Bring this cheque back?',
        subtitle:
            'You have the paper again. What the customer owes does not change. '
            'You can take it to your bank, or give it to someone else.',
        maxWidth: 440,
        body: const SizedBox.shrink(),
        footer: SelloDialogFooter(
          cancelLabel: 'Back',
          cancelVariant: SelloButtonVariant.outline,
          onCancel: () => Navigator.of(context).pop(false),
          primaryLabel: 'I have it back',
          onPrimary: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(action);
  }

  Future<void> _returnToCustomer() async {
    final historical = _cheque.isTrackingOnly;
    final result = await showDialog<_ReasonResult>(
      context: context,
      builder: (context) => _ReasonDialog(
        title: 'Return this cheque to the customer?',
        subtitle: historical
            ? 'This is an old record. What the customer owes will not change.'
            : 'What the customer owes will go back up. The payment record stays.',
        confirmLabel: 'Return to customer',
      ),
    );
    if (!mounted || result == null || !result.submitted) return;
    final action = widget.onReturnToCustomer;
    if (action == null) return;
    await _run(() => action(result.reason));
  }

  Future<void> _give() async {
    final action = widget.onGive;
    if (action == null) return;
    final input = await showDialog<GiveChequeInput>(
      context: context,
      builder: (context) => GiveChequeDialog(cheque: _cheque),
    );
    if (!mounted || input == null) return;
    await _run(() => action(input));
  }

  Future<void> _runForward(ChequeForwardAction action) {
    return switch (action) {
      ChequeForwardAction.collect => _collect(),
      ChequeForwardAction.approve => _confirmApprove(),
      ChequeForwardAction.deposit => _run(widget.onDeposit ?? () async => null),
      ChequeForwardAction.clear => _run(widget.onClear ?? () async => null),
    };
  }

  ChequeRelatedDocuments _relatedDocuments() {
    final payment = _relatedPayment;
    if (payment == null) return const ChequeRelatedDocuments();
    return chequeRelatedDocuments(
      paymentNumber: payment.summary.paymentNumber,
      allocations: payment.allocations,
    );
  }

  Widget _field(String label, String value, {bool muted = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: muted ? AppColors.textFaint : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final dash = '—';
    final cheque = _cheque;
    final status = cheque.status;
    final related = _relatedDocuments();
    final next = chequeNextForwardAction(
      cheque: cheque,
      canCollect: widget.canCollect && widget.onCollect != null,
      canManageClearance: widget.canManageClearance,
    );
    final showBounce =
        chequeShowsBounce(
          cheque: cheque,
          canManageClearance: widget.canManageClearance,
        ) &&
        widget.onBounce != null;
    final showGivenFollowUp =
        chequeShowsGivenFollowUp(
          cheque: cheque,
          canManageClearance: widget.canManageClearance,
        ) &&
        widget.onRecallGiven != null;
    final showGive =
        chequeShowsGive(
          cheque: cheque,
          canManageClearance: widget.canManageClearance,
        ) &&
        widget.onGive != null;
    final showCancel =
        chequeShowsCancel(
          cheque: cheque,
          canCollect: widget.canCollect,
          canManageClearance: widget.canManageClearance,
        ) &&
        widget.onCancel != null;

    return SelloFormDialog(
      title: cheque.customerName ?? 'Customer cheque',
      subtitle: SelloFormatters.currency(
        cheque.amount,
        symbol: widget.currencySymbol,
      ),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 36,
        isMobile ? 12 : 16,
        isMobile ? 20 : 36,
        12,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: cheque.statusHelpText,
              child: SelloStatusBadge(
                label: cheque.displayLabel,
                tone: switch (status) {
                  ChequeStatus.awaitingCollection => SelloStatusTone.warning,
                  ChequeStatus.collected when cheque.isPendingApproval =>
                    SelloStatusTone.warning,
                  ChequeStatus.collected ||
                  ChequeStatus.deposited => SelloStatusTone.info,
                  ChequeStatus.given => SelloStatusTone.neutral,
                  ChequeStatus.returnedToCustomer => SelloStatusTone.warning,
                  ChequeStatus.cleared => SelloStatusTone.success,
                  ChequeStatus.bounced ||
                  ChequeStatus.cancelled => SelloStatusTone.danger,
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (cheque.isPendingApproval)
            const _ChequeNotice(
              text:
                  'You have this cheque. What the customer owes will change after '
                  'an owner or manager approves it.',
            )
          else if (cheque.isPendingClearance &&
              cheque.status == ChequeStatus.collected)
            const _ChequeNotice(
              text:
                  'What the customer owes already includes this cheque. Take it '
                  'to your bank, or give it to someone else. Neither takes more '
                  'money from the customer.',
            )
          else if (status == ChequeStatus.given)
            _ChequeNotice(
              text: cheque.givenToName == null
                  ? 'You gave this cheque to someone else. Bring it back if you have the paper again, or return it to the customer if they should owe this amount.'
                  : 'You gave this cheque to ${cheque.givenToName}. Bring it back if you have the paper again, or return it to the customer if they should owe this amount.',
            )
          else if (status == ChequeStatus.returnedToCustomer)
            const _ChequeNotice(
              text:
                  'This cheque was given back to the customer. What they owe includes this amount again.',
            )
          else if (status == ChequeStatus.deposited)
            const _ChequeNotice(
              text:
                  'This cheque is at your bank. Waiting for the bank to pay it. '
                  'What the customer owes does not change.',
            )
          else if (status == ChequeStatus.awaitingCollection)
            const _ChequeNotice(
              text:
                  'We do not have this cheque yet. What the customer owes does not '
                  'change until you receive it.',
            )
          else if (cheque.isTrackingOnly)
            const _ChequeNotice(
              text:
                  'This is an old cheque record. It does not change what the customer owes.',
            ),
          const SizedBox(height: 20),
          SelloDialogSection(
            title: 'Cheque',
            bottomSpacing: 20,
            children: [
              SelloFormRow(
                left: _field('Bank', cheque.bankName),
                right: _field('Cheque number', cheque.chequeNumber),
              ),
              const SizedBox(height: 14),
              SelloFormRow(
                left: _field('Holder', cheque.holderName),
                right: _field(
                  'Cheque date',
                  SelloFormatters.date(cheque.chequeDate),
                ),
              ),
              if (cheque.givenToName != null) ...[
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _field('Given to', cheque.givenToName!),
                  right: _field(
                    'Date given',
                    cheque.givenOn == null
                        ? dash
                        : SelloFormatters.date(cheque.givenOn),
                    muted: cheque.givenOn == null,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SelloFormRow(
                left: _field(
                  'Date received',
                  cheque.collectionDate == null
                      ? dash
                      : SelloFormatters.date(cheque.collectionDate),
                  muted: cheque.collectionDate == null,
                ),
                right: _field(
                  'Phone',
                  cheque.customerPhone ?? dash,
                  muted: cheque.customerPhone == null,
                ),
              ),
            ],
          ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 14),
            _RelatedDocumentsBlock(documents: related),
          ],
          if (cheque.appliedArAmount > 0 || cheque.appliedWalletAmount > 0)
            SelloDialogSection(
              title: 'Allocation',
              bottomSpacing: 20,
              children: [
                SelloFormRow(
                  left: _field(
                    'Against receivables',
                    SelloFormatters.currency(
                      cheque.appliedArAmount,
                      symbol: widget.currencySymbol,
                    ),
                  ),
                  right: _field(
                    'Wallet credit',
                    SelloFormatters.currency(
                      cheque.appliedWalletAmount,
                      symbol: widget.currencySymbol,
                    ),
                  ),
                ),
              ],
            ),
          if (_photoUrl != null)
            SelloDialogSection(
              title: 'Photo',
              bottomSpacing: 16,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(
                    _photoUrl!,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Text('Unable to load photo'),
                  ),
                ),
              ],
            ),
          if (cheque.givenNote != null)
            SelloDialogSection(
              title: 'Note when given',
              bottomSpacing: 16,
              children: [
                Text(
                  cheque.givenNote!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          if (cheque.notes != null)
            SelloDialogSection(
              title: 'Notes',
              bottomSpacing: 16,
              children: [
                Text(
                  cheque.notes!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          if (cheque.bounceReason != null ||
              cheque.cancelReason != null ||
              cheque.returnReason != null)
            SelloDialogSection(
              title: 'Reason',
              bottomSpacing: 16,
              children: [
                _field(
                  cheque.returnReason != null
                      ? 'Why it was returned to the customer'
                      : cheque.bounceReason != null
                      ? 'Why the bank returned it'
                      : 'Why it was cancelled',
                  cheque.returnReason ??
                      cheque.bounceReason ??
                      cheque.cancelReason ??
                      dash,
                ),
              ],
            ),
          SelloDialogSection(
            title: 'Activity',
            bottomSpacing: 8,
            children: [
              SelloFormRow(
                left: _field(
                  'Recorded by',
                  cheque.employeeName ?? dash,
                  muted: cheque.employeeName == null,
                ),
                right: _field(
                  'Created',
                  SelloFormatters.date(cheque.createdAt),
                ),
              ),
              const SizedBox(height: 12),
              EntityActivityPanel(
                referenceType: 'cheque',
                referenceId: cheque.id,
                emptyMessage: 'Cheque activity will appear here.',
              ),
            ],
          ),
        ],
      ),
      footer: SelloButtonBar(
        children: [
          SelloButton(
            label: 'Close',
            variant: SelloButtonVariant.outline,
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          ),
          if (widget.onEditDetails != null)
            SelloButton(
              label: 'Edit details',
              variant: SelloButtonVariant.ghost,
              onPressed: _busy ? null : widget.onEditDetails,
            ),
          if (showBounce)
            SelloButton(
              label: 'Bank returned it',
              variant: SelloButtonVariant.outline,
              tooltip: chequeBounceActionHint,
              onPressed: _busy ? null : _bounce,
            ),
          if (showCancel)
            SelloButton(
              label: 'Cancel',
              variant: SelloButtonVariant.ghost,
              tooltip: chequeCancelActionHint,
              onPressed: _busy ? null : _cancelCheque,
            ),
          if (showGivenFollowUp) ...[
            SelloButton(
              label: 'Edit who received it',
              variant: SelloButtonVariant.ghost,
              tooltip: chequeEditGivenHint,
              onPressed: _busy ? null : _editGiven,
            ),
            SelloButton(
              label: 'I have it back',
              variant: SelloButtonVariant.outline,
              tooltip: chequeRecallGivenHint,
              onPressed: _busy ? null : _recallGiven,
            ),
            SelloButton(
              label: 'Return to customer',
              variant: SelloButtonVariant.outline,
              tooltip: chequeReturnToCustomerHint,
              onPressed: _busy ? null : _returnToCustomer,
            ),
          ],
          if (showGive)
            SelloButton(
              label: 'Give to someone',
              variant: SelloButtonVariant.outline,
              tooltip: chequeGiveActionHint,
              onPressed: _busy ? null : _give,
            ),
          if (next != null)
            SelloButton(
              label: _busy ? 'Working…' : chequeForwardActionLabel(next),
              tooltip: chequeForwardActionHint(next),
              onPressed: _busy ? null : () => _runForward(next),
            ),
        ],
      ),
    );
  }
}

class _ReasonResult {
  const _ReasonResult({required this.submitted, this.reason});

  final bool submitted;
  final String? reason;
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  final String title;
  final String subtitle;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      maxWidth: 480,
      body: SelloTextField(
        controller: _controller,
        label: 'Reason',
        hint: 'Optional note for the audit trail',
        maxLines: 3,
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Back',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: () =>
            Navigator.of(context).pop(const _ReasonResult(submitted: false)),
        primaryLabel: widget.confirmLabel,
        onPrimary: () => Navigator.of(context).pop(
          _ReasonResult(
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

class _RelatedDocumentsBlock extends StatelessWidget {
  const _RelatedDocumentsBlock({required this.documents});

  final ChequeRelatedDocuments documents;

  @override
  Widget build(BuildContext context) {
    return SelloDialogSection(
      title: 'Related',
      bottomSpacing: 20,
      children: [
        if (documents.orderNumbers.isNotEmpty)
          _RelatedField(
            label: documents.orderNumbers.length > 1
                ? 'Related orders'
                : 'Related order',
            value: documents.orderNumbers.join('\n'),
          ),
        if (documents.paymentNumber != null) ...[
          if (documents.orderNumbers.isNotEmpty) const SizedBox(height: 14),
          _RelatedField(label: 'Payment', value: documents.paymentNumber!),
        ],
      ],
    );
  }
}

class _RelatedField extends StatelessWidget {
  const _RelatedField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ChequeNotice extends StatelessWidget {
  const _ChequeNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          height: 1.4,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
