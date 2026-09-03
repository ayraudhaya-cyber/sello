import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/products/presentation/sello_product_present_sheet.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_product_views.dart';
import 'package:sello/features/orders/presentation/widgets/product_layout_switcher.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/services/catalog/sales_catalog_layout_preferences.dart';
import 'package:sello/services/orders/order_stock_policy.dart';
import 'package:sello/services/reliability/reliability_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class OrderEditorResult {
  const OrderEditorResult({
    required this.input,
    this.complete = false,
    this.place = false,
  });

  final OrderUpsertInput input;

  /// Owner/Manager fulfillment finish (deducts remaining stock).
  final bool complete;

  /// Sales Rep submit — demand recorded as placed, no stock movement.
  final bool place;
}

/// Conversation-driven sales workspace — select customer, add products, complete or draft.
///
/// When [embedded] is true, renders the catalog/cart body only (no dialog chrome)
/// so a Customer Visit Workspace can host it without nested dialogs.
class OrderEditorDialog extends ConsumerStatefulWidget {
  const OrderEditorDialog({
    super.key,
    this.existing,
    required this.currencySymbol,
    this.visitId,
    this.initialCustomerId,
    this.initialCustomerName,
    this.embedded = false,
    this.visitMode = false,
    this.onEmbeddedResult,
    this.hideCustomerPicker = false,
    this.hideEmptyBasket = false,
    this.hideCartBar = false,
    this.onBasketChanged,
  });

  final OrderDetail? existing;
  final String currencySymbol;

  /// When creating an order during an active field visit.
  final String? visitId;
  final String? initialCustomerId;
  final String? initialCustomerName;

  /// Host inside [CustomerVisitWorkspacePage] — no [SelloFormDialog] chrome.
  final bool embedded;

  /// Soften copy for visit-first language (“shopping with…”) vs form language.
  final bool visitMode;

  /// Called instead of [Navigator.pop] when [embedded] is true.
  final ValueChanged<OrderEditorResult>? onEmbeddedResult;

  /// When the visit workspace already fixed the customer.
  final bool hideCustomerPicker;

  /// Visit workspace: hide the basket strip until products are added.
  final bool hideEmptyBasket;

  /// Visit workspace hosts its own compact basket bar.
  final bool hideCartBar;

  /// Notifies host when line count changes (for progressive disclosure).
  final ValueChanged<int>? onBasketChanged;

  @override
  ConsumerState<OrderEditorDialog> createState() => OrderEditorDialogState();
}

class OrderEditorDialogState extends ConsumerState<OrderEditorDialog> {
  CustomerSummary? _customer;
  final List<OrderLineDraft> _lines = [];
  PaymentMethod? _paymentMethod;
  final _notes = TextEditingController();
  final _orderDiscount = TextEditingController(text: '0');
  final _customerSearch = TextEditingController();
  final _productSearch = TextEditingController();
  final _customerFocus = FocusNode();

  Timer? _customerDebounce;
  Timer? _productDebounce;

  List<CustomerSummary> _customerResults = const [];
  bool _customerSearching = false;
  bool _showCustomerResults = false;
  bool _loadingCustomer = false;

  List<ProductSummary> _catalog = const [];
  List<ProductCategory> _categories = const [];
  String? _categoryId;
  bool _catalogLoading = true;
  String? _catalogError;

  ProductCatalogLayoutMode _layoutMode = ProductCatalogLayoutMode.gridTwo;
  final _layoutPreferences = SalesCatalogLayoutPreferencesStore();

  String? _error;

  /// Mobile: 0 = sell (customer + catalog), 1 = checkout.
  int _step = 0;

  bool get _isEdit => widget.existing != null;

  Map<String, OrderLineDraft> get _linesByProduct => {
        for (final line in _lines) line.productId: line,
      };

  CompanySettings get _settings =>
      ref.read(selloCompanySettingsProvider).valueOrNull ??
      CompanySettings.defaults;

  String? get _branchId {
    final session = ref.read(currentSessionProvider);
    return session?.branch?.id ?? session?.employee.branchId;
  }

  bool get _offlineStockHint {
    final snap = ref.read(connectivitySnapshotProvider).valueOrNull;
    return snap != null && !snap.transportOnline;
  }

  ProductSummary? _catalogProduct(String productId) {
    for (final product in _catalog) {
      if (product.id == productId) return product;
    }
    return null;
  }

  num? _availableForProduct(ProductSummary product) =>
      product.availableStockQuantity;

  num? maxQuantityForProduct(String productId) => _maxQuantityForProduct(productId);

  num? _maxQuantityForProduct(String productId) {
    final product = _catalogProduct(productId);
    final available = product?.availableStockQuantity ??
        _linesByProduct[productId]?.availableStock;
    return OrderStockPolicy.maxOrderQuantity(
      allowOrdersAboveAvailableStock:
          _settings.allowOrdersAboveAvailableStock,
      availableStock: available,
    );
  }

  void _showStockLimitFeedback(num? available) {
    if (!mounted) return;
    SelloSnackbars.warning(
      context,
      available == null
          ? 'Not enough stock available'
          : OrderStockPolicy.onlyAvailableMessage(available),
    );
  }

  void _onStockLimitReached(String productId) {
    final max = _maxQuantityForProduct(productId);
    _showStockLimitFeedback(
      max ?? _linesByProduct[productId]?.availableStock,
    );
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _paymentMethod = existing.summary.paymentMethod;
      _notes.text = existing.summary.notes ?? '';
      _orderDiscount.text = existing.summary.discountAmount.toString();
      for (final line in existing.lines) {
        _lines.add(
          OrderLineDraft(
            productId: line.productId,
            productName: line.productName ?? 'Product',
            productSku: line.productSku,
            unitPrice: line.unitPrice,
            quantity: line.quantity,
            discount: line.discount,
            discountType: line.discountType,
            existingItemId: line.id,
            productBrand: line.productBrand,
            productAttributes: Map<String, String>.from(line.productAttributes),
          ),
        );
      }
      Future.microtask(() => _hydrateCustomer(existing.summary.customerId));
    } else if (widget.initialCustomerId != null) {
      Future.microtask(() => _hydrateCustomer(widget.initialCustomerId!));
    }
    Future.microtask(_loadCatalog);
    Future.microtask(_loadCategories);
    Future.microtask(_loadLayoutPreference);
  }

  Future<void> _loadLayoutPreference() async {
    final mode = await _layoutPreferences.load();
    if (!mounted) return;
    setState(() => _layoutMode = mode);
  }

  void _setLayoutMode(ProductCatalogLayoutMode mode) {
    if (_layoutMode == mode) return;
    setState(() => _layoutMode = mode);
    _layoutPreferences.save(mode);
  }

  @override
  void dispose() {
    _customerDebounce?.cancel();
    _productDebounce?.cancel();
    _notes.dispose();
    _orderDiscount.dispose();
    _customerSearch.dispose();
    _productSearch.dispose();
    _customerFocus.dispose();
    super.dispose();
  }

  Future<void> _hydrateCustomer(String customerId) async {
    setState(() => _loadingCustomer = true);
    try {
      final customer =
          await ref.read(customerRepositoryProvider).fetchById(customerId);
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _loadingCustomer = false;
        _showCustomerResults = false;
        if (customer != null) {
          _customerSearch.text = customer.name;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCustomer = false);
    }
  }

  Future<void> _searchCustomers(String query) async {
    setState(() {
      _customerSearching = true;
      _showCustomerResults = true;
    });
    try {
      final result = await ref.read(customerRepositoryProvider).fetchCustomers(
            search: query,
            isActive: true,
            pageSize: 12,
          );
      if (!mounted) return;
      setState(() {
        _customerResults = result.items;
        _customerSearching = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _customerSearching = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _customerSearching = false);
    }
  }

  void _onCustomerQueryChanged(String value) {
    if (_customer != null) {
      setState(() {
        _customer = null;
        _error = null;
      });
    }
    _customerDebounce?.cancel();
    _customerDebounce = Timer(const Duration(milliseconds: 280), () {
      _searchCustomers(value);
    });
  }

  void _selectCustomer(CustomerSummary customer) {
    setState(() {
      _customer = customer;
      _customerSearch.text = customer.name;
      _showCustomerResults = false;
      _customerResults = const [];
      _error = null;
      if (_paymentMethod == PaymentMethod.credit && !customer.creditAllowed) {
        _paymentMethod = null;
      }
    });
    _customerFocus.unfocus();
  }

  void _clearCustomer() {
    setState(() {
      _customer = null;
      _customerSearch.clear();
      _showCustomerResults = false;
      _customerResults = const [];
      _error = null;
    });
  }

  Future<void> _loadCategories() async {
    try {
      final items = await ref.read(productRepositoryProvider).fetchCategories();
      if (!mounted) return;
      setState(() => _categories = items);
    } catch (_) {
      // Categories are optional chrome — catalog still works.
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final result = await ref.read(productRepositoryProvider).fetchProducts(
            search: _productSearch.text,
            categoryId: _categoryId,
            isActive: true,
            pageSize: 60,
            branchId: _branchId,
          );
      if (!mounted) return;
      setState(() {
        _catalog = result.items;
        _catalogLoading = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _catalogError = failure.message;
        _catalogLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catalogError = 'Unable to load products. Please try again.';
        _catalogLoading = false;
      });
    }
  }

  void _onProductSearchChanged(String _) {
    _productDebounce?.cancel();
    _productDebounce = Timer(const Duration(milliseconds: 280), _loadCatalog);
  }

  void _setCategory(String? categoryId) {
    if (_categoryId == categoryId) return;
    setState(() => _categoryId = categoryId);
    _loadCatalog();
  }

  void _addProduct(ProductSummary product) {
    final available = _availableForProduct(product);
    final max = OrderStockPolicy.maxOrderQuantity(
      allowOrdersAboveAvailableStock:
          _settings.allowOrdersAboveAvailableStock,
      availableStock: available,
    );
    if (max != null && max <= 0) {
      _showStockLimitFeedback(0);
      return;
    }

    final index = _lines.indexWhere((l) => l.productId == product.id);
    if (index >= 0) {
      final next = _lines[index].quantity + 1;
      if (max != null && next > max) {
        _showStockLimitFeedback(max);
        return;
      }
    }

    setState(() {
      if (index >= 0) {
        final existing = _lines[index];
        _lines[index] = existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _lines.add(
          OrderLineDraft(
            productId: product.id,
            productName: product.name,
            productSku: product.sku.isEmpty ? null : product.sku,
            imageUrl: product.imageUrl,
            unitPrice: product.sellingPrice,
            quantity: 1,
            availableStock: available,
            unitLabel: product.unitLabel,
            productBrand: product.brand,
            productAttributes: Map<String, String>.from(product.attributes),
          ),
        );
      }
      _error = null;
    });
    _notifyBasketChanged();
  }

  void _applyLineQuantity(String productId, num quantity) {
    if (quantity < 1) {
      final line = _linesByProduct[productId];
      if (line != null) _removeLineWithUndo(line);
      return;
    }

    final max = _maxQuantityForProduct(productId);
    final accepted = OrderStockPolicy.acceptQuantity(
      requested: quantity,
      max: max,
    );
    if (accepted == null) {
      _showStockLimitFeedback(
        max ?? _linesByProduct[productId]?.availableStock,
      );
      return;
    }

    setState(() {
      final index = _lines.indexWhere((l) => l.productId == productId);
      if (index < 0) return;
      final product = _catalogProduct(productId);
      _lines[index] = _lines[index].copyWith(
        quantity: accepted,
        availableStock: product != null
            ? _availableForProduct(product)
            : _lines[index].availableStock,
      );
      _error = null;
    });
    _notifyBasketChanged();
  }

  void _setLineQuantity(String productId, num quantity) {
    _applyLineQuantity(productId, quantity);
  }

  void _removeLineWithUndo(OrderLineDraft line) {
    setState(() {
      _lines.removeWhere((l) => l.productId == line.productId);
      _error = null;
    });
    _notifyBasketChanged();
    if (!mounted) return;
    SelloSnackbars.show(
      context,
      message: 'Item removed',
      kind: SelloToastKind.info,
      actionLabel: 'Undo',
      onAction: () {
        setState(() {
          if (!_lines.any((l) => l.productId == line.productId)) {
            _lines.add(line);
          }
        });
        _notifyBasketChanged();
      },
      duration: const Duration(seconds: 5),
    );
  }

  void _removeLine(String productId) {
    final line = _linesByProduct[productId];
    if (line != null) _removeLineWithUndo(line);
  }

  void _notifyBasketChanged() {
    widget.onBasketChanged?.call(_lines.length);
  }

  num get _orderDiscountValue =>
      num.tryParse(_orderDiscount.text.trim()) ?? 0;

  num get _subtotal =>
      OrderCalculations.subtotal(_lines.map((line) => line.lineTotal));

  num get _total => OrderCalculations.grandTotal(
        subtotal: _subtotal,
        orderDiscount: _orderDiscountValue,
      );

  OrderUpsertInput _buildInput() {
    return OrderUpsertInput(
      orderId: widget.existing?.summary.id,
      customerId: _customer!.id,
      lines: List<OrderLineDraft>.from(_lines),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      paymentMethod: _paymentMethod,
      paymentStatus: _paymentMethod == PaymentMethod.credit ||
              _paymentMethod == null
          ? PaymentStatus.unpaid
          : PaymentStatus.unpaid,
      orderDiscount: _orderDiscountValue,
      taxAmount: 0,
      visitId: widget.visitId,
    );
  }

  CustomerSummary? get selectedCustomer => _customer;
  List<OrderLineDraft> get lines => List.unmodifiable(_lines);
  num get runningTotal => _total;
  num get itemQuantity => _lines.fold<num>(0, (sum, line) => sum + line.quantity);

  void setLineQuantity(String productId, num quantity) =>
      _setLineQuantity(productId, quantity);

  void removeLine(String productId) => _removeLine(productId);

  Future<int> restoreFromProductLines(
    List<({String productId, num quantity})> lines,
  ) async {
    if (lines.isEmpty) return 0;
    try {
      final result = await ref.read(productRepositoryProvider).fetchProducts(
            pageSize: 200,
            isActive: true,
            branchId: _branchId,
          );
      final byId = {for (final product in result.items) product.id: product};
      final stockWarnings = <String>[];
      setState(() {
        _lines.clear();
        for (final line in lines) {
          final product = byId[line.productId];
          if (product == null) continue;
          final available = _availableForProduct(product);
          final qty = line.quantity;
          final max = OrderStockPolicy.maxOrderQuantity(
            allowOrdersAboveAvailableStock:
                _settings.allowOrdersAboveAvailableStock,
            availableStock: available,
          );
          if (max != null && qty > max) {
            stockWarnings.add(
              '${product.name}: ${OrderStockPolicy.onlyAvailableMessage(max)}',
            );
          }
          if (qty < 1) continue;
          _lines.add(
            OrderLineDraft(
              productId: product.id,
              productName: product.name,
              productSku: product.sku.isEmpty ? null : product.sku,
              imageUrl: product.imageUrl,
              unitPrice: product.sellingPrice,
              quantity: qty,
              availableStock: available,
              unitLabel: product.unitLabel,
              productBrand: product.brand,
              productAttributes: Map<String, String>.from(product.attributes),
            ),
          );
        }
        _error = null;
      });
      _notifyBasketChanged();
      if (stockWarnings.isNotEmpty && mounted) {
        SelloSnackbars.warning(
          context,
          stockWarnings.first,
        );
      }
      return _lines.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> refreshCatalogStock() async {
    await _loadCatalog();
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _lines.length; i++) {
        final product = _catalogProduct(_lines[i].productId);
        if (product == null) continue;
        _lines[i] = _lines[i].copyWith(
          availableStock: _availableForProduct(product),
        );
      }
    });
    _notifyBasketChanged();
  }

  bool _lineExceedsAvailable(OrderLineDraft line) {
    final max = _maxQuantityForProduct(line.productId);
    return max != null && line.quantity > max;
  }

  String? _stockViolationMessage() {
    for (final line in _lines) {
      if (_lineExceedsAvailable(line)) {
        final product = _catalogProduct(line.productId);
        final max = _maxQuantityForProduct(line.productId);
        final name = product?.name ?? line.productName;
        if (max != null) {
          return '$name now has only ${SelloFormatters.quantity(max)} available. Adjust the quantity and try again.';
        }
      }
    }
    return null;
  }

  bool _validateStockForSubmission({required bool enforcing}) {
    if (!enforcing || _settings.allowOrdersAboveAvailableStock) {
      return true;
    }
    final message = _stockViolationMessage();
    if (message == null) return true;
    setState(() => _error = message);
    if (mounted) {
      SelloSnackbars.warning(context, message);
    }
    return false;
  }

  void clearBasket() {
    setState(() {
      _lines.clear();
      _error = null;
    });
    _notifyBasketChanged();
  }

  /// Attach a customer after walk-in registration (visit workspace).
  void bindCustomer(CustomerSummary customer) {
    setState(() {
      _customer = customer;
      _customerSearch.text = customer.name;
      _showCustomerResults = false;
      _error = null;
    });
  }

  /// Build a validated result without navigating — used by visit workspace.
  OrderEditorResult? tryBuildResult({
    bool complete = false,
    bool place = false,
  }) {
    if (_customer == null) {
      setState(() => _error = 'Select a customer to continue.');
      return null;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return null;
    }
    if (complete && _paymentMethod == null) {
      if (!widget.embedded) {
        setState(() => _error = 'Choose a payment method to complete the order.');
        return null;
      }
    }
    if (complete &&
        _paymentMethod == PaymentMethod.credit &&
        _customer?.creditAllowed != true) {
      setState(() => _error = 'This customer is not allowed to buy on credit.');
      return null;
    }
    if (!_validateStockForSubmission(enforcing: complete || place)) {
      return null;
    }

    return OrderEditorResult(
      input: _buildInput(),
      complete: complete && (_paymentMethod != null || !widget.embedded),
      place: place,
    );
  }

  void submitEmbedded({required bool complete}) {
    final result = tryBuildResult(complete: complete);
    if (result == null) return;
    widget.onEmbeddedResult?.call(result);
  }

  void _submit({bool complete = false, bool place = false}) {
    if (_customer == null) {
      setState(() => _error = 'Select a customer to continue.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    if (complete && _paymentMethod == null) {
      setState(() => _error = 'Choose a payment method to complete the order.');
      return;
    }
    if (complete &&
        _paymentMethod == PaymentMethod.credit &&
        _customer?.creditAllowed != true) {
      setState(() => _error = 'This customer is not allowed to buy on credit.');
      return;
    }
    if (!_validateStockForSubmission(enforcing: complete || place)) {
      return;
    }

    final result = OrderEditorResult(
      input: _buildInput(),
      complete: complete,
      place: place,
    );
    if (widget.embedded) {
      widget.onEmbeddedResult?.call(result);
      return;
    }
    Navigator.of(context).pop(result);
  }

  void _goCheckout() {
    setState(() {
      _error = null;
      if (_customer == null) {
        _error = 'Select a customer to continue.';
        return;
      }
      if (_lines.isEmpty) {
        _error = 'Add at least one product.';
        return;
      }
      _step = 1;
    });
  }

  void _goBack() {
    if (_step <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  bool get _isSalesWorkspace =>
      ref.read(currentSessionProvider)?.usesSello == true;

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final symbol = widget.currencySymbol;
    final useSteps = isMobile && !widget.embedded;
    final selling = !useSteps || _step == 0;
    final visitMode = widget.visitMode || widget.embedded;
    final primaryActionLabel =
        _isSalesWorkspace ? 'Submit order' : 'Fulfill all';
    void onPrimaryAction() {
      if (_isSalesWorkspace) {
        _submit(place: true);
      } else {
        _submit(complete: true);
      }
    }

    final body = Column(
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
          const SizedBox(height: 10),
        ],
        if (selling) ...[
          if (!widget.hideCustomerPicker) ...[
            _buildCustomerPicker(symbol),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: isMobile
                ? _buildMobileSellBody(symbol)
                : _buildDesktopSellBody(symbol),
          ),
        ] else
          Expanded(
            child: SingleChildScrollView(
              child: _buildCheckoutBody(symbol, includeCustomer: true),
            ),
          ),
      ],
    );

    if (widget.embedded) {
      return body;
    }

    return SelloFormDialog(
      title: useSteps
          ? (_step == 0
              ? (_isEdit
                  ? 'Edit order'
                  : (visitMode ? 'Visit order' : 'New order'))
              : 'Review & complete')
          : (_isEdit
              ? 'Edit draft order'
              : (visitMode ? 'Visit order' : 'New order')),
      subtitle: useSteps
          ? (_step == 0
              ? (visitMode
                  ? null
                  : 'Pick the customer, then browse products together.')
              : null)
          : null,
      maxWidth: kSelloFormDialogWidth,
      fullscreenOnMobile: true,
      scrollableBody: false,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        12,
        isMobile ? 16 : 24,
        8,
      ),
      body: body,
      footer: useSteps
          ? SelloDialogFooter(
              cancelLabel: _step == 0 ? 'Close' : 'Back',
              cancelVariant: SelloButtonVariant.outline,
              onCancel: _goBack,
              primaryLabel: _step == 0 ? 'Review order' : primaryActionLabel,
              onPrimary: _step == 0 ? _goCheckout : onPrimaryAction,
            )
          : SelloDialogFooter(
              cancelLabel: 'Save draft',
              cancelVariant: SelloButtonVariant.outline,
              onCancel: () => _submit(complete: false),
              primaryLabel: primaryActionLabel,
              onPrimary: onPrimaryAction,
            ),
    );
  }

  Widget _buildMobileSellBody(String symbol) {
    final showBasket = _lines.isNotEmpty || !widget.hideEmptyBasket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildCatalogPane(symbol)),
        if (showBasket && !widget.hideCartBar) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildCartBar(symbol),
        ],
      ],
    );
  }

  Widget _buildDesktopSellBody(String symbol) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 62, child: _buildCatalogPane(symbol)),
        const SizedBox(width: 16),
        SizedBox(
          width: 340,
          child: _buildOrderSidebar(symbol),
        ),
      ],
    );
  }

  Widget _buildCustomerPicker(String symbol) {
    if (_loadingCustomer) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (_customer != null) {
      return _CustomerChipBar(
        customer: _customer!,
        currencySymbol: symbol,
        onChange: _clearCustomer,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloSearchBar(
          controller: _customerSearch,
          focusNode: _customerFocus,
          hint: 'Search customer by name, phone, or code…',
          onChanged: _onCustomerQueryChanged,
          onTap: () {
            if (!_showCustomerResults) {
              _searchCustomers(_customerSearch.text);
            }
          },
        ),
        if (_showCustomerResults) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outlinePanel),
              boxShadow: AppShadows.level2,
            ),
            child: _customerSearching
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _customerResults.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No matching customers. Try another name or phone.',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _customerResults.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.outlineSubtle),
                        itemBuilder: (context, index) {
                          final customer = _customerResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              customer.name,
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (customer.phone != null) customer.phone!,
                                'Owes ${SelloFormatters.currency(customer.outstandingBalance, symbol: symbol)}',
                              ].join(' · '),
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            onTap: () => _selectCustomer(customer),
                          );
                        },
                      ),
          ),
        ],
      ],
    );
  }

  Widget _buildCatalogPane(String symbol) {
    // Hub/mobile order create: catalog waits for a customer.
    // Visit / walk-in (visitMode): catalog-first — customer is fixed by the
    // host or registered only when the buyer purchases.
    final catalogOpen = _customer != null || widget.visitMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloSearchBar(
          controller: _productSearch,
          hint: 'Search products…',
          onChanged: catalogOpen ? _onProductSearchChanged : null,
          enabled: catalogOpen,
        ),
        const SizedBox(height: AppSpacing.sm),
        _CategoryChips(
          categories: _categories,
          selectedId: _categoryId,
          enabled: catalogOpen,
          onSelected: _setCategory,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _IntelligenceSuggestionsStrip(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            ProductLayoutSwitcher(
              mode: _layoutMode,
              onChanged: _setLayoutMode,
            ),
            const Spacer(),
            if (catalogOpen && !_catalogLoading && _catalog.isNotEmpty)
              Text(
                '${_catalog.length} products',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.textFaint,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: !catalogOpen
              ? const _CatalogGate()
              : _catalogLoading
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  : _catalogError != null
                      ? SelloStateView.error(
                          title: 'Unable to load products',
                          message: _catalogError,
                          actionLabel: 'Try again',
                          onAction: _loadCatalog,
                        )
                      : _catalog.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No products match. Try another search or category.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                          : _buildProductCatalog(symbol),
        ),
      ],
    );
  }

  Widget _buildProductCatalog(String symbol) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_layoutMode == ProductCatalogLayoutMode.list) {
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            itemCount: _catalog.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final product = _catalog[index];
              final line = _linesByProduct[product.id];
              return OrderCatalogListTile(
                product: product,
                currencySymbol: symbol,
                quantity: line?.quantity ?? 0,
                maxQuantity: _maxQuantityForProduct(product.id),
                onStockLimitReached: () => _onStockLimitReached(product.id),
                offlineStockHint: _offlineStockHint,
                reorderLevel: _settings.defaultReorderLevel,
                onAdd: () => _addProduct(product),
                onQuantityChanged: (qty) =>
                    _setLineQuantity(product.id, qty),
                onOpenPhotos: () => _openProductPhotos(product),
              );
            },
          );
        }

        final isLarge = _layoutMode == ProductCatalogLayoutMode.gridOne;
        final crossAxisCount = isLarge ? 1 : 2;
        final mainAxisExtent = isLarge ? 380.0 : 300.0;

        return GridView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: mainAxisExtent,
          ),
          itemCount: _catalog.length,
          itemBuilder: (context, index) {
            final product = _catalog[index];
            final line = _linesByProduct[product.id];
            return OrderCatalogGridCard(
              product: product,
              currencySymbol: symbol,
              quantity: line?.quantity ?? 0,
              large: isLarge,
              maxQuantity: _maxQuantityForProduct(product.id),
              onStockLimitReached: () => _onStockLimitReached(product.id),
              offlineStockHint: _offlineStockHint,
              reorderLevel: _settings.defaultReorderLevel,
              onAdd: () => _addProduct(product),
              onQuantityChanged: (qty) => _setLineQuantity(product.id, qty),
              onOpenPhotos: () => _openProductPhotos(product),
            );
          },
        );
      },
    );
  }

  Future<void> _openProductPhotos(ProductSummary product) async {
    await openSelloProductPhotoViewer(
      context,
      product: product,
      repository: ref.read(productRepositoryProvider),
    );
  }

  Widget _buildCartBar(String symbol) {
    final count = _lines.fold<num>(0, (sum, l) => sum + l.quantity);
    return Material(
      color: AppColors.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      child: InkWell(
        onTap: widget.embedded || _lines.isEmpty ? null : _goCheckout,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.panel),
            border: Border.all(color: AppColors.outlinePanel),
            color: _lines.isEmpty
                ? AppColors.surfaceMuted
                : context.brandAccentContainer.withValues(alpha: 0.45),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.brandAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${count.round()}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _lines.isEmpty
                      ? 'Basket'
                      : SelloFormatters.currency(_total, symbol: symbol),
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _lines.isEmpty
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (_lines.isNotEmpty && !widget.embedded)
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.brandAccent,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSidebar(String symbol) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Text(
                  'Order',
                  style: AppTypography.sectionTitle.copyWith(fontSize: 15),
                ),
                const Spacer(),
                Text(
                  SelloFormatters.currency(_total, symbol: symbol),
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: context.brandAccent,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.outlineSubtle),
          Expanded(
            flex: 5,
            child: _lines.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Added products appear here so you can adjust quantities without leaving the catalog.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      return _LineEditorTile(
                        line: line,
                        currencySymbol: symbol,
                        compact: true,
                        maxQuantity: _maxQuantityForProduct(line.productId),
                        onStockLimitReached: () =>
                            _onStockLimitReached(line.productId),
                        onQuantityChanged: (qty) =>
                            _setLineQuantity(line.productId, qty),
                        onRemove: () => _removeLine(line.productId),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.outlineSubtle),
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: _buildCheckoutBody(symbol, includeCustomer: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBody(String symbol, {required bool includeCustomer}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (includeCustomer) ...[
          if (_customer != null)
            _CustomerChipBar(
              customer: _customer!,
              currencySymbol: symbol,
              onChange: () {
                _clearCustomer();
                setState(() => _step = 0);
              },
            ),
          const SizedBox(height: 14),
          Text(
            '${_lines.length} product${_lines.length == 1 ? '' : 's'} · '
            '${SelloFormatters.currency(_total, symbol: symbol)}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _LineEditorTile(
              line: _lines[i],
              currencySymbol: symbol,
              maxQuantity: _maxQuantityForProduct(_lines[i].productId),
              onStockLimitReached: () =>
                  _onStockLimitReached(_lines[i].productId),
              onQuantityChanged: (qty) =>
                  _setLineQuantity(_lines[i].productId, qty),
              onRemove: () => _removeLine(_lines[i].productId),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SelloButton(
              label: 'Save draft',
              variant: SelloButtonVariant.outline,
              size: SelloButtonSize.small,
              onPressed: () => _submit(complete: false),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SelloDialogSection(
          title: 'Totals',
          children: [
            SelloFormRow(
              left: SelloTextField(
                controller: _orderDiscount,
                label: 'Order discount',
                hint: '0',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              right: const _TotalReadout(
                label: 'Tax',
                value: 'Reserved',
                muted: true,
              ),
            ),
            const SizedBox(height: 8),
            _TotalReadout(
              label: 'Subtotal',
              value: SelloFormatters.currency(_subtotal, symbol: symbol),
            ),
            const SizedBox(height: 8),
            _TotalReadout(
              label: 'Grand total',
              value: SelloFormatters.currency(_total, symbol: symbol),
              emphasize: true,
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
                for (final method in PaymentMethod.values
                    .where((m) => m != PaymentMethod.creditSettlement))
                  ChoiceChip(
                    label: Text(method.label),
                    selected: _paymentMethod == method,
                    onSelected: (selected) {
                      setState(() {
                        _paymentMethod = selected ? method : null;
                        _error = null;
                      });
                    },
                    selectedColor: context.brandAccentContainer,
                    labelStyle: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      color: _paymentMethod == method
                          ? context.brandAccent
                          : AppColors.textSecondary,
                    ),
                    side: BorderSide(
                      color: _paymentMethod == method
                          ? context.brandAccent.withValues(alpha: 0.35)
                          : AppColors.outlinePanel,
                    ),
                    backgroundColor: AppColors.surface,
                  ),
              ],
            ),
            if (_paymentMethod == PaymentMethod.credit &&
                _customer != null &&
                !_customer!.creditAllowed) ...[
              const SizedBox(height: 10),
              const Text(
                'Credit is not enabled for this customer.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  color: AppColors.warning,
                ),
              ),
            ],
          ],
        ),
        SelloDialogSection(
          title: 'Notes',
          bottomSpacing: 4,
          children: [
            SelloTextField(
              controller: _notes,
              label: 'Internal notes',
              hint: 'Note for warehouse or follow-up…',
              maxLines: 3,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Customer ───────────────────────────────────────────────────────────────

class _CustomerChipBar extends StatelessWidget {
  const _CustomerChipBar({
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
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.brandAccentContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              customer.name.isEmpty
                  ? '?'
                  : customer.name.trim()[0].toUpperCase(),
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
                color: context.brandAccent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (customer.phone != null) customer.phone!,
                    'Owes ${SelloFormatters.currency(customer.outstandingBalance, symbol: currencySymbol)}',
                    customer.creditAllowed ? 'Credit OK' : 'No credit',
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

// ── Catalog chrome ─────────────────────────────────────────────────────────

class _CatalogGate extends StatelessWidget {
  const _CatalogGate();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 40,
              color: AppColors.textFaint,
            ),
            SizedBox(height: 12),
            Text(
              'Select a customer to open the catalog',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Then browse products together — like a shop floor, not a form.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
  });

  final List<ProductCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, 'All', selectedId == null, () => onSelected(null)),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            _chip(
              context,
              category.name,
              selectedId == category.id,
              () => onSelected(category.id),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      showCheckmark: false,
      selectedColor: context.brandAccentContainer,
      labelStyle: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: selected ? context.brandAccent : AppColors.textSecondary,
      ),
      side: BorderSide(
        color: selected
            ? context.brandAccent.withValues(alpha: 0.35)
            : AppColors.outlinePanel,
      ),
      backgroundColor: AppColors.surface,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Reserved strip for future Sello Intelligence product suggestions.
class _IntelligenceSuggestionsStrip extends StatelessWidget {
  const _IntelligenceSuggestionsStrip();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 16,
            color: context.brandAccent,
          ),
          const SizedBox(width: AppSpacing.xs),
          const _SuggestionPill(label: 'Often ordered'),
          const SizedBox(width: 6),
          const _SuggestionPill(label: 'Repeat last order'),
          const SizedBox(width: 6),
          const _SuggestionPill(label: 'Suggested for them'),
        ],
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  const _SuggestionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.brandAccentContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label · soon',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: context.brandAccent,
        ),
      ),
    );
  }
}

// ── Lines / totals ───────────────────────────────────────────────────

class _LineEditorTile extends StatelessWidget {
  const _LineEditorTile({
    required this.line,
    required this.currencySymbol,
    required this.onQuantityChanged,
    required this.onRemove,
    this.compact = false,
    this.maxQuantity,
    this.onStockLimitReached,
  });

  final OrderLineDraft line;
  final String currencySymbol;
  final ValueChanged<num> onQuantityChanged;
  final VoidCallback onRemove;
  final bool compact;
  final num? maxQuantity;
  final VoidCallback? onStockLimitReached;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          SelloEntityThumb(
            name: line.productName,
            imageUrl: line.imageUrl,
            width: compact ? 40 : 44,
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 13 : 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  SelloFormatters.currency(
                    line.lineTotal,
                    symbol: currencySymbol,
                  ),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ProductQuantityControl(
            value: line.quantity,
            allowZero: true,
            showRemove: true,
            maxQuantity: maxQuantity,
            onIncreaseBlocked: onStockLimitReached,
            onChanged: onQuantityChanged,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

class _TotalReadout extends StatelessWidget {
  const _TotalReadout({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: emphasize ? 15 : 13.5,
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: emphasize ? 20 : 15,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            color: muted ? AppColors.textFaint : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
