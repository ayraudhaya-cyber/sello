import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/orders/order_fulfillment_math.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Result of recording a delivery against an open order.
class OrderFulfillmentResult {
  const OrderFulfillmentResult({required this.lines});

  /// Deliver quantities > 0 keyed by order item id.
  final List<({String orderItemId, num quantity})> lines;
}

/// Owner/Manager — record what was actually delivered (full or partial).
class OrderFulfillmentDialog extends StatefulWidget {
  const OrderFulfillmentDialog({
    super.key,
    required this.detail,
    required this.currencySymbol,
  });

  final OrderDetail detail;
  final String currencySymbol;

  static Future<OrderFulfillmentResult?> show({
    required BuildContext context,
    required OrderDetail detail,
    required String currencySymbol,
  }) {
    return showDialog<OrderFulfillmentResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderFulfillmentDialog(
        detail: detail,
        currencySymbol: currencySymbol,
      ),
    );
  }

  @override
  State<OrderFulfillmentDialog> createState() => _OrderFulfillmentDialogState();
}

class _OrderFulfillmentDialogState extends State<OrderFulfillmentDialog> {
  late final Map<String, TextEditingController> _controllers;
  String? _error;

  List<OrderLineItem> get _openLines => widget.detail.lines
      .where((line) => line.remainingQuantity > 0)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final line in _openLines)
        line.id: TextEditingController(
          text: SelloFormatters.quantity(line.remainingQuantity),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fillAllRemaining() {
    setState(() {
      _error = null;
      for (final line in _openLines) {
        _controllers[line.id]?.text =
            SelloFormatters.quantity(line.remainingQuantity);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _error = null;
      for (final controller in _controllers.values) {
        controller.text = '0';
      }
    });
  }

  void _submit() {
    final deliveries = <({String orderItemId, num quantity})>[];
    for (final line in _openLines) {
      final raw = _controllers[line.id]?.text.trim() ?? '';
      final qty = num.tryParse(raw) ?? 0;
      if (qty < 0) {
        setState(() => _error = 'Quantities cannot be negative.');
        return;
      }
      if (qty == 0) continue;
      final accepted = OrderFulfillmentMath.acceptFulfillmentQuantity(
        requested: qty,
        remaining: line.remainingQuantity,
      );
      if (accepted == null) {
        setState(() {
          _error =
              '${line.productName ?? 'Product'}: only '
              '${SelloFormatters.quantity(line.remainingQuantity)} remaining.';
        });
        return;
      }
      deliveries.add((orderItemId: line.id, quantity: accepted));
    }

    if (deliveries.isEmpty) {
      setState(() => _error = 'Enter at least one quantity to deliver.');
      return;
    }

    Navigator.of(context).pop(OrderFulfillmentResult(lines: deliveries));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final order = widget.detail.summary;

    return SelloFormDialog(
      title: 'Record delivery',
      subtitle: '${order.orderNumber} · ${order.customerName ?? 'Customer'}',
      maxWidth: 720,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 32,
        16,
        isMobile ? 20 : 32,
        8,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
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
          Text(
            'Enter how many units are being delivered now. '
            'Stock is reduced only for these quantities.',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SelloButton(
                label: 'Deliver remaining',
                variant: SelloButtonVariant.outline,
                size: SelloButtonSize.small,
                onPressed: _fillAllRemaining,
              ),
              const SizedBox(width: 8),
              SelloButton(
                label: 'Clear',
                variant: SelloButtonVariant.ghost,
                size: SelloButtonSize.small,
                onPressed: _clearAll,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_openLines.isEmpty)
            const Text(
              'Nothing left to deliver on this order.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: AppColors.textSecondary,
              ),
            )
          else
            for (var i = 0; i < _openLines.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _FulfillmentLineRow(
                line: _openLines[i],
                currencySymbol: widget.currencySymbol,
                controller: _controllers[_openLines[i].id]!,
              ),
            ],
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: () => Navigator.of(context).pop(),
        primaryLabel: 'Record delivery',
        onPrimary: _openLines.isEmpty ? null : _submit,
      ),
    );
  }
}

class _FulfillmentLineRow extends StatelessWidget {
  const _FulfillmentLineRow({
    required this.line,
    required this.currencySymbol,
    required this.controller,
  });

  final OrderLineItem line;
  final String currencySymbol;
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
            line.productName ?? 'Product',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${SelloFormatters.quantity(line.quantity)} ordered · '
            '${SelloFormatters.quantity(line.deliveredQuantity)} delivered · '
            '${SelloFormatters.quantity(line.remainingQuantity)} remaining',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SelloTextField(
            controller: controller,
            label: 'Deliver now',
            hint: '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Unit ${SelloFormatters.currency(line.unitPrice, symbol: currencySymbol)}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
