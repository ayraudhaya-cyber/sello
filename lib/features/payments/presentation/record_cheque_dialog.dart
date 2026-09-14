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
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Record a cheque instrument — returns [CreateChequeInput] for the caller to save.
class RecordChequeDialog extends ConsumerStatefulWidget {
  const RecordChequeDialog({
    super.key,
    required this.currencySymbol,
    this.visitId,
    this.initialCustomer,
    this.markCollected = false,
  });

  final String currencySymbol;
  final String? visitId;
  final CustomerSummary? initialCustomer;
  final bool markCollected;

  @override
  ConsumerState<RecordChequeDialog> createState() => _RecordChequeDialogState();
}

class _RecordChequeDialogState extends ConsumerState<RecordChequeDialog> {
  final _media = MediaService();

  CustomerSummary? _customer;
  List<ReceivableOrder> _receivables = const [];
  final Map<String, num> _allocations = {};

  final _amount = TextEditingController();
  final _bank = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _holder = TextEditingController();
  final _notes = TextEditingController();

  DateTime _chequeDate = DateTime.now();
  DateTime? _collectionDate;
  bool _markCollected = false;
  Uint8List? _photoBytes;
  String? _uploadedPhotoPath;
  bool _uploadingPhoto = false;
  bool _loadingOrders = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _markCollected = widget.markCollected;
    if (_markCollected) {
      _collectionDate = DateTime.now();
    }
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
    final selected = await showDialog<CustomerSummary>(
      context: context,
      builder: (context) => _CustomerPicker(
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (selected == null || !mounted) return;
    await _applyCustomer(selected);
  }

  Future<void> _applyCustomer(CustomerSummary selected) async {
    setState(() {
      _customer = selected;
      _allocations.clear();
      _error = null;
      _loadingOrders = true;
      if (_holder.text.trim().isEmpty) {
        _holder.text = selected.name;
      }
    });
    try {
      final orders = await ref
          .read(paymentRepositoryProvider)
          .fetchReceivableOrders(selected.id);
      if (!mounted) return;
      setState(() {
        _receivables = orders;
        _loadingOrders = false;
        if (_markCollected && orders.isNotEmpty) {
          final amount = num.tryParse(_amount.text.trim()) ?? 0;
          if (amount > 0) {
            _rebalanceAllocations(amount);
          } else {
            final totalDue = orders.fold<num>(0, (sum, o) => sum + o.remaining);
            _amount.text = totalDue.toStringAsFixed(2);
            _rebalanceAllocations(totalDue);
          }
        }
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingOrders = false;
        _error = failure.message;
      });
    }
  }

  void _rebalanceAllocations(num paymentAmount) {
    _allocations.clear();
    if (!_markCollected) return;
    var remaining = paymentAmount;
    for (final order in _receivables) {
      if (remaining <= 0) break;
      final take = order.remaining.clamp(0, remaining);
      if (take > 0) {
        _allocations[order.id] = take;
        remaining -= take;
      }
    }
  }

  Future<void> _pickDate({required bool collection}) async {
    final initial = collection
        ? (_collectionDate ?? DateTime.now())
        : _chequeDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (collection) {
        _collectionDate = picked;
      } else {
        _chequeDate = picked;
      }
    });
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

  CreateChequeInput? _buildInput() {
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
    if (_markCollected && _collectionDate == null) {
      setState(() => _error = 'Collection date is required when marked collected.');
      return null;
    }

    return CreateChequeInput(
      customerId: _customer!.id,
      amount: amount,
      bankName: _bank.text.trim(),
      chequeNumber: _chequeNumber.text.trim(),
      holderName: _holder.text.trim(),
      chequeDate: _chequeDate,
      collectionDate: _markCollected ? _collectionDate : null,
      photoPath: _uploadedPhotoPath,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      allocations: _markCollected
          ? [
              for (final entry in _allocations.entries)
                if (entry.value > 0)
                  PaymentAllocationInput(
                    orderId: entry.key,
                    amount: entry.value,
                  ),
            ]
          : const [],
      visitId: widget.visitId,
      markCollected: _markCollected,
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
    final symbol = widget.currencySymbol;
    final isMobile = context.isMobile;

    return SelloFormDialog(
      title: _markCollected ? 'Record collected cheque' : 'Record cheque',
      subtitle: _markCollected
          ? 'Cheque in hand — balances update when recorded as collected.'
          : 'Promise or scheduled collection — awaiting status until collected.',
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
                  currencySymbol: symbol,
                  onChange: _pickCustomer,
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
                onChanged: (value) {
                  final parsed = num.tryParse(value.trim()) ?? 0;
                  setState(() {
                    _error = null;
                    _rebalanceAllocations(parsed);
                  });
                },
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
                onTap: () => _pickDate(collection: false),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Collection',
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mark as collected',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  SelloSwitch(
                    value: _markCollected,
                    onChanged: (value) {
                      setState(() {
                        _markCollected = value;
                        if (value) {
                          _collectionDate ??= DateTime.now();
                          final amount =
                              num.tryParse(_amount.text.trim()) ?? 0;
                          if (amount > 0) _rebalanceAllocations(amount);
                        } else {
                          _collectionDate = null;
                          _allocations.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
              if (_markCollected) ...[
                const SizedBox(height: 12),
                _dateField(
                  label: 'Collection date',
                  value: _collectionDate,
                  required: true,
                  onTap: () => _pickDate(collection: true),
                ),
              ],
            ],
          ),
          if (_markCollected && _customer != null)
            SelloDialogSection(
              title: 'Outstanding orders',
              children: [
                if (_loadingOrders)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_receivables.isEmpty)
                  Text(
                    'No unpaid completed orders. Amount will reduce the '
                    'customer balance / credit the wallet if overpaid.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      color: AppColors.textFaint,
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final order in _receivables) ...[
                        _OrderAllocRow(
                          order: order,
                          currencySymbol: symbol,
                          allocated: _allocations[order.id] ?? 0,
                          onChanged: (value) {
                            setState(() {
                              if (value <= 0) {
                                _allocations.remove(order.id);
                              } else {
                                _allocations[order.id] =
                                    value.clamp(0, order.remaining);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
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
        primaryLabel: _submitting ? 'Saving…' : 'Save cheque',
        onPrimary: _submitting || _uploadingPhoto ? null : _confirm,
      ),
    );
  }
}

class _CustomerStrip extends StatelessWidget {
  const _CustomerStrip({
    required this.customer,
    required this.currencySymbol,
    required this.onChange,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final VoidCallback onChange;

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
                const SizedBox(height: 6),
                Text(
                  [
                    if (customer.phone != null) customer.phone!,
                    'Outstanding ${SelloFormatters.currency(customer.outstandingBalance, symbol: currencySymbol)}',
                    'Wallet ${SelloFormatters.currency(customer.walletBalance, symbol: currencySymbol)}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
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

class _OrderAllocRow extends StatefulWidget {
  const _OrderAllocRow({
    required this.order,
    required this.currencySymbol,
    required this.allocated,
    required this.onChanged,
  });

  final ReceivableOrder order;
  final String currencySymbol;
  final num allocated;
  final ValueChanged<num> onChanged;

  @override
  State<_OrderAllocRow> createState() => _OrderAllocRowState();
}

class _OrderAllocRowState extends State<_OrderAllocRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.allocated > 0 ? widget.allocated.toStringAsFixed(2) : '',
    );
  }

  @override
  void didUpdateWidget(covariant _OrderAllocRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next =
        widget.allocated > 0 ? widget.allocated.toStringAsFixed(2) : '';
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outlinePanel),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNumber,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Due ${SelloFormatters.currency(order.remaining, symbol: widget.currencySymbol)} · '
                  '${SelloFormatters.date(order.orderedAt)}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Allocate',
                isDense: true,
              ),
              onChanged: (value) {
                widget.onChanged(num.tryParse(value.trim()) ?? 0);
              },
            ),
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
      subtitle: 'Active customers with receivables or wallet activity.',
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
