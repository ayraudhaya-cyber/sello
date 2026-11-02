import 'package:flutter/material.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/order_return.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Cancels an order that has already been placed.
///
/// A draft uses the shorter confirm on the orders page.
class CancelOrderDialog extends StatefulWidget {
  const CancelOrderDialog({
    super.key,
    required this.order,
    required this.currencySymbol,
    required this.loadContext,
    required this.submit,
  });

  final OrderSummary order;
  final String currencySymbol;
  final Future<OrderReturnContext> Function() loadContext;
  final Future<void> Function({
    required String reason,
    required OrderReturnDestination destination,
  })
  submit;

  static Future<bool> show({
    required BuildContext context,
    required OrderSummary order,
    required String currencySymbol,
    required Future<OrderReturnContext> Function() loadContext,
    required Future<void> Function({
      required String reason,
      required OrderReturnDestination destination,
    })
    submit,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CancelOrderDialog(
        order: order,
        currencySymbol: currencySymbol,
        loadContext: loadContext,
        submit: submit,
      ),
    );
    return saved == true;
  }

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  final _reason = TextEditingController();
  OrderReturnContext? _context;
  OrderReturnDestination _destination = OrderReturnDestination.cash;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final context = await widget.loadContext();
      if (!mounted) return;
      setState(() {
        _context = context;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is AppFailure
            ? error.message
            : 'Unable to check this order.';
      });
    }
  }

  String _money(num value) =>
      SelloFormatters.currency(value, symbol: widget.currencySymbol);

  Future<void> _save() async {
    final figures = _context;
    if (figures == null || _saving) return;
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Write a short reason for cancelling this order.');
      return;
    }
    final paid = figures.amountPaid > 0.001;
    if (figures.approvalGuide != null || (paid && figures.chequeGuide != null)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.submit(
        reason: reason,
        destination: paid ? _destination : OrderReturnDestination.none,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is AppFailure
            ? error.message
            : 'Unable to cancel this order.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final figures = _context;
    final paid = (figures?.amountPaid ?? 0) > 0.001;
    final blocked =
        figures?.approvalGuide != null ||
        (paid && figures?.chequeGuide != null);

    return SelloFormDialog(
      title: 'Cancel order',
      subtitle:
          '${widget.order.orderNumber} stops here. Delivered items go back to stock. Units that were not delivered are no longer held. What they still owe on this order is cleared.',
      maxWidth: 560,
      fullscreenOnMobile: true,
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (figures?.approvalGuide != null)
                  Text(
                    figures!.approvalGuide!,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  )
                else if (paid && figures?.chequeGuide != null)
                  Text(
                    'A cheque on this order has not cleared yet. Finish it on Payments before cancelling. You can give the money back or add it to their wallet after that.',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  )
                else ...[
                  if (figures != null && figures.stillOwed > 0.001) ...[
                    Text(
                      '${_money(figures.stillOwed)} comes off what they owe.',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (paid) ...[
                    Text(
                      'They already paid ${_money(figures!.amountPaid)}. Where should that money go?',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Give the money back'),
                          selected:
                              _destination == OrderReturnDestination.cash,
                          onSelected: _saving
                              ? null
                              : (_) => setState(
                                  () => _destination =
                                      OrderReturnDestination.cash,
                                ),
                        ),
                        ChoiceChip(
                          label: const Text('Add to their wallet'),
                          selected:
                              _destination == OrderReturnDestination.wallet,
                          onSelected: _saving
                              ? null
                              : (_) => setState(
                                  () => _destination =
                                      OrderReturnDestination.wallet,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  SelloTextField(
                    controller: _reason,
                    label: 'Reason',
                    required: true,
                    maxLines: 3,
                    enabled: !_saving,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ],
              ],
            ),
      footer: SelloDialogFooter(
        cancelLabel: 'Keep order',
        primaryLabel: 'Cancel order',
        primaryEnabled: !_loading && !_saving && figures != null && !blocked,
        primaryLoading: _saving,
        onPrimary: _save,
      ),
    );
  }
}
