import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/models/supplier_order.dart';
import 'package:sello/shared/models/supplier_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class _DraftLine {
  _DraftLine({
    required this.productId,
    required this.variantId,
    required this.title,
    required this.quantity,
    required this.unitCost,
    this.sku,
  });

  final String productId;
  final String? variantId;
  final String title;
  final String? sku;
  final TextEditingController quantity;
  final TextEditingController unitCost;
}

class SupplierOrderEditorDialog extends ConsumerStatefulWidget {
  const SupplierOrderEditorDialog({this.existing, required this.currencySymbol});

  final SupplierOrderSummary? existing;
  final String currencySymbol;

  @override
  ConsumerState<SupplierOrderEditorDialog> createState() =>
      _SupplierOrderEditorDialogState();
}

class _SupplierOrderEditorDialogState
    extends ConsumerState<SupplierOrderEditorDialog> {
  final _search = TextEditingController();
  final _notes = TextEditingController();
  final List<_DraftLine> _lines = [];
  List<SupplierSummary> _suppliers = const [];
  List<Branch> _branches = const [];
  List<ProductSummary> _products = const [];
  String? _supplierId;
  String? _branchId;
  SupplierPayMethod? _method;
  bool _loading = true;
  bool _searching = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _supplierId = existing?.supplierId;
    _branchId = existing?.branchId;
    _method = existing?.paymentMethod;
    _notes.text = existing?.notes ?? '';
    if (existing != null) {
      for (final line in existing.lines) {
        _lines.add(
          _DraftLine(
            productId: line.productId,
            variantId: line.variantId,
            title: line.title,
            sku: line.sku,
            quantity: TextEditingController(
              text: SelloFormatters.quantity(line.quantity),
            ),
            unitCost: TextEditingController(text: line.unitCost.toString()),
          ),
        );
      }
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.quantity.dispose();
      line.unitCost.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    try {
      final suppliers = await ref
          .read(supplierRepositoryProvider)
          .fetchSuppliers(
            companyId: session.company.id,
            isActive: true,
            pageSize: 100,
          );
      final branches = await ref
          .read(branchRepositoryProvider)
          .fetchBranches(companyId: session.company.id);
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers.items;
        _branches = branches;
        _branchId ??= session.branch?.id ?? branches.firstOrNull?.id;
        _loading = false;
      });
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _searchProducts(String value) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    setState(() => _searching = true);
    try {
      final page = await ref.read(productRepositoryProvider).fetchProducts(
        search: value,
        isActive: true,
        pageSize: 12,
        branchId: _branchId,
      );
      if (!mounted) return;
      setState(() {
        _products = page.items;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  void _addProduct(ProductSummary product, ProductVariant? variant) {
    final variantId = variant?.id;
    final key = variantId ?? product.id;
    if (_lines.any((line) => (line.variantId ?? line.productId) == key)) {
      setState(() => _error = 'That product is already on the order.');
      return;
    }
    final label = variant?.label?.trim();
    final title = label != null &&
            label.isNotEmpty &&
            label.toLowerCase() != 'default'
        ? '${product.name} · $label'
        : product.name;
    final cost = variant?.unitCost ?? product.costPrice;
    setState(() {
      _error = null;
      _lines.add(
        _DraftLine(
          productId: product.id,
          variantId: variantId,
          title: title,
          sku: variant?.sku ?? product.sku,
          quantity: TextEditingController(text: '1'),
          unitCost: TextEditingController(
            text: cost == 0 ? '' : cost.toString(),
          ),
        ),
      );
      _search.clear();
      _products = const [];
    });
  }

  Future<void> _save({required bool place}) async {
    if (_supplierId == null) {
      setState(() => _error = 'Choose a supplier.');
      return;
    }
    if (_branchId == null) {
      setState(() => _error = 'Choose a branch.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    final lines = <({String productId, String? variantId, num quantity, num unitCost})>[];
    for (final line in _lines) {
      final qty = num.tryParse(line.quantity.text.trim());
      final cost = num.tryParse(line.unitCost.text.trim()) ?? 0;
      if (qty == null || qty <= 0) {
        setState(() => _error = '${line.title} needs a quantity.');
        return;
      }
      if (cost < 0) {
        setState(() => _error = '${line.title} has a cost below zero.');
        return;
      }
      lines.add((
        productId: line.productId,
        variantId: line.variantId,
        quantity: qty,
        unitCost: cost,
      ));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(supplierOrderRepositoryProvider).save(
        orderId: widget.existing?.id,
        supplierId: _supplierId!,
        branchId: _branchId!,
        lines: lines,
        paymentMethod: _method?.dbValue,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        place: place,
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.currencySymbol;
    return SelloFormDialog(
      title: widget.existing == null ? 'New supplier order' : 'Edit order',
      subtitle: 'Products already in Sello. Stock moves when the goods arrive.',
      maxWidth: 760,
      fullscreenOnMobile: true,
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SelloDropdown<String>(
                  label: 'Supplier',
                  required: true,
                  value: _supplierId,
                  items: [
                    for (final supplier in _suppliers)
                      DropdownMenuItem(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                  ],
                  onChanged: _saving
                      ? (_) {}
                      : (value) => setState(() => _supplierId = value),
                ),
                const SizedBox(height: 12),
                SelloDropdown<String>(
                  label: 'Branch',
                  required: true,
                  value: _branchId,
                  items: [
                    for (final branch in _branches)
                      DropdownMenuItem(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                  ],
                  onChanged: _saving
                      ? (_) {}
                      : (value) => setState(() => _branchId = value),
                ),
                const SizedBox(height: 12),
                Text(
                  'How you expect to pay',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final method in SupplierPayMethod.values)
                      ChoiceChip(
                        label: Text(method.label),
                        selected: _method == method,
                        onSelected: _saving
                            ? null
                            : (selected) => setState(
                                () => _method = selected ? method : null,
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SelloSearchBar(
                  controller: _search,
                  hint: 'Search products to add',
                  onChanged: (value) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => _searchProducts(value),
                    );
                  },
                ),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_products.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final product in _products) ..._productChoices(product),
                ],
                const SizedBox(height: 16),
                if (_lines.isEmpty)
                  const Text(
                    'No products yet.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  for (final line in _lines) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.title,
                                  style: const TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (line.sku != null)
                                  Text(
                                    line.sku!,
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: SelloTextField(
                              label: 'Qty',
                              required: true,
                              controller: line.quantity,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: SelloTextField(
                              label: 'Cost',
                              controller: line.unitCost,
                              hint: money,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    line.quantity.dispose();
                                    line.unitCost.dispose();
                                    _lines.remove(line);
                                  }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                const SizedBox(height: 8),
                SelloTextField(
                  label: 'Notes',
                  controller: _notes,
                  maxLines: 2,
                ),
              ],
            ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        leading: widget.existing?.status == SupplierOrderStatus.awaitingDelivery
            ? null
            : SelloButton(
                label: 'Save draft',
                variant: SelloButtonVariant.outline,
                loading: _saving,
                onPressed: _saving || _loading ? null : () => _save(place: false),
              ),
        primaryLabel: widget.existing?.status == SupplierOrderStatus.awaitingDelivery
            ? 'Save'
            : 'Place order',
        primaryLoading: _saving,
        primaryEnabled: !_loading,
        onPrimary: _saving || _loading
            ? null
            : () => _save(
                place: widget.existing?.status !=
                    SupplierOrderStatus.awaitingDelivery,
              ),
      ),
    );
  }

  List<Widget> _productChoices(ProductSummary product) {
    final variants = product.variants.where((v) => v.isActive).toList();
    if (variants.length <= 1) {
      return [_productTile(product, variants.firstOrNull)];
    }
    return [for (final variant in variants) _productTile(product, variant)];
  }

  Widget _productTile(ProductSummary product, ProductVariant? variant) {
    final label = variant?.label?.trim();
    final title = label != null &&
            label.isNotEmpty &&
            label.toLowerCase() != 'default'
        ? '${product.name} · $label'
        : product.name;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(variant?.sku ?? product.sku),
      onTap: () => _addProduct(product, variant),
    );
  }
}
