import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
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

  Future<void> _pickCustomer() async {
    if (widget.lockCustomer) return;
    final selected = await showDialog<CustomerSummary>(
      context: context,
      builder: (context) => _CustomerPicker(
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (selected == null || !mounted) return;
    _applyCustomer(selected);
  }

  void _applyCustomer(CustomerSummary selected) {
    setState(() {
      _customer = selected;
      _error = null;
      if (_holder.text.trim().isEmpty) {
        _holder.text = selected.name;
      }
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
          'Record a cheque received before you started using Sello. This won’t change the customer’s balance.',
      maxWidth: kSelloFormDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 32,
        20,
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
          SelloDialogSection(
            title: 'Customer',
            children: [
              if (_customer == null)
                SelloButton(
                  label: 'Select customer',
                  icon: Icons.person_search_rounded,
                  variant: SelloButtonVariant.outline,
                  onPressed: _pickCustomer,
                )
              else
                _CustomerStrip(
                  customer: _customer!,
                  onChange: widget.lockCustomer ? null : _pickCustomer,
                ),
            ],
          ),
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
                left: SelloTextField(
                  controller: _bank,
                  label: 'Bank',
                  required: true,
                ),
                right: SelloTextField(
                  controller: _chequeNumber,
                  label: 'Cheque number',
                  required: true,
                ),
              ),
              const SizedBox(height: 12),
              SelloTextField(
                controller: _holder,
                label: 'Cheque holder',
                required: true,
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
                  label: 'Collection date',
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
                  label: 'Deposit date',
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
                  label: 'Clearance date',
                  value: _clearanceDate,
                  onTap: () => _pickDate(
                    current: _clearanceDate,
                    onPicked: (value) => _clearanceDate = value,
                  ),
                ),
              ],
            ],
          ),
          SelloDialogSection(
            title: 'Photo',
            children: [
              SelloImagePickerPanel(
                title: 'Cheque image',
                localBytes: _photoBytes,
                onUpload: _uploadingPhoto ? () {} : _pickPhoto,
                onRemove: _photoBytes == null ? null : _clearPhoto,
                uploadLabel: _uploadingPhoto ? 'Uploading…' : 'Add photo',
                height: 180,
                hints: const [
                  'Optional photo of the physical cheque',
                  'Supports: PNG, JPG, WEBP',
                ],
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Notes',
            bottomSpacing: 8,
            children: [
              SelloTextField(
                controller: _notes,
                label: 'Internal notes',
                maxLines: 3,
              ),
            ],
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

class _CustomerStrip extends StatelessWidget {
  const _CustomerStrip({
    required this.customer,
    this.onChange,
  });

  final CustomerSummary customer;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (customer.phone != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    customer.phone!,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onChange != null)
            SelloButton(
              label: 'Change',
              size: SelloButtonSize.small,
              variant: SelloButtonVariant.ghost,
              onPressed: onChange,
            ),
        ],
      ),
    );
  }
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({required this.currencySymbol});

  final String currencySymbol;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<CustomerSummary> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(customerRepositoryProvider).fetchCustomers(
            search: _search.text,
            isActive: true,
            pageSize: 40,
          );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _loading = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Select customer',
      subtitle: 'Choose the customer this cheque belongs to.',
      maxWidth: 720,
      fullscreenOnMobile: true,
      body: Column(
        children: [
          SelloSearchBar(
            controller: _search,
            hint: 'Search name, phone or code…',
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 280), _load);
            },
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else if (_error != null)
            SelloStateView.error(
              title: 'Unable to load customers',
              message: _error,
              actionLabel: 'Try again',
              onAction: _load,
            )
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matching customers.'),
            )
          else
            SizedBox(
              height: 420,
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final customer = _items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      customer.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        if (customer.phone != null) customer.phone!,
                        'Outstanding ${SelloFormatters.currency(customer.outstandingBalance, symbol: widget.currencySymbol)}',
                      ].join(' · '),
                    ),
                    onTap: () => Navigator.of(context).pop(customer),
                  );
                },
              ),
            ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Close',
        primaryLabel: 'Done',
        primaryEnabled: false,
        onPrimary: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
