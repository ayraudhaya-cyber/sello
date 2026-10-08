import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/corrections/application/correction_rules.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Reverse-and-replace a completed or pending collection.
class CorrectPaymentDialog extends ConsumerStatefulWidget {
  const CorrectPaymentDialog({
    super.key,
    required this.detail,
    required this.currencySymbol,
  });

  final PaymentDetail detail;
  final String currencySymbol;

  @override
  ConsumerState<CorrectPaymentDialog> createState() =>
      _CorrectPaymentDialogState();
}

class _CorrectPaymentDialogState extends ConsumerState<CorrectPaymentDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _reference;
  late final TextEditingController _notes;
  late final TextEditingController _reason;
  late PaymentMethod _method;
  bool _submitting = false;
  String? _error;

  PaymentSummary get payment => widget.detail.summary;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: payment.amount.toString());
    _reference = TextEditingController(text: payment.reference ?? '');
    _notes = TextEditingController(text: payment.notes ?? '');
    _reason = TextEditingController();
    _method = payment.method.isSettlementMethod
        ? payment.method
        : PaymentMethod.cash;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = num.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a short reason for this correction.');
      return;
    }

    final allocTotal = widget.detail.allocations.fold<num>(
      0,
      (sum, item) => sum + item.amount,
    );
    if (allocTotal > amount + 0.001) {
      setState(
        () => _error =
            'The new amount is smaller than the current allocation. '
            'Enter at least ${SelloFormatters.currency(allocTotal, symbol: widget.currencySymbol)} '
            'or remove allocations by recording a new unallocated collection.',
      );
      return;
    }

    final money = SelloFormatters.currency(
      amount,
      symbol: widget.currencySymbol,
    );
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Correct payment?',
      message:
          '${PaymentCorrectionRules.explanation(payment.status)}\n\n'
          'Corrected amount: $money · ${_method.label}.',
      confirmLabel: 'Correct payment',
      cancelLabel: 'Cancel',
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(paymentRepositoryProvider).correctPayment(
            paymentId: payment.id,
            amount: amount,
            method: _method,
            allocations: [
              for (final alloc in widget.detail.allocations)
                PaymentAllocationInput(
                  orderId: alloc.orderId,
                  receivableAdjustmentId: alloc.receivableAdjustmentId,
                  amount: alloc.amount,
                ),
            ],
            reference: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            reason: _reason.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Unable to correct this payment. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Correct payment',
      subtitle: PaymentCorrectionRules.explanation(payment.status),
      maxWidth: kSelloFormDialogWidth,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SelloFormRow(
            left: SelloTextField(
              controller: _amount,
              label: 'Amount',
              required: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            right: SelloDropdown<PaymentMethod>(
              value: _method,
              label: 'Payment method',
              required: true,
              items: [
                for (final method in PaymentMethod.settlementMethods)
                  DropdownMenuItem(
                    value: method,
                    child: Text(method.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
          ),
          const SizedBox(height: 16),
          SelloTextField(
            controller: _reference,
            label: 'Reference',
          ),
          const SizedBox(height: 16),
          SelloTextField(
            controller: _notes,
            label: 'Notes',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SelloTextField(
            controller: _reason,
            label: 'Reason',
            required: true,
            hint: 'Wrong amount, wrong method, allocated to the wrong order…',
            maxLines: 2,
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: _submitting ? null : () => Navigator.of(context).maybePop(),
        primaryLabel: 'Correct payment',
        primaryLoading: _submitting,
        onPrimary: _submitting ? null : _submit,
      ),
    );
  }
}
