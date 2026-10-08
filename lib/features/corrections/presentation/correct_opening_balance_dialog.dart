import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/customer_receivable_adjustment.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class CorrectOpeningBalanceDialog extends ConsumerStatefulWidget {
  const CorrectOpeningBalanceDialog({
    super.key,
    required this.customer,
    required this.adjustment,
    required this.currencySymbol,
  });

  final CustomerSummary customer;
  final CustomerReceivableAdjustment adjustment;
  final String currencySymbol;

  @override
  ConsumerState<CorrectOpeningBalanceDialog> createState() =>
      _CorrectOpeningBalanceDialogState();
}

class _CorrectOpeningBalanceDialogState
    extends ConsumerState<CorrectOpeningBalanceDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _reason;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.adjustment.amount.toString());
    _reason = TextEditingController();
  }

  @override
  void dispose() {
    _amount.dispose();
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

    final money = SelloFormatters.currency(
      amount,
      symbol: widget.currencySymbol,
    );
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Correct opening balance?',
      message:
          'Sello will reverse the original opening balance and record $money '
          'as the corrected amount. Customer history stays explainable.',
      confirmLabel: 'Correct opening balance',
      cancelLabel: 'Cancel',
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(customerRepositoryProvider).correctOpeningBalanceAdjustment(
            adjustmentId: widget.adjustment.id,
            amount: amount,
            reason: _reason.text.trim(),
            notes: widget.adjustment.notes,
            referenceNumber: widget.adjustment.referenceNumber,
            recognizedAt: widget.adjustment.recognizedAt,
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
        _error = 'Unable to correct this opening balance. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Correct opening balance',
      subtitle:
          'Original ${widget.adjustment.adjustmentNumber}: '
          '${SelloFormatters.currency(widget.adjustment.amount, symbol: widget.currencySymbol)}.',
      maxWidth: 480,
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
          SelloTextField(
            controller: _amount,
            label: 'Corrected amount',
            required: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          SelloTextField(
            controller: _reason,
            label: 'Reason',
            required: true,
            hint: 'Entered the wrong amount…',
            maxLines: 2,
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: _submitting ? null : () => Navigator.of(context).maybePop(),
        primaryLabel: 'Correct opening balance',
        primaryLoading: _submitting,
        onPrimary: _submitting ? null : _submit,
      ),
    );
  }
}
