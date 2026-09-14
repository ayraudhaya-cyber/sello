import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
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
    this.onDeposit,
    this.onClear,
    this.onBounce,
    this.onCancel,
  });

  final ChequeSummary cheque;
  final String currencySymbol;
  final bool canCollect;
  final bool canManageClearance;
  final Future<String?> Function(CollectChequeInput input)? onCollect;
  final Future<String?> Function()? onApprove;
  final Future<String?> Function()? onDeposit;
  final Future<String?> Function()? onClear;
  final Future<String?> Function(String? reason)? onBounce;
  final Future<String?> Function(String? reason)? onCancel;

  @override
  ConsumerState<ChequeDetailsDialog> createState() =>
      _ChequeDetailsDialogState();
}

class _ChequeDetailsDialogState extends ConsumerState<ChequeDetailsDialog> {
  bool _busy = false;
  String? _photoUrl;
  late ChequeSummary _cheque;

  @override
  void initState() {
    super.initState();
    _cheque = widget.cheque;
    Future.microtask(_loadPhoto);
  }

  @override
  void didUpdateWidget(covariant ChequeDetailsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cheque.id != widget.cheque.id ||
        oldWidget.cheque.updatedKey != widget.cheque.updatedKey) {
      _cheque = widget.cheque;
      Future.microtask(_loadPhoto);
    }
  }

  Future<void> _loadPhoto() async {
    final path = _cheque.photoPath;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _photoUrl = null);
      return;
    }
    final url =
        await ref.read(chequeRepositoryProvider).signChequePhoto(path);
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

  Future<void> _confirmSimple({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<String?> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SelloFormDialog(
        title: title,
        subtitle: message,
        maxWidth: 440,
        body: const SizedBox.shrink(),
        footer: SelloDialogFooter(
          cancelLabel: 'Cancel',
          cancelVariant: SelloButtonVariant.outline,
          onCancel: () => Navigator.of(context).pop(false),
          primaryLabel: confirmLabel,
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
        title: 'Bounce cheque',
        subtitle: historical
            ? 'This cheque was added as historical tracking. Sello never '
                'recorded a payment for it, so the customer balance will not '
                'change automatically.'
            : 'Outstanding balance is restored. The payment remains for audit.',
        confirmLabel: 'Bounce',
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
        title: 'Cancel cheque',
        subtitle: 'Cancels this instrument. Applied balances reverse if needed.',
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

    final input = await showDialog<CollectChequeInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CollectChequeSheet(
        cheque: _cheque,
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (!mounted || input == null) return;
    await _run(() => action(input));
  }

  Future<void> _approve() async {
    final action = widget.onApprove;
    if (action == null) return;
    await _confirmSimple(
      title: 'Approve collection',
      message:
          'Apply this cheque to the customer balance? Outstanding will decrease once.',
      confirmLabel: 'Approve',
      action: action,
    );
  }

  Future<void> _deposit() async {
    final action = widget.onDeposit;
    if (action == null) return;
    await _confirmSimple(
      title: 'Deposit cheque',
      message: 'Mark this cheque as deposited at the bank?',
      confirmLabel: 'Deposit',
      action: action,
    );
  }

  Future<void> _clear() async {
    final action = widget.onClear;
    if (action == null) return;
    await _confirmSimple(
      title: 'Clear cheque',
      message: 'Mark this cheque as cleared by the bank?',
      confirmLabel: 'Clear',
      action: action,
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
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14.5,
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

    final actions = <Widget>[];
    if (widget.canCollect &&
        status.canCollect &&
        widget.onCollect != null) {
      actions.add(
        SelloButton(
          label: _busy ? 'Working…' : 'Mark as collected',
          onPressed: _busy ? null : _collect,
        ),
      );
    }
    if (widget.canManageClearance &&
        cheque.canApproveCollection &&
        widget.onApprove != null) {
      actions.add(
        SelloButton(
          label: _busy ? 'Working…' : 'Approve collection',
          onPressed: _busy ? null : _approve,
        ),
      );
    }
    if (widget.canManageClearance &&
        cheque.canDeposit &&
        widget.onDeposit != null) {
      actions.add(
        SelloButton(
          label: _busy ? 'Working…' : 'Deposit',
          onPressed: _busy ? null : _deposit,
        ),
      );
    }
    if (widget.canManageClearance &&
        status.canClear &&
        widget.onClear != null) {
      actions.add(
        SelloButton(
          label: _busy ? 'Working…' : 'Clear',
          onPressed: _busy ? null : _clear,
        ),
      );
    }
    if (widget.canManageClearance &&
        cheque.canBounce &&
        widget.onBounce != null) {
      actions.add(
        SelloButton(
          label: 'Bounce',
          variant: SelloButtonVariant.outline,
          onPressed: _busy ? null : _bounce,
        ),
      );
    }
    if ((widget.canManageClearance ||
            (widget.canCollect && status == ChequeStatus.awaitingCollection)) &&
        status.canCancel &&
        widget.onCancel != null) {
      actions.add(
        SelloButton(
          label: 'Cancel',
          variant: SelloButtonVariant.ghost,
          onPressed: _busy ? null : _cancelCheque,
        ),
      );
    }

    return SelloFormDialog(
      title: cheque.chequeNumberLabel.isEmpty
          ? 'Cheque ${cheque.chequeNumber}'
          : cheque.chequeNumberLabel,
      subtitle: cheque.customerName ?? 'Customer cheque',
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
          Align(
            alignment: Alignment.centerLeft,
            child: SelloStatusBadge(
              label: cheque.displayLabel,
              tone: switch (status) {
                ChequeStatus.awaitingCollection => SelloStatusTone.warning,
                ChequeStatus.collected when cheque.isPendingApproval =>
                  SelloStatusTone.warning,
                ChequeStatus.collected ||
                ChequeStatus.deposited =>
                  SelloStatusTone.info,
                ChequeStatus.cleared => SelloStatusTone.success,
                ChequeStatus.bounced ||
                ChequeStatus.cancelled =>
                  SelloStatusTone.danger,
              },
            ),
          ),
          const SizedBox(height: 20),
          if (cheque.isPendingApproval)
            _ChequeNotice(
              text:
                  'Collected · Pending approval — outstanding is unchanged until '
                  'an Owner or Manager approves this collection.',
            )
          else if (cheque.isPendingClearance)
            _ChequeNotice(
              text:
                  'Collected · Pending clearance — outstanding already reflects '
                  'this cheque. Deposit and clear do not change the balance again.',
            )
          else if (status == ChequeStatus.awaitingCollection)
            _ChequeNotice(
              text:
                  'Awaiting collection — customer outstanding is unchanged until '
                  'this cheque is collected.',
            ),
          if (cheque.isPendingApproval ||
              cheque.isPendingClearance ||
              status == ChequeStatus.awaitingCollection)
            const SizedBox(height: 28)
          else
            const SizedBox(height: 20),
          SelloDialogSection(
            title: 'Cheque',
            children: [
              SelloFormRow(
                left: _field(
                  'Amount',
                  SelloFormatters.currency(
                    cheque.amount,
                    symbol: widget.currencySymbol,
                  ),
                ),
                right: _field('Bank', cheque.bankName),
              ),
              const SizedBox(height: 18),
              SelloFormRow(
                left: _field('Cheque number', cheque.chequeNumber),
                right: _field('Holder', cheque.holderName),
              ),
              const SizedBox(height: 18),
              SelloFormRow(
                left: _field(
                  'Cheque date',
                  SelloFormatters.date(cheque.chequeDate),
                ),
                right: _field(
                  'Collection date',
                  cheque.collectionDate == null
                      ? dash
                      : SelloFormatters.date(cheque.collectionDate),
                  muted: cheque.collectionDate == null,
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Customer',
            children: [
              SelloFormRow(
                left: _field(
                  'Name',
                  cheque.customerName ?? dash,
                  muted: cheque.customerName == null,
                ),
                right: _field(
                  'Phone',
                  cheque.customerPhone ?? dash,
                  muted: cheque.customerPhone == null,
                ),
              ),
            ],
          ),
          if (cheque.appliedArAmount > 0 || cheque.appliedWalletAmount > 0)
            SelloDialogSection(
              title: 'Applied',
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
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(
                    _photoUrl!,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Text('Unable to load photo'),
                  ),
                ),
              ],
            ),
          if (cheque.notes != null)
            SelloDialogSection(
              title: 'Notes',
              children: [
                Text(
                  cheque.notes!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          if (cheque.bounceReason != null || cheque.cancelReason != null)
            SelloDialogSection(
              title: 'Reason',
              children: [
                _field(
                  cheque.bounceReason != null ? 'Bounce reason' : 'Cancel reason',
                  cheque.bounceReason ?? cheque.cancelReason ?? dash,
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
              const SizedBox(height: 14),
              EntityActivityPanel(
                referenceType: 'cheque',
                referenceId: cheque.id,
                emptyMessage: 'Cheque activity will appear here.',
              ),
            ],
          ),
        ],
      ),
      footer: actions.isEmpty
          ? SelloDialogFooter(
              cancelLabel: 'Close',
              cancelVariant: SelloButtonVariant.outline,
              onCancel: () => Navigator.of(context).maybePop(),
              primaryLabel: 'Done',
              onPrimary: () => Navigator.of(context).maybePop(),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                SelloButton(
                  label: 'Close',
                  variant: SelloButtonVariant.outline,
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).maybePop(),
                ),
                ...actions,
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
        onCancel: () => Navigator.of(context).pop(
          const _ReasonResult(submitted: false),
        ),
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

class _CollectChequeSheet extends ConsumerStatefulWidget {
  const _CollectChequeSheet({
    required this.cheque,
    required this.currencySymbol,
  });

  final ChequeSummary cheque;
  final String currencySymbol;

  @override
  ConsumerState<_CollectChequeSheet> createState() =>
      _CollectChequeSheetState();
}

class _CollectChequeSheetState extends ConsumerState<_CollectChequeSheet> {
  DateTime _collectionDate = DateTime.now();
  final _notes = TextEditingController();
  List<ReceivableOrder> _receivables = const [];
  final Map<String, num> _allocations = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _collectionDate = widget.cheque.collectionDate ?? DateTime.now();
    if (widget.cheque.notes != null) {
      _notes.text = widget.cheque.notes!;
    }
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final orders = await ref
          .read(paymentRepositoryProvider)
          .fetchReceivableOrders(widget.cheque.customerId);
      if (!mounted) return;
      setState(() {
        _receivables = orders;
        _loading = false;
        var remaining = widget.cheque.amount;
        for (final order in orders) {
          if (remaining <= 0) break;
          final take = order.remaining.clamp(0, remaining);
          if (take > 0) {
            _allocations[order.id] = take;
            remaining -= take;
          }
        }
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      CollectChequeInput(
        chequeId: widget.cheque.id,
        collectionDate: _collectionDate,
        allocations: [
          for (final entry in _allocations.entries)
            if (entry.value > 0)
              PaymentAllocationInput(
                orderId: entry.key,
                amount: entry.value,
              ),
        ],
        photoPath: widget.cheque.photoPath,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Collect cheque',
      subtitle: 'Apply this cheque to outstanding orders and update balances.',
      maxWidth: kSelloFormDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 12),
          ],
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _collectionDate,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _collectionDate = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Collection date *',
                border: OutlineInputBorder(),
              ),
              child: Text(SelloFormatters.date(_collectionDate)),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_receivables.isNotEmpty) ...[
            Text(
              'Outstanding orders',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final order in _receivables) ...[
              Text(
                '${order.orderNumber} · due '
                '${SelloFormatters.currency(order.remaining, symbol: widget.currencySymbol)}'
                '${_allocations[order.id] != null ? ' · allocate ${SelloFormatters.currency(_allocations[order.id]!, symbol: widget.currencySymbol)}' : ''}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 12),
          ],
          SelloTextField(
            controller: _notes,
            label: 'Notes',
            maxLines: 2,
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: 'Collect',
        onPrimary: _confirm,
      ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13.5,
          height: 1.4,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
