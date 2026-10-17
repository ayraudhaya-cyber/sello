import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Who received an in-hand customer cheque, and the day it was handed over.
class GiveChequeDialog extends StatefulWidget {
  const GiveChequeDialog({
    super.key,
    required this.cheque,
    this.editing = false,
  });

  final ChequeSummary cheque;
  final bool editing;

  @override
  State<GiveChequeDialog> createState() => _GiveChequeDialogState();
}

class _GiveChequeDialogState extends State<GiveChequeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late DateTime _givenOn;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.editing ? widget.cheque.givenToName ?? '' : '',
    );
    _note = TextEditingController(
      text: widget.editing ? widget.cheque.givenNote ?? '' : '',
    );
    _givenOn = widget.editing
        ? (widget.cheque.givenOn ?? DateTime.now())
        : DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _givenOn,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() => _givenOn = picked);
  }

  void _confirm() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter who received this cheque.');
      return;
    }
    if (name.length > 120) {
      setState(() => _error = 'Use a shorter name.');
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(
      GiveChequeInput(
        chequeId: widget.cheque.id,
        givenToName: name,
        givenOn: DateTime(_givenOn.year, _givenOn.month, _givenOn.day),
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: widget.editing ? 'Who received this cheque' : 'Give this cheque',
      subtitle: widget.editing
          ? 'Correct the name or the date. What the customer owes does not change.'
          : 'Hand the paper cheque to someone else. What the customer owes does not change.',
      maxWidth: 480,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloTextField(
            controller: _name,
            label: 'Given to',
            required: true,
            hint: 'Name of the person or business',
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InputDecorator(
              decoration: const InputDecoration(
                label: SelloFieldLabel(label: 'Date given', required: true),
                border: OutlineInputBorder(),
              ),
              child: Text(
                SelloFormatters.date(_givenOn),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelloTextField(
            controller: _note,
            label: 'Note',
            hint: 'Optional',
            maxLines: 2,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Back',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: () => Navigator.of(context).pop(),
        primaryLabel: widget.editing ? 'Save' : 'Give cheque',
        onPrimary: _confirm,
      ),
    );
  }
}
