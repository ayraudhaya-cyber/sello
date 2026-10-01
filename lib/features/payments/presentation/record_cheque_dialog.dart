import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/features/payments/presentation/receivable_picker_copy.dart';
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
    this.preferredOrderId,
    this.recordingIsOptional = false,
  });

  final String currencySymbol;
  final String? visitId;
  final CustomerSummary? initialCustomer;
  final bool markCollected;

  /// Visit/order just created — allocate this receivable first when in hand.
  final String? preferredOrderId;

  /// After visit checkout the order is already saved. Later / close skips
  /// without creating a cheque.
  final bool recordingIsOptional;

  @override
  ConsumerState<RecordChequeDialog> createState() => _RecordChequeDialogState();
}

class _RecordChequeDialogState extends ConsumerState<RecordChequeDialog> {
  final _media = MediaService();

  CustomerSummary? _customer;
  List<ReceivableOrder> _receivables = const [];
  final Map<String, num> _allocations = {};
  final Set<String> _selectedOrderIds = {};
  bool _allocationsManual = false;

  final _amount = TextEditingController();
  final _bank = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _holder = TextEditingController();
  final _notes = TextEditingController();

  DateTime _chequeDate = DateTime.now();
  DateTime? _collectionDate;
  bool _inHand = false;
  Uint8List? _photoBytes;
  String? _uploadedPhotoPath;
  bool _uploadingPhoto = false;
  bool _loadingOrders = false;
  bool _submitting = false;
  bool _extrasOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inHand = widget.markCollected;
    if (_inHand) {
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

  Future<void> _applyCustomer(CustomerSummary selected) async {
    final previousName = _customer?.name;
    setState(() {
      _holder.text = defaultChequeHolderName(
        currentHolder: _holder.text,
        selectedCustomerName: selected.name,
        previousCustomerName: previousName,
      );
      _customer = selected;
      _allocations.clear();
      _selectedOrderIds.clear();
      _allocationsManual = false;
      _error = null;
      _loadingOrders = true;
    });
    try {
      final orders = await ref
          .read(paymentRepositoryProvider)
          .fetchReceivableOrders(selected.id);
      if (!mounted) return;
      setState(() {
        _receivables = orders;
        _loadingOrders = false;
        if (_inHand && orders.isNotEmpty) {
          final amount = num.tryParse(_amount.text.trim()) ?? 0;
          if (amount > 0) {
            _rebalanceAllocations(amount);
          } else {
            final preferred = preferredChequeDefaultAmount(
              orders: orders,
              preferredOrderId: widget.preferredOrderId,
            );
            final fill =
                preferred ?? orders.fold<num>(0, (sum, o) => sum + o.remaining);
            _amount.text = fill.toStringAsFixed(2);
            _rebalanceAllocations(fill);
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
    if (_allocationsManual) return;
    _applyFifoAllocations(paymentAmount);
  }

  void _applyFifoAllocations(num paymentAmount) {
    _allocations.clear();
    _selectedOrderIds.clear();
    if (!_inHand) return;
    for (final alloc in fifoChequeAllocations(
      amount: paymentAmount,
      orders: _receivables,
      preferredOrderId: widget.preferredOrderId,
    )) {
      final targetId = alloc.orderId ?? alloc.receivableAdjustmentId;
      if (targetId == null) continue;
      _allocations[targetId] = alloc.amount;
      _selectedOrderIds.add(targetId);
    }
  }

  void _toggleOrder(ReceivableOrder order, bool selected) {
    setState(() {
      _allocationsManual = true;
      _error = null;
      if (selected) {
        _selectedOrderIds.add(order.id);
        _allocations[order.id] = chequeOrderSelectionAmount(order);
      } else {
        _selectedOrderIds.remove(order.id);
        _allocations.remove(order.id);
      }
    });
  }

  void _editOrderAmount(ReceivableOrder order, num amount) {
    setState(() {
      _allocationsManual = true;
      _error = null;
      final clamped = clampChequeOrderAllocation(
        amount: amount,
        remaining: order.remaining,
      );
      _selectedOrderIds.add(order.id);
      if (clamped > 0) {
        _allocations[order.id] = clamped;
      } else {
        _allocations[order.id] = 0;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _chequeDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() => _chequeDate = picked);
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
      final path = await ref
          .read(chequeRepositoryProvider)
          .uploadChequePhoto(
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
    if (_inHand && _collectionDate == null) {
      setState(
        () => _error =
            'Date received is required when you already have the cheque.',
      );
      return null;
    }
    if (_inHand) {
      final allocationError = chequeManualAllocationError(
        chequeAmount: amount,
        allocations: _allocations,
        orders: _receivables,
      );
      if (allocationError != null) {
        setState(() => _error = allocationError);
        return null;
      }
    }

    return CreateChequeInput(
      customerId: _customer!.id,
      amount: amount,
      bankName: _bank.text.trim(),
      chequeNumber: _chequeNumber.text.trim(),
      holderName: _holder.text.trim(),
      chequeDate: _chequeDate,
      collectionDate: _inHand ? _collectionDate : null,
      photoPath: _uploadedPhotoPath,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      allocations: _inHand
          ? [
              for (final entry in _allocations.entries)
                if (entry.value > 0)
                  PaymentAllocationInput.fromReceivable(
                    _receivables.firstWhere((r) => r.id == entry.key),
                    entry.value,
                  ),
            ]
          : const [],
      visitId: widget.visitId,
      markCollected: _inHand,
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

  Widget _dateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          label: const SelloFieldLabel(label: 'Cheque date', required: true),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          SelloFormatters.date(_chequeDate),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            color: AppColors.textPrimary,
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
      title: 'Record cheque',
      subtitle: widget.recordingIsOptional
          ? 'The order is already saved. Record this cheque now, or skip and record it later from the order.'
          : _inHand
          ? 'We have this cheque.'
          : 'Turn this off if the customer has not given the cheque yet.',
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
          SelloCustomerSearchField(
            customer: _customer,
            currencySymbol: symbol,
            onChanged: (selected) {
              if (selected == null) {
                setState(() {
                  _customer = null;
                  _receivables = const [];
                  _allocations.clear();
                  _selectedOrderIds.clear();
                  _allocationsManual = false;
                });
                return;
              }
              _applyCustomer(selected);
            },
          ),
          const SizedBox(height: 14),
          SelloTextField(controller: _holder, label: 'Holder', required: true),
          const SizedBox(height: 14),
          SelloTextField(
            controller: _amount,
            label: 'Amount',
            required: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              final parsed = num.tryParse(value.trim()) ?? 0;
              setState(() {
                _error = null;
                _rebalanceAllocations(parsed);
              });
            },
          ),
          const SizedBox(height: 14),
          SelloFormRow(
            stackBelow: 560,
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
          const SizedBox(height: 14),
          _dateField(),
          const SizedBox(height: 18),
          _InHandToggle(
            value: _inHand,
            onChanged: (value) {
              setState(() {
                _inHand = value;
                if (value) {
                  _collectionDate ??= DateTime.now();
                  final amount = num.tryParse(_amount.text.trim()) ?? 0;
                  if (!_allocationsManual && amount > 0) {
                    _rebalanceAllocations(amount);
                  }
                } else {
                  _collectionDate = null;
                  _allocations.clear();
                  _selectedOrderIds.clear();
                  _allocationsManual = false;
                }
              });
            },
          ),
          if (_inHand && _customer != null) ...[
            const SizedBox(height: 16),
            _OutstandingOrdersBlock(
              loading: _loadingOrders,
              receivables: orderReceivablesForCheque(
                orders: _receivables,
                preferredOrderId: widget.preferredOrderId,
              ),
              selectedIds: _selectedOrderIds,
              allocations: _allocations,
              currencySymbol: symbol,
              onSelected: _toggleOrder,
              onAmountChanged: _editOrderAmount,
            ),
          ],
          const SizedBox(height: 8),
          _ChequeExtrasSection(
            expanded:
                _extrasOpen || _photoBytes != null || _notes.text.isNotEmpty,
            onExpansionChanged: (open) => setState(() => _extrasOpen = open),
            photoBytes: _photoBytes,
            uploading: _uploadingPhoto,
            onPickPhoto: _pickPhoto,
            onClearPhoto: _photoBytes == null ? null : _clearPhoto,
            notes: _notes,
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: widget.recordingIsOptional ? 'Later' : 'Cancel',
        primaryLabel: _submitting ? 'Saving…' : 'Save cheque',
        onPrimary: _submitting || _uploadingPhoto ? null : _confirm,
      ),
    );
  }
}

class _InHandToggle extends StatelessWidget {
  const _InHandToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'I already have this cheque',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value
                      ? 'We have the paper cheque. What the customer owes will update, or wait for approval.'
                      : 'We do not have this cheque yet. What the customer owes stays the same.',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SelloSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _OutstandingOrdersBlock extends StatelessWidget {
  const _OutstandingOrdersBlock({
    required this.loading,
    required this.receivables,
    required this.selectedIds,
    required this.allocations,
    required this.currencySymbol,
    required this.onSelected,
    required this.onAmountChanged,
  });

  final bool loading;
  final List<ReceivableOrder> receivables;
  final Set<String> selectedIds;
  final Map<String, num> allocations;
  final String currencySymbol;
  final void Function(ReceivableOrder order, bool selected) onSelected;
  final void Function(ReceivableOrder order, num amount) onAmountChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Outstanding orders',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select the orders this cheque should cover. Edit an amount for a partial payment.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12.5,
            height: 1.35,
            color: AppColors.textFaint,
          ),
        ),
        const SizedBox(height: 10),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (receivables.isEmpty)
          const Text(
            'No unpaid completed orders. Amount will reduce the customer balance / credit the wallet if overpaid.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 1.4,
              color: AppColors.textFaint,
            ),
          )
        else
          for (final order in receivables) ...[
            _OrderAllocRow(
              order: order,
              currencySymbol: currencySymbol,
              selected: selectedIds.contains(order.id),
              allocated: allocations[order.id] ?? 0,
              onSelected: (selected) => onSelected(order, selected),
              onAmountChanged: (value) => onAmountChanged(order, value),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _ChequeExtrasSection extends StatelessWidget {
  const _ChequeExtrasSection({
    required this.expanded,
    required this.onExpansionChanged,
    required this.photoBytes,
    required this.uploading,
    required this.onPickPhoto,
    required this.onClearPhoto,
    required this.notes,
  });

  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final Uint8List? photoBytes;
  final bool uploading;
  final VoidCallback onPickPhoto;
  final VoidCallback? onClearPhoto;
  final TextEditingController notes;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
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
            localBytes: photoBytes,
            onUpload: uploading ? () {} : onPickPhoto,
            onRemove: onClearPhoto,
            uploadLabel: uploading ? 'Uploading…' : 'Add photo',
            height: 140,
            hints: const ['Optional photo of the physical cheque'],
          ),
          const SizedBox(height: 12),
          SelloTextField(
            controller: notes,
            label: 'Internal notes',
            maxLines: 2,
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
    required this.selected,
    required this.allocated,
    required this.onSelected,
    required this.onAmountChanged,
  });

  final ReceivableOrder order;
  final String currencySymbol;
  final bool selected;
  final num allocated;
  final ValueChanged<bool> onSelected;
  final ValueChanged<num> onAmountChanged;

  @override
  State<_OrderAllocRow> createState() => _OrderAllocRowState();
}

class _OrderAllocRowState extends State<_OrderAllocRow> {
  late final TextEditingController _controller;
  late final FocusNode _amountFocus;

  @override
  void initState() {
    super.initState();
    _amountFocus = FocusNode();
    _controller = TextEditingController(text: _displayAmount(widget));
  }

  @override
  void didUpdateWidget(covariant _OrderAllocRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_amountFocus.hasFocus) return;
    final next = _displayAmount(widget);
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  String _displayAmount(_OrderAllocRow widget) {
    if (!widget.selected) return '';
    if (widget.allocated <= 0) return '';
    return widget.allocated.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final selected = widget.selected;

    return Material(
      color: selected
          ? context.brandAccentContainer.withValues(alpha: 0.45)
          : AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 10, 12, 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? context.brandAccent.withValues(alpha: 0.28)
                : AppColors.outlinePanel,
          ),
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => widget.onSelected(!selected),
              borderRadius: BorderRadius.circular(AppRadius.panel),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeColor: context.brandAccent,
                      onChanged: (value) => widget.onSelected(value ?? false),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.pickerTitle,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.3,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          for (final line in ReceivablePickerCopy.subtitleLines(
                            order,
                            currencySymbol: widget.currencySymbol,
                          )) ...[
                            const SizedBox(height: 3),
                            Text(
                              line,
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                height: 1.35,
                                color: AppColors.textFaint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 2),
              child: TextField(
                controller: _controller,
                focusNode: _amountFocus,
                enabled: selected,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  label: const SelloFieldLabel(label: 'Amount'),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) {
                  widget.onAmountChanged(num.tryParse(value.trim()) ?? 0);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
