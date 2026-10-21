import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/payments/application/order_collection_rules.dart';
import 'package:sello/features/payments/application/receive_payment_allocation.dart';
import 'package:sello/features/payments/presentation/receivable_picker_copy.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Premium receive-payment workspace dialog.
class ReceivePaymentDialog extends ConsumerStatefulWidget {
  const ReceivePaymentDialog({
    super.key,
    required this.currencySymbol,
    this.visitId,
    this.initialCustomer,
    this.preferredOrderId,
  });

  final String currencySymbol;
  final String? visitId;
  final CustomerSummary? initialCustomer;

  /// Order just placed (visit checkout) — pre-selected with its balance.
  final String? preferredOrderId;

  @override
  ConsumerState<ReceivePaymentDialog> createState() =>
      _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends ConsumerState<ReceivePaymentDialog> {
  CustomerSummary? _customer;
  List<ReceivableOrder> _receivables = const [];
  final Map<String, num> _allocations = {};
  final Set<String> _selectedIds = {};
  PaymentMethod? _method = PaymentMethod.cash;
  final _amount = TextEditingController();
  final _discountAmount = TextEditingController();
  final _discountPercent = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  bool _loadingOrders = false;
  String? _error;

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
    _discountAmount.dispose();
    _discountPercent.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  num get _discountAmountValue {
    final value = num.tryParse(_discountAmount.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  num get _discountPercentValue {
    final value = num.tryParse(_discountPercent.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  bool _discountAllowed() {
    final role = ref.read(currentRoleProvider);
    if (role != UserRole.salesRepresentative) return true;
    final salesSettings = ref.read(selloCompanySettingsProvider).valueOrNull;
    if (salesSettings != null) {
      return salesSettings.salesRepsCanDiscountCollections;
    }
    return ref.read(companySettingsProvider).salesRepsCanDiscountCollections;
  }

  num get _allocatedTotal => ReceivePaymentAllocation.totalOf(_allocations);

  /// Money discount against the selected outstanding lines.
  num get _resolvedDiscount {
    if (!_discountAllowed()) return 0;
    return OrderCollectionRules.resolvedDiscount(
      outstanding: _allocatedTotal,
      amount: _discountAmountValue,
      percent: _discountPercentValue,
    );
  }

  void _writePaymentAmount(num value) {
    if (value <= 0) {
      _amount.clear();
      return;
    }
    _amount.text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  void _syncAmountFromAllocations() {
    final discount = _resolvedDiscount;
    final cash = _allocatedTotal - discount;
    _writePaymentAmount(cash < 0 ? 0 : cash);
  }

  Future<void> _pickCustomer() async {
    final selected = await showDialog<CustomerSummary>(
      context: context,
      builder: (context) =>
          _CustomerPicker(currencySymbol: widget.currencySymbol),
    );
    if (selected == null || !mounted) return;
    await _applyCustomer(selected);
  }

  Future<void> _applyCustomer(CustomerSummary selected) async {
    setState(() {
      _customer = selected;
      _allocations.clear();
      _selectedIds.clear();
      _amount.clear();
      _discountAmount.clear();
      _discountPercent.clear();
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
      });
      final preferredId = widget.preferredOrderId;
      if (preferredId != null && _selectedIds.isEmpty) {
        for (final receivable in orders) {
          if (receivable.id == preferredId) {
            _toggleReceivable(receivable, true);
            break;
          }
        }
      }
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingOrders = false;
        _error = failure.message;
      });
    }
  }

  void _toggleReceivable(ReceivableOrder receivable, bool selected) {
    setState(() {
      _error = null;
      if (selected) {
        _selectedIds.add(receivable.id);
        _allocations[receivable.id] = ReceivePaymentAllocation.fullAmount(
          receivable,
        );
      } else {
        _selectedIds.remove(receivable.id);
        _allocations.remove(receivable.id);
      }
      _syncAmountFromAllocations();
    });
  }

  void _editReceivableAmount(ReceivableOrder receivable, num amount) {
    setState(() {
      _error = null;
      final clamped = ReceivePaymentAllocation.clampAmount(
        amount: amount,
        remaining: receivable.remaining,
      );
      if (clamped <= 0) {
        _selectedIds.remove(receivable.id);
        _allocations.remove(receivable.id);
      } else {
        _selectedIds.add(receivable.id);
        _allocations[receivable.id] = clamped;
      }
      _syncAmountFromAllocations();
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _error = null;
      if (value == true) {
        _allocations
          ..clear()
          ..addAll(ReceivePaymentAllocation.selectAll(_receivables));
        _selectedIds
          ..clear()
          ..addAll(_allocations.keys);
      } else {
        _allocations.clear();
        _selectedIds.clear();
      }
      _syncAmountFromAllocations();
    });
  }

  ReceivePaymentInput? _buildInput() {
    if (_customer == null) {
      setState(() => _error = 'Select a customer.');
      return null;
    }
    final amount = num.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter a payment amount.');
      return null;
    }
    if (_method == null) {
      setState(() => _error = 'Choose a payment method.');
      return null;
    }
    if (_method == PaymentMethod.wallet &&
        amount > (_customer?.walletBalance ?? 0)) {
      setState(() => _error = 'Wallet balance is insufficient.');
      return null;
    }
    final discount = _resolvedDiscount;
    // Cap against selected receivables — not global customer AR (delivered-only).
    final discountError = OrderCollectionRules.validateDiscount(
      discount: discount,
      moneyReceived: amount,
      outstanding: _allocatedTotal > 0.001
          ? _allocatedTotal
          : (_customer?.outstandingBalance ?? 0),
      allowed: _discountAllowed(),
    );
    if (discountError != null) {
      setState(() => _error = discountError);
      return null;
    }
    final allocationError = ReceivePaymentAllocation.validate(
      paymentAmount: amount,
      discountAmount: discount,
      allocations: _allocations,
      receivables: _receivables,
    );
    if (allocationError != null) {
      setState(() => _error = allocationError);
      return null;
    }

    return ReceivePaymentInput(
      customerId: _customer!.id,
      amount: amount,
      discountAmount: discount,
      method: _method!,
      allocations: [
        for (final entry in _allocations.entries)
          if (entry.value > 0)
            PaymentAllocationInput.fromReceivable(
              _receivables.firstWhere((r) => r.id == entry.key),
              entry.value,
            ),
      ],
      reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      visitId: widget.visitId,
    );
  }

  void _confirm() {
    final input = _buildInput();
    if (input == null) return;
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    final symbol = widget.currencySymbol;
    final isMobile = context.isMobile;
    ref.watch(currentRoleProvider);
    ref.watch(selloCompanySettingsProvider);
    ref.watch(companySettingsProvider);
    final canDiscount = _discountAllowed();

    return SelloFormDialog(
      title: 'Receive payment',
      subtitle:
          'Collect money the customer already owes. Tick the orders or opening balance this payment should cover.',
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
          if (_customer != null)
            SelloDialogSection(
              title: 'Outstanding',
              children: [
                if (_loadingOrders)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_receivables.isEmpty)
                  const Text(
                    'No unpaid orders or opening balances. Payment will reduce '
                    'Outstanding, or add to Wallet if you collect more than they owe.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13.5,
                      color: AppColors.textFaint,
                    ),
                  )
                else
                  _OutstandingAllocations(
                    receivables: _receivables,
                    selectedIds: _selectedIds,
                    allocations: _allocations,
                    currencySymbol: symbol,
                    onSelectAll: _toggleSelectAll,
                    onSelected: _toggleReceivable,
                    onAmountChanged: _editReceivableAmount,
                  ),
              ],
            ),
          SelloDialogSection(
            title: 'Payment amount',
            children: [
              SelloTextField(
                controller: _amount,
                label: 'Amount',
                required: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) {
                  setState(() => _error = null);
                },
              ),
              if (canDiscount) ...[
                const SizedBox(height: 12),
                SelloFormRow(
                  left: SelloTextField(
                    controller: _discountAmount,
                    label: 'Discount amount',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) {
                      setState(() {
                        _error = null;
                        _syncAmountFromAllocations();
                      });
                    },
                  ),
                  right: SelloTextField(
                    controller: _discountPercent,
                    label: 'Discount %',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) {
                      setState(() {
                        _error = null;
                        _syncAmountFromAllocations();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use amount, percent, or both. Percent applies first to the '
                  'selected outstanding, then the amount.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textTertiary,
                  ),
                ),
                if (_resolvedDiscount > 0.001) ...[
                  const SizedBox(height: 12),
                  _ReceiveDiscountSummary(
                    currencySymbol: symbol,
                    allocated: _allocatedTotal,
                    discount: _resolvedDiscount,
                    discountPercent: _discountPercentValue,
                    discountAmount: _discountAmountValue,
                    moneyReceived: num.tryParse(_amount.text.trim()) ?? 0,
                  ),
                ],
              ],
            ],
          ),
          SelloDialogSection(
            title: 'Payment method',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final method in PaymentMethod.settlementMethods)
                    ChoiceChip(
                      label: Text(method.label),
                      selected: _method == method,
                      onSelected: (selected) {
                        setState(() {
                          _method = selected ? method : null;
                          _error = null;
                        });
                      },
                      selectedColor: context.brandAccentContainer,
                      labelStyle: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: _method == method
                            ? context.brandAccent
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(
                        color: _method == method
                            ? context.brandAccent.withValues(alpha: 0.35)
                            : AppColors.outlinePanel,
                      ),
                      backgroundColor: AppColors.surface,
                    ),
                ],
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Reference',
            children: [
              SelloTextField(
                controller: _reference,
                label: 'Payment reference',
                hint: 'Transfer ref, receipt no…',
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
        primaryLabel: 'Confirm payment',
        onPrimary: _confirm,
      ),
    );
  }
}

class _ReceiveDiscountSummary extends StatelessWidget {
  const _ReceiveDiscountSummary({
    required this.currencySymbol,
    required this.allocated,
    required this.discount,
    required this.discountPercent,
    required this.discountAmount,
    required this.moneyReceived,
  });

  final String currencySymbol;
  final num allocated;
  final num discount;
  final num discountPercent;
  final num discountAmount;
  final num moneyReceived;

  String _money(num value) =>
      SelloFormatters.currency(value, symbol: currencySymbol);

  String get _discountDetail {
    final parts = <String>[];
    if (discountPercent > 0.001) {
      final pct = discountPercent == discountPercent.roundToDouble()
          ? discountPercent.toStringAsFixed(0)
          : discountPercent.toString();
      parts.add('$pct% of selected');
    }
    if (discountAmount > 0.001) {
      parts.add(_money(discountAmount));
    }
    return parts.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    final settles = moneyReceived + discount;
    final remaining = allocated - settles;
    final remainingClamped = remaining < 0 ? 0 : remaining;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        children: [
          _ReceiveSummaryRow(
            label: 'Discount',
            value: '− ${_money(discount)}',
            detail: _discountDetail.isEmpty ? null : _discountDetail,
          ),
          const SizedBox(height: 8),
          _ReceiveSummaryRow(
            label: 'Amount received',
            value: _money(moneyReceived),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _ReceiveSummaryRow(
            label: 'Total applied',
            value: _money(settles),
            emphasize: true,
          ),
          const SizedBox(height: 8),
          _ReceiveSummaryRow(
            label: 'Outstanding left',
            value: _money(remainingClamped),
          ),
        ],
      ),
    );
  }
}

class _ReceiveSummaryRow extends StatelessWidget {
  const _ReceiveSummaryRow({
    required this.label,
    required this.value,
    this.detail,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String? detail;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: emphasize ? 13 : 12.5,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                  color: emphasize
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: emphasize ? 15 : 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        height: 1.3,
                      ),
                    ),
                    if (customer.phone != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        customer.phone!,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SelloButton(
                label: 'Change',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.ghost,
                onPressed: onChange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CustomerFact(
            label: 'Outstanding',
            value: SelloFormatters.currency(
              customer.outstandingBalance,
              symbol: currencySymbol,
            ),
          ),
          const SizedBox(height: 6),
          _CustomerFact(
            label: 'Wallet',
            value: SelloFormatters.currency(
              customer.walletBalance,
              symbol: currencySymbol,
            ),
          ),
          const SizedBox(height: 6),
          _CustomerFact(
            label: 'Credit',
            value: customer.creditAllowed
                ? SelloFormatters.currency(
                    customer.creditLimit,
                    symbol: currencySymbol,
                  )
                : 'Not allowed',
          ),
        ],
      ),
    );
  }
}

class _CustomerFact extends StatelessWidget {
  const _CustomerFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _OutstandingAllocations extends StatelessWidget {
  const _OutstandingAllocations({
    required this.receivables,
    required this.selectedIds,
    required this.allocations,
    required this.currencySymbol,
    required this.onSelectAll,
    required this.onSelected,
    required this.onAmountChanged,
  });

  final List<ReceivableOrder> receivables;
  final Set<String> selectedIds;
  final Map<String, num> allocations;
  final String currencySymbol;
  final ValueChanged<bool?> onSelectAll;
  final void Function(ReceivableOrder receivable, bool selected) onSelected;
  final void Function(ReceivableOrder receivable, num amount) onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final totalDue = receivables.fold<num>(
      0,
      (sum, row) => sum + row.remaining,
    );
    final selectAllValue = ReceivePaymentAllocation.selectAllValue(
      receivables: receivables,
      selectedIds: selectedIds,
    );

    return Column(
      children: [
        _SelectAllRow(
          value: selectAllValue,
          totalLabel: SelloFormatters.currency(
            totalDue,
            symbol: currencySymbol,
          ),
          onChanged: onSelectAll,
        ),
        const SizedBox(height: 8),
        for (final receivable in receivables) ...[
          _OrderAllocRow(
            order: receivable,
            currencySymbol: currencySymbol,
            selected: selectedIds.contains(receivable.id),
            allocated: allocations[receivable.id] ?? 0,
            onSelected: (selected) => onSelected(receivable, selected),
            onAmountChanged: (value) => onAmountChanged(receivable, value),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    required this.value,
    required this.totalLabel,
    required this.onChanged,
  });

  final bool? value;
  final String totalLabel;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == true;
    return Material(
      color: selected
          ? context.brandAccentContainer.withValues(alpha: 0.45)
          : AppColors.surfaceMuted,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: InkWell(
        onTap: () => onChanged(value == true ? false : true),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? context.brandAccent.withValues(alpha: 0.28)
                  : AppColors.outlinePanel,
            ),
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Row(
            children: [
              Checkbox(
                tristate: true,
                value: value,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: context.brandAccent,
                onChanged: onChanged,
              ),
              const SizedBox(width: 4),
              const Text(
                'Select all',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  totalLabel,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
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

  String _displayAmount(_OrderAllocRow row) {
    if (!row.selected || row.allocated <= 0) return '';
    return row.allocated.toStringAsFixed(2);
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
      final result = await ref
          .read(customerRepositoryProvider)
          .fetchCustomers(search: _search.text, isActive: true, pageSize: 40);
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
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(customer),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                          if (customer.phone != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              customer.phone!,
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Outstanding ${SelloFormatters.currency(customer.outstandingBalance, symbol: widget.currencySymbol)}',
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              height: 1.35,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
