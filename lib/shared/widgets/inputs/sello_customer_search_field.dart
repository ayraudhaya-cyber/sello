import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/utils/customer_search.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Inline customer search (name / phone / code). Selecting does not open a dialog.
class SelloCustomerSearchField extends ConsumerStatefulWidget {
  const SelloCustomerSearchField({
    super.key,
    required this.customer,
    required this.onChanged,
    required this.currencySymbol,
    this.enabled = true,
    this.required = true,
  });

  final CustomerSummary? customer;
  final ValueChanged<CustomerSummary?> onChanged;
  final String currencySymbol;
  final bool enabled;
  final bool required;

  @override
  ConsumerState<SelloCustomerSearchField> createState() =>
      _SelloCustomerSearchFieldState();
}

class _SelloCustomerSearchFieldState
    extends ConsumerState<SelloCustomerSearchField> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<CustomerSummary> _items = const [];
  bool _loading = false;
  String? _error;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    if (widget.customer == null) {
      Future.microtask(() => _load(''));
    }
  }

  @override
  void didUpdateWidget(covariant SelloCustomerSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customer != null &&
        oldWidget.customer?.id != widget.customer?.id) {
      _search.clear();
      _showResults = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus && widget.customer == null) {
      setState(() => _showResults = true);
      if (_items.isEmpty && !_loading) _load(_search.text);
    }
  }

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(customerRepositoryProvider)
          .fetchCustomers(search: query, isActive: true, pageSize: 12);
      if (!mounted) return;
      final filtered = result.items
          .where((customer) => matchesCustomerSearch(customer, query))
          .toList(growable: false);
      setState(() {
        _items = filtered;
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

  void _onQuery(String value) {
    setState(() => _showResults = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _load(value));
  }

  void _select(CustomerSummary customer) {
    _search.clear();
    _focus.unfocus();
    setState(() {
      _showResults = false;
      _items = const [];
    });
    widget.onChanged(customer);
  }

  void _clear() {
    _search.clear();
    widget.onChanged(null);
    setState(() => _showResults = true);
    Future.microtask(() {
      if (mounted) _focus.requestFocus();
    });
    _load('');
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.customer;
    if (selected != null) {
      return _SelectedCustomerStrip(
        customer: selected,
        currencySymbol: widget.currencySymbol,
        onChange: widget.enabled ? _clear : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloTextField(
          controller: _search,
          focusNode: _focus,
          enabled: widget.enabled,
          required: widget.required,
          label: 'Customer',
          hint: 'Search name or phone…',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: _onQuery,
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.error,
            ),
          ),
        ] else if (_showResults && !_loading) ...[
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Text(
              _search.text.trim().isEmpty
                  ? 'Type a customer name or phone number.'
                  : 'No matching customers.',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textFaint,
              ),
            )
          else
            _CustomerResultList(
              items: _items,
              currencySymbol: widget.currencySymbol,
              onSelect: _select,
            ),
        ],
      ],
    );
  }
}

class _SelectedCustomerStrip extends StatelessWidget {
  const _SelectedCustomerStrip({
    required this.customer,
    required this.currencySymbol,
    this.onChange,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
                    fontSize: 15.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (customer.phone != null) customer.phone!,
                    'Outstanding ${SelloFormatters.currency(customer.outstandingBalance, symbol: currencySymbol)}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

class _CustomerResultList extends StatelessWidget {
  const _CustomerResultList({
    required this.items,
    required this.currencySymbol,
    required this.onSelect,
  });

  final List<CustomerSummary> items;
  final String currencySymbol;
  final ValueChanged<CustomerSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.level2,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final customer = items[index];
          return InkWell(
            onTap: () => onSelect(customer),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (customer.phone != null) customer.phone!,
                      SelloFormatters.currency(
                        customer.outstandingBalance,
                        symbol: currencySymbol,
                      ),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
