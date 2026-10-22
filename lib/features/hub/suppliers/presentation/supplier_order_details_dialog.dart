import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/supplier_order.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class SupplierOrderDetailsDialog extends ConsumerStatefulWidget {
  const SupplierOrderDetailsDialog({
    required this.order,
    required this.currencySymbol,
  });

  final SupplierOrderSummary order;
  final String currencySymbol;

  @override
  ConsumerState<SupplierOrderDetailsDialog> createState() =>
      _SupplierOrderDetailsDialogState();
}

class _SupplierOrderDetailsDialogState
    extends ConsumerState<SupplierOrderDetailsDialog> {
  late SupplierOrderSummary _order;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _reload() async {
    final fresh = await ref
        .read(supplierOrderRepositoryProvider)
        .fetchById(_order.id);
    if (!mounted) return;
    setState(() => _order = fresh);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } on AppFailure catch (error) {
      if (!mounted) return;
      await showSelloNotice(
        context: context,
        title: 'Could not update this order',
        message: error.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    final lines = await showDialog<List<({String orderLineId, num quantity})>>(
      context: context,
      builder: (context) => _ReceiveDialog(
        order: _order,
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (lines == null || lines.isEmpty || !mounted) return;
    var number = '';
    await _run(() async {
      number = await ref.read(supplierOrderRepositoryProvider).receive(
        orderId: _order.id,
        lines: lines,
      );
    });
    if (!mounted || number.isEmpty) return;
    SelloSnackbars.success(context, '$number saved. Stock is updated.');
  }

  Future<void> _pay() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _PaymentDialog(order: _order),
    );
    if (saved != true || !mounted) return;
    SelloSnackbars.success(context, 'Payment recorded.');
    await _reload();
  }

  Future<void> _closeRemaining() async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Close what will not arrive?',
      message:
          'Units that have not been received stay off stock and off what you owe.',
      confirmLabel: 'Close remaining',
      cancelLabel: 'Keep open',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref
          .read(supplierOrderRepositoryProvider)
          .closeRemaining(_order.id),
    );
  }

  Future<void> _cancel() async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Cancel this order?',
      message: 'Nothing has been received, so stock and the balance stay as they are.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(supplierOrderRepositoryProvider).cancel(_order.id),
    );
  }

  Future<void> _clearCheque(SupplierPaymentSummary payment) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Cheque cleared?',
      message:
          '${payment.paymentNumber} will reduce what you owe ${ _order.supplierName}.',
      confirmLabel: 'Mark cleared',
      cancelLabel: 'Not yet',
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref
          .read(supplierOrderRepositoryProvider)
          .clearCheque(payment.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.currencySymbol;
    final order = _order;
    return SelloFormDialog(
      title: order.orderNumber,
      subtitle: order.supplierName,
      maxWidth: 760,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SelloStatusBadge(
                label: order.status.label,
                tone: switch (order.status) {
                  SupplierOrderStatus.received => SelloStatusTone.success,
                  SupplierOrderStatus.partiallyReceived =>
                    SelloStatusTone.warning,
                  SupplierOrderStatus.awaitingDelivery => SelloStatusTone.info,
                  SupplierOrderStatus.cancelled => SelloStatusTone.neutral,
                  SupplierOrderStatus.draft => SelloStatusTone.neutral,
                },
              ),
              const Spacer(),
              Text(
                SelloFormatters.currency(order.total, symbol: money),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You owe ${SelloFormatters.currency(order.stillOwed, symbol: money)}'
            '${order.paymentMethod == null ? '' : ' · ${order.paymentMethod!.label}'}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          for (final line in order.lines) ...[
            Text(
              line.title,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Ordered ${SelloFormatters.quantity(line.quantity)}'
              ' · Received ${SelloFormatters.quantity(line.receivedQuantity)}'
              '${line.cancelledQuantity > 0 ? ' · Closed ${SelloFormatters.quantity(line.cancelledQuantity)}' : ''}'
              ' · ${SelloFormatters.currency(line.unitCost, symbol: money)}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (order.receipts.isNotEmpty) ...[
            const Text(
              'Receipts',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final receipt in order.receipts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${receipt.receiptNumber} · ${SelloFormatters.date(receipt.receivedAt)} · ${SelloFormatters.currency(receipt.value, symbol: money)}',
                  style: const TextStyle(fontFamily: AppTypography.fontFamily),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (order.payments.isNotEmpty) ...[
            const Text(
              'Payments',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final payment in order.payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${payment.paymentNumber} · ${payment.method.label} · ${payment.statusLabel} · ${SelloFormatters.currency(payment.amount, symbol: money)}',
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                        ),
                      ),
                    ),
                    if (payment.isPendingCheque)
                      SelloButton(
                        label: 'Mark cleared',
                        size: SelloButtonSize.small,
                        variant: SelloButtonVariant.outline,
                        onPressed: _busy ? null : () => _clearCheque(payment),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Close',
        onCancel: () => Navigator.of(context).pop(_order),
        destructiveLabel: order.status == SupplierOrderStatus.draft ||
                (order.status == SupplierOrderStatus.awaitingDelivery &&
                    !order.hasReceipt)
            ? 'Cancel order'
            : (order.status.canReceive ? 'Close remaining' : null),
        onDestructive: _busy
            ? null
            : (order.status == SupplierOrderStatus.draft ||
                  (order.status == SupplierOrderStatus.awaitingDelivery &&
                      !order.hasReceipt))
            ? _cancel
            : (order.status.canReceive ? _closeRemaining : null),
        leading: order.status.canReceive
            ? SelloButton(
                label: 'Receive goods',
                variant: SelloButtonVariant.outline,
                onPressed: _busy ? null : _receive,
              )
            : null,
        primaryLabel: 'Record payment',
        primaryEnabled: order.status.canPay && !_busy,
        onPrimary: order.status.canPay && !_busy ? _pay : null,
      ),
    );
  }
}

class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.order, required this.currencySymbol});

  final SupplierOrderSummary order;
  final String currencySymbol;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final Map<String, TextEditingController> _qty;

  @override
  void initState() {
    super.initState();
    _qty = {
      for (final line in widget.order.lines)
        line.id: TextEditingController(
          text: line.stillOpen > 0
              ? SelloFormatters.quantity(line.stillOpen)
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _qty.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final lines = <({String orderLineId, num quantity})>[];
    for (final line in widget.order.lines) {
      final raw = _qty[line.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final qty = num.tryParse(raw);
      if (qty == null || qty < 0) return;
      if (qty > 0) lines.add((orderLineId: line.id, quantity: qty));
    }
    Navigator.of(context).pop(lines);
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Receive goods',
      subtitle: widget.order.orderNumber,
      maxWidth: 640,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Change the quantity if the supplier sent fewer, more, or some units cannot be accepted. Only what you enter is added to stock.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          for (final line in widget.order.lines) ...[
            Text(
              line.title,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Ordered ${SelloFormatters.quantity(line.quantity)} · Already in ${SelloFormatters.quantity(line.receivedQuantity)}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SelloTextField(
              label: 'Receive now',
              controller: _qty[line.id],
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.of(context).pop(),
        primaryLabel: 'Save receipt',
        onPrimary: _save,
      ),
    );
  }
}

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({required this.order});

  final SupplierOrderSummary order;

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  SupplierPayMethod _method = SupplierPayMethod.cash;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _method = widget.order.paymentMethod ?? SupplierPayMethod.cash;
    if (widget.order.stillOwed > 0) {
      _amount.text = widget.order.stillOwed.toString();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(supplierOrderRepositoryProvider).recordPayment(
        orderId: widget.order.id,
        amount: amount,
        method: _method.dbValue,
        reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Record payment',
      subtitle: widget.order.supplierName,
      maxWidth: 480,
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
          SelloTextField(
            label: 'Amount',
            required: true,
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final method in SupplierPayMethod.values)
                ChoiceChip(
                  label: Text(method.label),
                  selected: _method == method,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _method = method),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _method == SupplierPayMethod.cheque
                ? 'A cheque reduces what you owe when you mark it cleared.'
                : 'This reduces what you owe as soon as you save.',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SelloTextField(label: 'Reference', controller: _reference),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        primaryLabel: 'Save payment',
        primaryLoading: _saving,
        onPrimary: _saving ? null : _save,
      ),
    );
  }
}
