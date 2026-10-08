import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class EditChequeDetailsDialog extends ConsumerStatefulWidget {
  const EditChequeDetailsDialog({super.key, required this.cheque});

  final ChequeSummary cheque;

  @override
  ConsumerState<EditChequeDetailsDialog> createState() =>
      _EditChequeDetailsDialogState();
}

class _EditChequeDetailsDialogState
    extends ConsumerState<EditChequeDetailsDialog> {
  late final TextEditingController _bank;
  late final TextEditingController _number;
  late final TextEditingController _holder;
  late final TextEditingController _notes;
  late DateTime _date;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cheque = widget.cheque;
    _bank = TextEditingController(text: cheque.bankName);
    _number = TextEditingController(text: cheque.chequeNumber);
    _holder = TextEditingController(text: cheque.holderName);
    _notes = TextEditingController(text: cheque.notes ?? '');
    _date = cheque.chequeDate.toLocal();
  }

  @override
  void dispose() {
    _bank.dispose();
    _number.dispose();
    _holder.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_bank.text.trim().isEmpty ||
        _number.text.trim().isEmpty ||
        _holder.text.trim().isEmpty) {
      setState(() => _error = 'Bank, cheque number, and holder are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(chequeRepositoryProvider).updateDetails(
            chequeId: widget.cheque.id,
            bankName: _bank.text.trim(),
            chequeNumber: _number.text.trim(),
            holderName: _holder.text.trim(),
            chequeDate: _date,
            notes: _notes.text.trim(),
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
        _error = 'Unable to update cheque details. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Edit cheque details',
      subtitle:
          'Bank, number, holder, date, and notes only. Amount and status stay on the cheque lifecycle.',
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
          SelloTextField(
            controller: _bank,
            label: 'Bank',
            required: true,
          ),
          const SizedBox(height: 16),
          SelloFormRow(
            left: SelloTextField(
              controller: _number,
              label: 'Cheque number',
              required: true,
            ),
            right: SelloTextField(
              controller: _holder,
              label: 'Holder',
              required: true,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _submitting ? null : _pickDate,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InputDecorator(
              decoration: const InputDecoration(
                label: SelloFieldLabel(label: 'Cheque date', required: true),
                border: OutlineInputBorder(),
              ),
              child: Text(
                SelloFormatters.date(_date),
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
            label: 'Notes',
            maxLines: 3,
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: _submitting ? null : () => Navigator.of(context).maybePop(),
        primaryLabel: 'Save details',
        primaryLoading: _submitting,
        onPrimary: _submitting ? null : _submit,
      ),
    );
  }
}
