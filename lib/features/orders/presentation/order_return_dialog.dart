import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/orders/application/order_return_math.dart';
import 'package:sello/shared/models/order_return.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class OrderReturnDialog extends StatefulWidget {
  const OrderReturnDialog({
    super.key,
    required this.detail,
    required this.currencySymbol,
    required this.loadContext,
    required this.submit,
  });

  final OrderDetail detail;
  final String currencySymbol;
  final Future<OrderReturnContext> Function() loadContext;
  final Future<OrderReturnSummary> Function({
    required List<({String orderItemId, num quantity})> lines,
    required OrderReturnDestination destination,
    required bool restock,
  })
  submit;

  static Future<OrderReturnSummary?> show({
    required BuildContext context,
    required OrderDetail detail,
    required String currencySymbol,
    required Future<OrderReturnContext> Function() loadContext,
    required Future<OrderReturnSummary> Function({
      required List<({String orderItemId, num quantity})> lines,
      required OrderReturnDestination destination,
      required bool restock,
    })
    submit,
  }) {
    return showDialog<OrderReturnSummary>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderReturnDialog(
        detail: detail,
        currencySymbol: currencySymbol,
        loadContext: loadContext,
        submit: submit,
      ),
    );
  }

  @override
  State<OrderReturnDialog> createState() => _OrderReturnDialogState();
}

class _OrderReturnDialogState extends State<OrderReturnDialog> {
  late final Map<String, TextEditingController> _controllers;
  OrderReturnContext? _context;
  OrderReturnDestination _destination = OrderReturnDestination.cash;
  bool _restock = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<OrderLineItem> get _returnable => widget.detail.lines
      .where((line) => line.returnableQuantity > 0)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final line in _returnable)
        line.id: TextEditingController()..addListener(_refresh),
    };
    _load();
  }

  Future<void> _load() async {
    try {
      final context = await widget.loadContext();
      if (!mounted) return;
      setState(() {
        _context = context;
        _loading = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  OrderReturnQuote get _quote {
    var share = 0.0;
    var itemDiscount = 0.0;
    for (final line in _returnable) {
      final qty = num.tryParse(_controllers[line.id]?.text.trim() ?? '') ?? 0;
      if (qty <= 0) continue;
      share += OrderReturnQuote.lineShare(line, qty);
      itemDiscount += OrderReturnQuote.itemDiscountFor(line, qty);
    }
    final order = widget.detail.summary;
    return OrderReturnQuote.quote(
      orderSubtotal: order.subtotal,
      orderTotal: order.total,
      lineShareSum: share,
      stillOwed: _context?.stillOwed ?? 0,
      itemDiscount: itemDiscount,
      invoiceDiscount: OrderReturnQuote.invoiceShare(
        orderSubtotal: order.subtotal,
        orderDiscount: order.displayDiscountAmount,
        lineShareSum: share,
      ),
    );
  }

  String get _invoiceDiscountLabel {
    final order = widget.detail.summary;
    final percent = order.discountPercent;
    if (percent > 0.001 && order.discountFixedAmount <= 0.001) {
      final text = percent == percent.roundToDouble()
          ? percent.toStringAsFixed(0)
          : percent.toString();
      return 'Invoice discount ($text%)';
    }
    return 'Invoice discount';
  }

  String get _nothingToReturn {
    final lines = widget.detail.lines;
    final anyDelivered = lines.any((line) => line.deliveredQuantity > 0);
    final anyStillOpen = lines.any((line) => line.remainingQuantity > 0);
    if (!anyDelivered) {
      return 'Nothing has been delivered yet, so nothing can come back. '
          'To sell fewer items, correct the invoice. '
          'To drop the whole order, cancel it.';
    }
    if (anyStillOpen) {
      return 'Everything already delivered has been returned. '
          'Units that were never delivered can be reduced on the invoice, '
          'or closed with Cancel remaining.';
    }
    return 'Everything delivered on this order has already been returned.';
  }

  List<({String orderItemId, num quantity})>? _lines() {
    final lines = <({String orderItemId, num quantity})>[];
    for (final line in _returnable) {
      final raw = _controllers[line.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final qty = num.tryParse(raw);
      if (qty == null || qty < 0) {
        _error = 'Enter a quantity for each item you are returning.';
        return null;
      }
      if (qty == 0) continue;
      if (qty > line.returnableQuantity + 0.0001) {
        _error =
            '${line.displayTitle}: only '
            '${SelloFormatters.quantity(line.returnableQuantity)} can come back.';
        return null;
      }
      lines.add((orderItemId: line.id, quantity: qty));
    }
    if (lines.isEmpty) {
      _error = 'Enter at least one quantity to return.';
      return null;
    }
    return lines;
  }

  Future<void> _submit() async {
    final lines = _lines();
    if (lines == null) {
      setState(() {});
      return;
    }
    final quote = _quote;
    final approvalGuide = _context?.approvalGuide;
    if (approvalGuide != null) {
      setState(() => _error = approvalGuide);
      return;
    }
    if (quote.hasPaidPortion && _context?.chequeWaiting == true) {
      setState(() => _error = _context?.chequeGuide);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.submit(
        lines: lines,
        destination: quote.hasPaidPortion
            ? _destination
            : OrderReturnDestination.none,
        restock: _restock,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final order = widget.detail.summary;
    final quote = _quote;
    final money = widget.currencySymbol;
    final ready = _context != null;
    final approvalGuide = _context?.approvalGuide;
    final chequeBlocked =
        ready && quote.hasPaidPortion && _context!.chequeWaiting;

    return SelloFormDialog(
      title: 'Return items',
      subtitle: '${order.orderNumber} · ${order.customerName ?? 'Customer'}',
      maxWidth: 720,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 32,
        16,
        isMobile ? 20 : 32,
        8,
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (approvalGuide != null) ...[
                  _Guide(message: approvalGuide),
                  const SizedBox(height: 12),
                ] else if (chequeBlocked) ...[
                  _Guide(message: _context!.chequeGuide ?? ''),
                  const SizedBox(height: 12),
                ],
                if (_error != null && approvalGuide == null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_returnable.isEmpty)
                  Text(
                    _nothingToReturn,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  )
                else ...[
                const Text(
                  'Enter how many delivered units the customer is bringing back.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                  for (var i = 0; i < _returnable.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _ReturnLine(
                      line: _returnable[i],
                      controller: _controllers[_returnable[i].id]!,
                    ),
                  ],
                if (_returnable.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  if (quote.returnValue > 0.001 &&
                      quote.itemDiscount > 0.001) ...[
                    _SummaryLine(
                      label: 'Item discount',
                      value:
                          '− ${SelloFormatters.currency(quote.itemDiscount, symbol: money)}',
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (quote.returnValue > 0.001 &&
                      quote.invoiceDiscount > 0.001) ...[
                    _SummaryLine(
                      label: _invoiceDiscountLabel,
                      value:
                          '− ${SelloFormatters.currency(quote.invoiceDiscount, symbol: money)}',
                    ),
                    const SizedBox(height: 6),
                  ],
                  _SummaryLine(
                    label: 'Return value',
                    value: SelloFormatters.currency(
                      quote.returnValue,
                      symbol: money,
                    ),
                    strong: true,
                  ),
                  if (ready && quote.owedReduction > 0.001) ...[
                    const SizedBox(height: 6),
                    _SummaryLine(
                      label: 'Comes off what they owe',
                      value: SelloFormatters.currency(
                        quote.owedReduction,
                        symbol: money,
                      ),
                    ),
                  ],
                  if (ready && quote.hasPaidPortion) ...[
                    const SizedBox(height: 6),
                    _SummaryLine(
                      label: 'Already paid',
                      value: SelloFormatters.currency(
                        quote.paidPortion,
                        symbol: money,
                      ),
                    ),
                    if (!chequeBlocked) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Where should the paid amount go?',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DestinationChip(
                          label: 'Give it back',
                          icon: Icons.payments_outlined,
                          selected: _destination == OrderReturnDestination.cash,
                          onSelected: _saving
                              ? null
                              : () => setState(
                                  () => _destination =
                                      OrderReturnDestination.cash,
                                ),
                        ),
                        _DestinationChip(
                          label: 'Save for their next order',
                          icon: Icons.account_balance_wallet_outlined,
                          selected:
                              _destination == OrderReturnDestination.wallet,
                          onSelected: _saving
                              ? null
                              : () => setState(
                                  () => _destination =
                                      OrderReturnDestination.wallet,
                                ),
                        ),
                      ],
                    ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Put back in stock',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _restock
                                  ? 'These can be sold again.'
                                  : 'These cannot be sold again.',
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'This applies to every item in this return. If some are damaged and some can be sold again, record them as two returns.',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SelloSwitch(
                        value: _restock,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _restock = value),
                      ),
                    ],
                  ),
                ],
                ],
              ],
            ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        cancelEnabled: !_saving,
        onCancel: () => Navigator.of(context).pop(),
        primaryLabel: 'Return items',
        primaryLoading: _saving,
        primaryEnabled: !_loading &&
            ready &&
            approvalGuide == null &&
            _returnable.isNotEmpty &&
            !chequeBlocked,
        onPrimary: _saving || _loading ? null : _submit,
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13.5,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ReturnLine extends StatelessWidget {
  const _ReturnLine({required this.line, required this.controller});

  final OrderLineItem line;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            line.displayTitle,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${SelloFormatters.quantity(line.deliveredQuantity)} delivered · '
            '${SelloFormatters.quantity(line.returnableQuantity)} can come back',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SelloTextField(
            controller: controller,
            label: 'Return now',
            hint: '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final color = selected ? accent : AppColors.textSecondary;
    final radius = BorderRadius.circular(AppRadius.chip);
    return Material(
      color: selected
          ? context.selloColors.surfaceSelected
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected ? accent.withValues(alpha: 0.28) : AppColors.outline,
        ),
      ),
      child: InkWell(
        onTap: onSelected,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: strong ? 15 : 13.5,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
      color: strong ? AppColors.textPrimary : AppColors.textSecondary,
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}
