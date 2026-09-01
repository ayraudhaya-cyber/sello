import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Premium receive-payment workspace dialog.
class ReceivePaymentDialog extends ConsumerStatefulWidget {
  const ReceivePaymentDialog({
    super.key,
    required this.currencySymbol,
    this.visitId,
    this.initialCustomer,
  });

  final String currencySymbol;
  final String? visitId;
  final CustomerSummary? initialCustomer;

  @override
  ConsumerState<ReceivePaymentDialog> createState() =>
      _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends ConsumerState<ReceivePaymentDialog> {
  CustomerSummary? _customer;
  List<ReceivableOrder> _receivables = const [];
  final Map<String, num> _allocations = {};
  PaymentMethod? _method = PaymentMethod.cash;
  final _amount = TextEditingController();
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
    _reference.dispose();
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
      _amount.clear();
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
        if (orders.isNotEmpty) {
          final totalDue = orders.fold<num>(0, (sum, o) => sum + o.remaining);
          _amount.text = totalDue.toStringAsFixed(2);
          // Default FIFO full allocation
          var remaining = totalDue;
          for (final order in orders) {
            final take = order.remaining.clamp(0, remaining);
            if (take > 0) {
              _allocations[order.id] = take;
              remaining -= take;
            }
            if (remaining <= 0) break;
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

    return ReceivePaymentInput(
      customerId: _customer!.id,
      amount: amount,
      method: _method!,
      allocations: [
        for (final entry in _allocations.entries)
          if (entry.value > 0)
            PaymentAllocationInput(orderId: entry.key, amount: entry.value),
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

    return SelloFormDialog(
      title: 'Receive payment',
      subtitle:
          'Collect against outstanding orders. Partial and multi-order payments are supported.',
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
              title: 'Outstanding orders',
              children: [
                if (_loadingOrders)
                  const LinearProgressIndicator(minHeight: 2)
                else if (_receivables.isEmpty)
                  Text(
                    'No unpaid completed orders. Payment will reduce the '
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
            title: 'Payment amount',
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
                hint: 'Cheque no, transfer ref, receipt…',
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
                    customer.creditAllowed
                        ? 'Credit ${SelloFormatters.currency(customer.creditLimit, symbol: currencySymbol)}'
                        : 'No credit',
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
