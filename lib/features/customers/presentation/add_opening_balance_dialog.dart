import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Owner/Manager records historical AR after the customer already exists.
class AddOpeningBalanceDialog extends ConsumerStatefulWidget {
  const AddOpeningBalanceDialog({
    super.key,
    required this.customer,
    required this.currencySymbol,
  });

  final CustomerSummary customer;
  final String currencySymbol;

  @override
  ConsumerState<AddOpeningBalanceDialog> createState() =>
      _AddOpeningBalanceDialogState();
}

class _AddOpeningBalanceDialogState
    extends ConsumerState<AddOpeningBalanceDialog> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _reference = TextEditingController();
  DateTime _asOf = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _asOf = DateTime(picked.year, picked.month, picked.day);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = num.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }

    final money = SelloFormatters.currency(
      amount,
      symbol: widget.currencySymbol,
    );
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Add opening balance?',
      message:
          'This will increase ${widget.customer.name}\'s outstanding by $money. '
          'It does not create an invoice.',
      confirmLabel: 'Add opening balance',
      cancelLabel: 'Cancel',
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(customerRepositoryProvider).recordOpeningBalanceAdjustment(
            customerId: widget.customer.id,
            amount: amount,
            recognizedAt: DateTime.utc(_asOf.year, _asOf.month, _asOf.day),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            referenceNumber: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
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
        _error = 'Unable to add this opening balance. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;

    return SelloFormDialog(
      title: 'Add opening balance',
      subtitle:
          'Record money this customer already owed before using Sello. '
          'This will increase their outstanding balance without creating an invoice.',
      maxWidth: kSelloFormDialogWidth,
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _error = null),
            ),
            right: SelloTextField(
              controller: _reference,
              label: 'Old invoice / reference',
              hint: 'INV-4587',
              helperText: 'Optional — reference from before Sello',
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _submitting ? null : _pickAsOf,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InputDecorator(
              decoration: const InputDecoration(
                label: SelloFieldLabel(label: 'As of', required: true),
                border: OutlineInputBorder(),
              ),
              child: Text(
                SelloFormatters.date(_asOf),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SelloTextField(
            controller: _notes,
            label: 'Note',
            hint: 'Why this amount is being added…',
            maxLines: 3,
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: 'Add opening balance',
        primaryLoading: _submitting,
        onPrimary: _submitting ? null : _submit,
      ),
    );
  }
}
