import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

const _existingChequeStatuses = <ChequeStatus>[
  ChequeStatus.awaitingCollection,
  ChequeStatus.collected,
  ChequeStatus.deposited,
  ChequeStatus.cleared,
];

/// Record a pre-Sello cheque for tracking only — returns [CreateExistingChequeInput].
class AddExistingChequeDialog extends ConsumerStatefulWidget {
  const AddExistingChequeDialog({
    super.key,
    required this.currencySymbol,
    this.initialCustomer,
    this.lockCustomer = false,
  });

  final String currencySymbol;
  final CustomerSummary? initialCustomer;
  final bool lockCustomer;

  @override
  ConsumerState<AddExistingChequeDialog> createState() =>
      _AddExistingChequeDialogState();
}

class _AddExistingChequeDialogState
    extends ConsumerState<AddExistingChequeDialog> {
  final _media = MediaService();

  CustomerSummary? _customer;

  final _amount = TextEditingController();
  final _bank = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _holder = TextEditingController();
  final _notes = TextEditingController();

  DateTime _chequeDate = DateTime.now();
  DateTime? _collectionDate;
  DateTime? _depositDate;
  DateTime? _clearanceDate;
  ChequeStatus _status = ChequeStatus.awaitingCollection;

  Uint8List? _photoBytes;
  String? _uploadedPhotoPath;
  bool _uploadingPhoto = false;
  bool _submitting = false;
  bool _extrasOpen = false;
  String? _error;

  bool get _showCollectionDate =>
      _status == ChequeStatus.collected ||
      _status == ChequeStatus.deposited ||
      _status == ChequeStatus.cleared;

  bool get _showDepositDate =>
      _status == ChequeStatus.deposited || _status == ChequeStatus.cleared;

  bool get _showClearanceDate => _status == ChequeStatus.cleared;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCustomer;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyCustomer(initial);
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _bank.dispose();
    _chequeNumber.dispose();
    _holder.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _applyCustomer(CustomerSummary selected) {
    final previousName = _customer?.name;
    setState(() {
      _holder.text = defaultChequeHolderName(
        currentHolder: _holder.text,
        selectedCustomerName: selected.name,
        previousCustomerName: previousName,
      );
      _customer = selected;
      _error = null;
    });
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked));
  }

  Future<void> _pickPhoto() async {
    final companyId = ref.read(currentSessionProvider)?.company.id;
    if (companyId == null) {
      setState(() => _error = 'Your session expired. Sign in again.');
      return;
    }

    setState(() {
      _uploadingPhoto = true;
      _error = null;
      _extrasOpen = true;
    });
    try {
      final file = await _media.pickWithBestExperience(context);
      if (file == null || !mounted) {
        setState(() => _uploadingPhoto = false);
        return;
      }
      final raw = await file.readAsBytes();
      if (!mounted) return;
      final prepared = await _media.prepareForUpload(context, raw);
      if (prepared == null || !mounted) {
        setState(() => _uploadingPhoto = false);
        return;
      }

      final tempKey = 'draft-${DateTime.now().millisecondsSinceEpoch}';
      final path = await ref.read(chequeRepositoryProvider).uploadChequePhoto(
            companyId: companyId,
            chequeKey: tempKey,
            bytes: prepared.bytes,
            contentType: prepared.contentType,
          );
      if (!mounted) return;
      setState(() {
        _photoBytes = prepared.bytes;
        _uploadedPhotoPath = path;
        _uploadingPhoto = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _error = error.toString();
      });
    }
  }

  void _clearPhoto() {
    setState(() {
      _photoBytes = null;
      _uploadedPhotoPath = null;
    });
  }

  CreateExistingChequeInput? _buildInput() {
    if (_customer == null) {
      setState(() => _error = 'Select a customer.');
      return null;
    }
    final amount = num.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter a cheque amount greater than zero.');
      return null;
    }
    if (_bank.text.trim().isEmpty) {
      setState(() => _error = 'Enter the bank name.');
      return null;
    }
    if (_chequeNumber.text.trim().isEmpty) {
      setState(() => _error = 'Enter the cheque number.');
      return null;
    }
    if (_holder.text.trim().isEmpty) {
      setState(() => _error = 'Enter the cheque holder name.');
      return null;
    }

    return CreateExistingChequeInput(
      customerId: _customer!.id,
      amount: amount,
      bankName: _bank.text.trim(),
      chequeNumber: _chequeNumber.text.trim(),
      holderName: _holder.text.trim(),
      chequeDate: _chequeDate,
      status: _status,
      collectionDate: _showCollectionDate ? _collectionDate : null,
      depositDate: _showDepositDate ? _depositDate : null,
      clearanceDate: _showClearanceDate ? _clearanceDate : null,
      photoPath: _uploadedPhotoPath,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    final input = _buildInput();
    if (input == null) return;
    setState(() => _submitting = true);
    if (!mounted) return;
    Navigator.of(context).pop(input);
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    bool required = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          label: SelloFieldLabel(label: label, required: required),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          value == null ? 'Select date' : SelloFormatters.date(value),
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            color: value == null
                ? AppColors.textFaint
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;

    return SelloFormDialog(
      title: 'Add existing cheque',
      subtitle:
          'Old cheque record only — does not change what the customer owes. Use Record cheque for a new cheque.',
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.outlinePanel),
            ),
            child: const Text(
              'This is not a new collection. Sello stores the instrument for tracking only.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelloCustomerSearchField(
            customer: _customer,
            currencySymbol: widget.currencySymbol,
            enabled: !widget.lockCustomer,
            onChanged: (selected) {
              if (selected == null) {
                if (widget.lockCustomer) return;
                setState(() => _customer = null);
                return;
              }
              _applyCustomer(selected);
            },
          ),
          const SizedBox(height: 14),
          SelloTextField(
            controller: _holder,
            label: 'Holder',
            required: true,
          ),
          const SizedBox(height: 8),
          SelloDialogSection(
            title: 'Cheque details',
            children: [
              SelloTextField(
                controller: _amount,
                label: 'Amount',
                required: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              SelloFormRow(
                left: SelloSriLankaBankField(
                  controller: _bank,
                  onChanged: (_) => setState(() => _error = null),
                ),
                right: SelloTextField(
                  controller: _chequeNumber,
                  label: 'Cheque number',
                  required: true,
                ),
              ),
              const SizedBox(height: 12),
              _dateField(
                label: 'Cheque date',
                value: _chequeDate,
                required: true,
                onTap: () => _pickDate(
                  current: _chequeDate,
                  onPicked: (value) => _chequeDate = value,
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Current status',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in _existingChequeStatuses)
                    ChoiceChip(
                      label: Text(status.shortLabel),
                      selected: _status == status,
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() {
                          _status = status;
                          _error = null;
                        });
                      },
                      selectedColor: context.brandAccentContainer,
                      labelStyle: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: _status == status
                            ? context.brandAccent
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                        color: _status == status
                            ? context.brandAccent.withValues(alpha: 0.35)
                            : AppColors.outlinePanel,
                      ),
                      backgroundColor: AppColors.surface,
                    ),
                ],
              ),
              if (_showCollectionDate) ...[
                const SizedBox(height: 12),
                _dateField(
                  label: 'Date received',
                  value: _collectionDate,
                  onTap: () => _pickDate(
                    current: _collectionDate,
                    onPicked: (value) => _collectionDate = value,
                  ),
                ),
              ],
              if (_showDepositDate) ...[
                const SizedBox(height: 12),
                _dateField(
                  label: 'Taken to bank',
                  value: _depositDate,
                  onTap: () => _pickDate(
                    current: _depositDate,
                    onPicked: (value) => _depositDate = value,
                  ),
                ),
              ],
              if (_showClearanceDate) ...[
                const SizedBox(height: 12),
                _dateField(
                  label: 'Date bank paid',
                  value: _clearanceDate,
                  onTap: () => _pickDate(
                    current: _clearanceDate,
                    onPicked: (value) => _clearanceDate = value,
                  ),
                ),
              ],
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded:
                  _extrasOpen || _photoBytes != null || _notes.text.isNotEmpty,
              onExpansionChanged: (open) => setState(() => _extrasOpen = open),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text(
                'Add photo or notes',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              children: [
                SelloImagePickerPanel(
                  title: 'Cheque image',
                  localBytes: _photoBytes,
                  onUpload: _uploadingPhoto ? () {} : _pickPhoto,
                  onRemove: _photoBytes == null ? null : _clearPhoto,
                  uploadLabel: _uploadingPhoto ? 'Uploading…' : 'Add photo',
                  height: 140,
                  hints: const [
                    'Optional photo of the physical cheque',
                  ],
                ),
                const SizedBox(height: 12),
                SelloTextField(
                  controller: _notes,
                  label: 'Internal notes',
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: _submitting ? 'Saving…' : 'Save existing cheque',
        onPrimary: _submitting || _uploadingPhoto ? null : _confirm,
      ),
    );
  }
}
