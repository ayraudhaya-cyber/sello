import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/mobile/orders/application/sello_orders_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/orders/presentation/order_editor_dialog.dart';
import 'package:sello/features/payments/presentation/receive_payment_dialog.dart';
import 'package:sello/features/payments/presentation/record_cheque_dialog.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/features/visits/application/visit_checkout_payment_rules.dart';
import 'package:sello/features/visits/presentation/signature_pad.dart';
import 'package:sello/features/visits/presentation/visit_basket_bar.dart';
import 'package:sello/features/visits/presentation/visit_basket_sheet.dart';
import 'package:sello/features/visits/presentation/visit_customer_context_header.dart';
import 'package:sello/features/visits/presentation/visit_customer_details_sheet.dart';
import 'package:sello/features/visits/presentation/visit_draft_restore_banner.dart';
import 'package:sello/features/visits/presentation/visit_order_status_banner.dart';
import 'package:sello/features/visits/presentation/visit_checkout_stage.dart';
import 'package:sello/features/visits/presentation/walk_in_customer_sheet.dart';
import 'package:sello/services/orders/visit_order_draft.dart';
import 'package:sello/services/orders/visit_order_draft_store.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

enum _VisitStage { catalog, checkout }

/// Field sales visit — catalog, then checkout.
///
/// Reuses [OrderEditorDialog] basket/pricing, [selloOrdersProvider],
/// [PaymentRepository], and [VisitRepository]. No parallel domain logic.
///
/// Walk-in opens the catalog with no customer row. Registration happens only
/// when the buyer decides to purchase.
class CustomerVisitWorkspacePage extends ConsumerStatefulWidget {
  const CustomerVisitWorkspacePage({
    super.key,
    this.customerId,
    this.scheduledVisitId,
    this.customerName,
    this.walkIn = false,
  });

  final String? customerId;
  final String? scheduledVisitId;
  final String? customerName;

  /// Catalog-first discovery — no customer until purchase.
  final bool walkIn;

  @override
  ConsumerState<CustomerVisitWorkspacePage> createState() =>
      _CustomerVisitWorkspacePageState();
}

class _CustomerVisitWorkspacePageState
    extends ConsumerState<CustomerVisitWorkspacePage> {
  final _orderKey = GlobalKey<OrderEditorDialogState>();
  final _signatureKey = GlobalKey<SelloSignaturePadState>();
  final _visitNotes = TextEditingController();
  final _orderDiscount = TextEditingController();
  final _orderDiscountPercent = TextEditingController();
  final _discountAmountFocus = FocusNode();
  final _discountPercentFocus = FocusNode();

  CustomerSummary? _customer;
  bool _booting = true;
  String? _bootError;
  int _basketCount = 0;
  num _basketQty = 0;
  num _basketTotal = 0;
  num _basketSavings = 0;
  bool _orderSubmitted = false;
  String? _savedVisitOrderId;
  _VisitStage _stage = _VisitStage.catalog;
  VisitPaymentArrangement _arrangement = VisitPaymentArrangement.noneYet;
  DateTime? _chequeFollowUpDate;
  bool _saving = false;
  bool _signed = false;
  late bool _isWalkIn;
  final _draftStore = VisitOrderDraftStore();
  VisitOrderDraft? _pendingDraft;

  @override
  void initState() {
    super.initState();
    _isWalkIn = widget.walkIn;
    _visitNotes.addListener(_onVisitNotesChanged);
    _orderDiscount.addListener(_onDiscountChanged);
    _orderDiscountPercent.addListener(_onDiscountChanged);
    _bindZeroClear(_discountAmountFocus, _orderDiscount);
    _bindZeroClear(_discountPercentFocus, _orderDiscountPercent);
    Future.microtask(_bootstrap);
  }

  void _onVisitNotesChanged() {
    unawaited(_persistDraft());
  }

  void _bindZeroClear(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (!node.hasFocus) return;
      final text = controller.text.trim();
      if (text == '0' || text == '0.0' || text == '0.00') {
        controller.clear();
      }
    });
  }

  void _onDiscountChanged() {
    _orderKey.currentState?.setOrderDiscounts(
      amount: num.tryParse(_orderDiscount.text.trim()) ?? 0,
      percent: num.tryParse(_orderDiscountPercent.text.trim()) ?? 0,
    );
    _syncBasketFromEditor();
    unawaited(_persistDraft());
  }

  @override
  void dispose() {
    _visitNotes.removeListener(_onVisitNotesChanged);
    _orderDiscount.removeListener(_onDiscountChanged);
    _orderDiscountPercent.removeListener(_onDiscountChanged);
    _visitNotes.dispose();
    _orderDiscount.dispose();
    _orderDiscountPercent.dispose();
    _discountAmountFocus.dispose();
    _discountPercentFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });
    try {
      final active = ref.read(activeCustomerVisitProvider).valueOrNull;

      // Walk-in: open catalog immediately — no visit or customer row yet.
      if (_isWalkIn &&
          (widget.customerId == null || widget.customerId!.isEmpty)) {
        if (active != null) {
          setState(() {
            _booting = false;
            _bootError =
                'Finish or leave your current visit before starting a walk-in.';
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _customer = null;
          _booting = false;
        });
        await _loadPendingDraft();
        return;
      }

      final customerId = widget.customerId ?? active?.customerId;
      if (customerId == null || customerId.isEmpty) {
        setState(() {
          _booting = false;
          _bootError =
              'Pick a customer from your list, or start a New Walk-in.';
        });
        return;
      }

      final customerFuture = ref
          .read(customerRepositoryProvider)
          .fetchById(customerId);
      if (active == null || active.customerId != customerId) {
        await ref
            .read(activeCustomerVisitProvider.notifier)
            .startVisit(
              customerId: customerId,
              scheduledVisitId: widget.scheduledVisitId,
              customerName: widget.customerName,
            );
      }

      final customer = await customerFuture;
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _isWalkIn = false;
        _booting = false;
      });
      await _loadPendingDraft();
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _bootError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _bootError = 'Unable to open this visit. Try again from Customers.';
      });
    }
  }

  String? _branchIdFor(AppSession session) =>
      session.branch?.id ?? session.employee.branchId;

  Future<CustomerSummary?> _registerWalkInCustomer() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;

    final sheetInput = await WalkInCustomerSheet.show(context);
    if (sheetInput == null || !mounted) return null;

    // The sale is completed on account first. Paid today collects against
    // that balance in the payment dialog; credit and cheque stay outstanding.
    final input = CustomerUpsertInput(
      name: sheetInput.name,
      customerType: sheetInput.customerType,
      creditAllowed: true,
      creditLimit: sheetInput.creditLimit,
      openingBalance: sheetInput.openingBalance,
      code: sheetInput.code,
      companyName: sheetInput.companyName,
      phone: sheetInput.phone,
      whatsapp: sheetInput.whatsapp,
      email: sheetInput.email,
      addressLine1: sheetInput.addressLine1,
      city: sheetInput.city,
      taxNumber: sheetInput.taxNumber,
      notes: sheetInput.notes,
      isActive: sheetInput.isActive,
    );

    final branchId = _branchIdFor(session);

    final customerId = await ref
        .read(customerRepositoryProvider)
        .upsertCustomer(
          companyId: session.company.id,
          employeeId: session.employee.id,
          branchId: branchId,
          input: input,
        );

    await ref
        .read(activeCustomerVisitProvider.notifier)
        .startVisit(
          customerId: customerId,
          customerName: input.name,
          branchId: branchId,
        );

    final customer = await ref
        .read(customerRepositoryProvider)
        .fetchById(customerId);
    if (customer == null) {
      throw const UnexpectedFailure('Customer was created but could not load.');
    }

    _orderKey.currentState?.bindCustomer(customer);
    if (!mounted) return customer;
    setState(() {
      _customer = customer;
      _isWalkIn = false;
    });
    return customer;
  }

  bool _draftMatchesContext(VisitOrderDraft draft) {
    final customerId = _customer?.id ?? widget.customerId;
    if (draft.walkIn && _isWalkIn) {
      if (_customer == null && draft.customerId == null) return true;
      if (_customer != null &&
          draft.customerId != null &&
          draft.customerId == _customer!.id) {
        return true;
      }
    }
    if (customerId != null &&
        draft.customerId != null &&
        draft.customerId == customerId) {
      return true;
    }
    return false;
  }

  Future<void> _loadPendingDraft() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    final draft = await _draftStore.load(
      companyId: session.company.id,
      employeeId: session.employee.id,
    );
    if (!mounted) return;
    if (draft == null || !draft.hasLines || !_draftMatchesContext(draft)) {
      return;
    }
    final editor = _orderKey.currentState;
    if (editor != null && editor.lines.isNotEmpty) {
      return;
    }
    setState(() => _pendingDraft = draft);
    // Home "Continue" only restores the visit/customer. Cart is local — put
    // lines back automatically once the order editor is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoRestoreDraftIfNeeded());
    });
  }

  Future<void> _autoRestoreDraftIfNeeded() async {
    if (!mounted || _pendingDraft == null) return;
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted || _pendingDraft == null) return;
      final editor = _orderKey.currentState;
      if (editor != null) {
        if (editor.lines.isNotEmpty) return;
        final expected = _pendingDraft!.lines.length;
        await _continueDraft(announce: true, expectedLines: expected);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _persistDraft() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    final editor = _orderKey.currentState;
    final lines = editor?.lines ?? [];
    final hasMeta =
        _visitNotes.text.trim().isNotEmpty ||
        _stage == _VisitStage.checkout ||
        _arrangement != VisitPaymentArrangement.noneYet;

    if (lines.isEmpty && !hasMeta) {
      await _draftStore.clear(
        companyId: session.company.id,
        employeeId: session.employee.id,
      );
      return;
    }

    final draft = VisitOrderDraft(
      companyId: session.company.id,
      employeeId: session.employee.id,
      customerId: _customer?.id,
      customerName: _customer?.name ?? widget.customerName,
      walkIn: _isWalkIn,
      scheduledVisitId: widget.scheduledVisitId,
      lines: [
        for (final line in lines)
          VisitOrderDraftLine(
            productId: line.productId,
            variantId: line.variantId,
            quantity: line.quantity,
          ),
      ],
      visitNotes: _visitNotes.text.trim().isEmpty
          ? null
          : _visitNotes.text.trim(),
      stage: _stage == _VisitStage.checkout
          ? VisitOrderDraftStage.checkout
          : VisitOrderDraftStage.catalog,
      arrangement: _arrangement.name,
      chequeFollowUpAt: _chequeFollowUpDate,
      updatedAt: DateTime.now(),
      runningTotal: editor?.runningTotal ?? 0,
      orderDiscount: num.tryParse(_orderDiscount.text.trim()) ?? 0,
      orderDiscountPercent:
          num.tryParse(_orderDiscountPercent.text.trim()) ?? 0,
    );
    await _draftStore.save(draft);
  }

  Future<void> _continueDraft({
    bool announce = false,
    int? expectedLines,
  }) async {
    final draft = _pendingDraft;
    if (draft == null) return;
    final restored = await _orderKey.currentState?.restoreFromProductLines([
      for (final line in draft.lines)
        (
          productId: line.productId,
          variantId: line.variantId,
          quantity: line.quantity,
        ),
    ]);
    if (draft.visitNotes != null && draft.visitNotes!.isNotEmpty) {
      _visitNotes.text = draft.visitNotes!;
    }
    if (draft.arrangement != null) {
      _arrangement = VisitPaymentArrangement.values.firstWhere(
        (value) => value.name == draft.arrangement,
        orElse: () => VisitPaymentArrangement.noneYet,
      );
    }
    _chequeFollowUpDate = draft.chequeFollowUpAt;
    _orderDiscount.text = draft.orderDiscount == 0
        ? ''
        : draft.orderDiscount.toString();
    _orderDiscountPercent.text = draft.orderDiscountPercent == 0
        ? ''
        : draft.orderDiscountPercent.toString();
    _orderKey.currentState?.setOrderDiscounts(
      amount: draft.orderDiscount,
      percent: draft.orderDiscountPercent,
    );
    if (draft.stage == VisitOrderDraftStage.checkout && (restored ?? 0) > 0) {
      _stage = _VisitStage.checkout;
    }
    setState(() => _pendingDraft = null);
    _syncBasketFromEditor();
    await _persistDraft();
    if (!mounted) return;
    if (restored == 0 && draft.lines.isNotEmpty) {
      SelloSnackbars.warning(
        context,
        'Some products from your draft could not be loaded.',
      );
      return;
    }
    if (announce && (restored ?? 0) > 0) {
      final count = restored ?? 0;
      final partial = expectedLines != null && count < expectedLines;
      SelloSnackbars.success(
        context,
        partial
            ? 'Order restored · $count of $expectedLines items'
            : 'Order restored · $count items',
      );
    }
  }

  Future<void> _confirmDiscardDraft() async {
    final shopName = _isWalkIn && _customer == null
        ? 'Walk-in'
        : (_customer?.name ?? widget.customerName ?? 'this customer');
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Discard order?',
      message:
          'This removes the current draft for $shopName. '
          'It can’t be undone.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final session = ref.read(currentSessionProvider);
    if (session != null) {
      await _draftStore.clear(
        companyId: session.company.id,
        employeeId: session.employee.id,
      );
    }
    _orderKey.currentState?.clearBasket();
    _visitNotes.clear();
    _arrangement = VisitPaymentArrangement.noneYet;
    _chequeFollowUpDate = null;
    _stage = _VisitStage.catalog;
    setState(() {
      _pendingDraft = null;
      _basketCount = 0;
      _basketQty = 0;
      _basketTotal = 0;
    });
    if (mounted) {
      SelloSnackbars.success(context, 'Draft discarded.');
    }
  }

  void _openCustomerDetails() {
    final settings =
        ref.read(selloCompanySettingsProvider).valueOrNull ??
        CompanySettings.defaults;
    final active = ref.read(activeCustomerVisitProvider).valueOrNull;
    final shopName = _isWalkIn && _customer == null
        ? 'Walk-in'
        : (_customer?.name ?? widget.customerName ?? 'Customer');
    final hasDraft = _basketCount > 0 || _pendingDraft != null;

    showVisitCustomerDetailsSheet(
      context,
      shopName: shopName,
      customer: _customer,
      activeVisit: active,
      currencySymbol: _currency,
      showOutstanding: settings.salesCanViewOutstandingBalances,
      onDiscardOrder: hasDraft ? _confirmDiscardDraft : null,
    );
  }

  Future<void> _leaveWithoutSaving() async {
    final orderState = _orderKey.currentState;
    final hasLines = orderState?.lines.isNotEmpty ?? false;
    final active = ref.read(activeCustomerVisitProvider).valueOrNull;

    if (hasLines) {
      await _persistDraft();
      if (!mounted) return;
      final leave = await showSelloDialog(
        context: context,
        title: 'Order in progress',
        message:
            'Your basket is saved on this device. '
            'You can continue it next time you open this customer.',
        confirmLabel: 'Leave',
        cancelLabel: 'Stay',
      );
      if (leave != true || !mounted) return;
    }

    if (_isWalkIn && active == null && !hasLines) {
      context.go(RoutePaths.selloCustomers);
      return;
    }

    context.go(RoutePaths.selloCustomers);
  }

  void _syncBasketFromEditor() {
    final editor = _orderKey.currentState;
    final count = editor?.lines.length ?? 0;
    final qty = editor?.itemQuantity ?? 0;
    final total = editor?.runningTotal ?? 0;
    final savings = editor?.discountSavings ?? 0;
    if (_basketCount == count &&
        _basketQty == qty &&
        _basketTotal == total &&
        _basketSavings == savings) {
      return;
    }
    setState(() {
      _basketCount = count;
      _basketQty = qty;
      _basketTotal = total;
      _basketSavings = savings;
      if (count == 0) {
        _stage = _VisitStage.catalog;
      }
      if (count > 0 && _pendingDraft != null) {
        _pendingDraft = null;
      }
    });
    unawaited(_persistDraft());
  }

  Future<void> _openBasketReview({bool fromCheckout = false}) async {
    final continueToCheckout = await showVisitBasketSheet(
      context: context,
      orderKey: _orderKey,
      currencySymbol: _currency,
    );
    if (!mounted) return;
    _syncBasketFromEditor();
    if (fromCheckout) return;
    if (continueToCheckout == true && _basketCount > 0) {
      setState(() => _stage = _VisitStage.checkout);
    }
  }

  void _goCheckout() {
    if (_basketCount <= 0) return;
    setState(() => _stage = _VisitStage.checkout);
  }

  void _goCatalog() => setState(() => _stage = _VisitStage.catalog);

  void _handleSystemBack() {
    if (_stage == _VisitStage.checkout) {
      _goCatalog();
      return;
    }
    _leaveWithoutSaving();
  }

  String get _currency {
    return ref.watch(selloCurrencySymbolProvider);
  }

  Future<void> _finishVisit() async {
    if (_saving) return;
    final orderState = _orderKey.currentState;
    final hasLines = orderState?.lines.isNotEmpty ?? false;

    // Walk-in, no purchase: discard — never create a customer.
    if (_isWalkIn && _customer == null && !hasLines) {
      if (!mounted) return;
      context.go(RoutePaths.selloCustomers);
      return;
    }

    if (hasLines && !_signed) {
      SelloSnackbars.error(
        context,
        'Ask the buyer to review and sign before finishing.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_customer == null && hasLines) {
        final registered = await _registerWalkInCustomer();
        if (registered == null) {
          setState(() => _saving = false);
          return;
        }
      }

      final visit = ref.read(activeCustomerVisitProvider).valueOrNull;
      final customer = _customer;
      if (visit == null || customer == null) {
        setState(() => _saving = false);
        if (mounted) {
          SelloSnackbars.error(context, 'Visit is not ready yet. Try again.');
        }
        return;
      }

      OrderConfirmationOutcome? confirmation;
      if (!_orderSubmitted && hasLines && orderState != null) {
        orderState.setOrderDiscounts(
          amount: num.tryParse(_orderDiscount.text.trim()) ?? 0,
          percent: num.tryParse(_orderDiscountPercent.text.trim()) ?? 0,
        );
        final result = orderState.tryBuildResult(place: true);
        if (result == null) {
          setState(() => _saving = false);
          return;
        }
        final draft = result.input;
        if (!customer.creditAllowed) {
          final session = ref.read(currentSessionProvider);
          final employeeId = session?.employee.id;
          if (employeeId == null || employeeId.isEmpty) {
            throw const ValidationFailure('No active session found.');
          }
          await ref
              .read(customerRepositoryProvider)
              .allowOnAccount(customerId: customer.id, employeeId: employeeId);
        }
        // Record demand (placed). Delivery is a separate step and is what
        // marks the order completed and moves stock.
        final input = OrderUpsertInput(
          orderId: draft.orderId,
          customerId: draft.customerId,
          lines: draft.lines,
          notes: draft.notes,
          paymentMethod: PaymentMethod.credit,
          paymentStatus: PaymentStatus.unpaid,
          orderDiscount: draft.orderDiscount,
          orderDiscountPercent: draft.orderDiscountPercent,
          taxAmount: draft.taxAmount,
          status: draft.status,
          visitId: visit.isLocalOnly ? null : visit.id,
          offlineClientId: draft.offlineClientId,
        );
        final saved = await ref
            .read(selloOrdersProvider.notifier)
            .saveOrder(input, place: true, reloadList: false);
        if (!saved.isOk) {
          if (!mounted) return;
          setState(() => _saving = false);
          final error = saved.error ?? 'Unable to save this order.';
          if (error.toLowerCase().contains('stock')) {
            await _orderKey.currentState?.refreshCatalogStock();
            if (!mounted) return;
            await showSelloDialog(
              context: context,
              title: 'Stock changed',
              message: '$error Adjust quantities and try again.',
              confirmLabel: 'OK',
              cancelLabel: 'Close',
            );
          } else {
            SelloSnackbars.error(context, error);
          }
          return;
        }
        _orderSubmitted = true;
        _savedVisitOrderId = saved.orderId;
        confirmation = saved.confirmation;
      }

      if (_arrangement == VisitPaymentArrangement.paidToday) {
        if (!mounted) return;
        final payment = await showDialog<ReceivePaymentInput>(
          context: context,
          builder: (_) => ReceivePaymentDialog(
            currencySymbol: _currency,
            visitId: visit.isLocalOnly ? null : visit.id,
            initialCustomer: customer,
            preferredOrderId: _savedVisitOrderId,
          ),
        );
        if (!mounted) return;
        if (payment != null) {
          final result = await ref
              .read(paymentRepositoryProvider)
              .receivePayment(payment);
          if (!mounted) return;
          if (result.isPendingReview) {
            await presentCollectionAcknowledgement(
              context,
              result.acknowledgement,
            );
          }
        }
      }

      var skippedOptionalCheque = false;
      if (VisitCheckoutPaymentRules.shouldOpenRecordCheque(_arrangement)) {
        if (!mounted) return;
        final chequeInput = await showDialog<CreateChequeInput>(
          context: context,
          barrierDismissible: true,
          builder: (_) => RecordChequeDialog(
            currencySymbol: _currency,
            visitId: visit.isLocalOnly ? null : visit.id,
            initialCustomer: customer,
            markCollected: true,
            recordingIsOptional: true,
            preferredOrderId:
                VisitCheckoutPaymentRules.preferredOrderIdForCheque(
                  arrangement: _arrangement,
                  createdOrderId: _savedVisitOrderId,
                ),
          ),
        );
        if (!mounted) return;
        if (VisitCheckoutPaymentRules.shouldCreateChequeRecord(
          arrangement: _arrangement,
          recordChequeSubmitted: chequeInput != null,
        )) {
          try {
            await ref.read(chequeRepositoryProvider).createCheque(chequeInput!);
          } on AppFailure catch (failure) {
            if (!mounted) return;
            SelloSnackbars.error(context, failure.message);
            skippedOptionalCheque = true;
          }
        } else {
          skippedOptionalCheque = true;
        }
      }

      // Cheque later: arrangement note only — no Record cheque, no ledger row,
      // no scheduled follow-up visit, no forced date.

      final signaturePath = _signed
          ? 'pending:visit-signature:${visit.id}:${DateTime.now().millisecondsSinceEpoch}'
          : null;

      final outcome = hasLines
          ? VisitOutcome.orderCreated
          : VisitCheckoutPaymentRules.resolveOutcomeWithoutOrder(_arrangement);

      final noteParts = <String>[
        if (_visitNotes.text.trim().isNotEmpty) _visitNotes.text.trim(),
        ...VisitCheckoutPaymentRules.arrangementNoteLines(
          arrangement: _arrangement,
          expectedChequeDate: _chequeFollowUpDate,
          formatDate: SelloFormatters.date,
        ),
      ];

      final completed = await ref
          .read(activeCustomerVisitProvider.notifier)
          .completeVisit(
            outcome: outcome,
            notes: noteParts.isEmpty ? null : noteParts.join('\n'),
            signatureStoragePath: signaturePath,
          );
      if (!completed.pendingSync) {
        await ref.read(activeCustomerVisitProvider.notifier).reload();
        final stillOpen = ref.read(activeCustomerVisitProvider).valueOrNull;
        if (stillOpen != null && stillOpen.isActive) {
          throw const ValidationFailure(
            'The visit is still open. Submit again to close it.',
          );
        }
      }

      final session = ref.read(currentSessionProvider);
      if (session != null) {
        await _draftStore.clear(
          companyId: session.company.id,
          employeeId: session.employee.id,
        );
      }

      if (!mounted) return;
      SelloSnackbars.success(
        context,
        VisitCheckoutPaymentRules.visitSavedMessage(
          arrangement: _arrangement,
          hasLines: hasLines,
          skippedOptionalCheque: skippedOptionalCheque,
        ),
      );
      if (confirmation != null && confirmation.hasShareActions && mounted) {
        await showOrderConfirmationShareSheet(context, confirmation);
      } else if (confirmation?.customerWasSkipped == true && mounted) {
        SelloSnackbars.warning(context, confirmation!.customerSkippedReason!);
      }
      if (!mounted) return;
      context.go(RoutePaths.selloDashboard);
    } on AppFailure catch (error) {
      if (!mounted) return;
      if (error.message.toLowerCase().contains('already finished')) {
        context.go(RoutePaths.selloDashboard);
        return;
      }
      SelloSnackbars.error(context, error.message);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to finish this visit.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickChequeDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _chequeFollowUpDate ?? now,
    );
    if (picked == null) return;
    setState(() => _chequeFollowUpDate = picked);
    unawaited(_persistDraft());
  }

  void _clearChequeDate() {
    setState(() => _chequeFollowUpDate = null);
    unawaited(_persistDraft());
  }

  @override
  Widget build(BuildContext context) {
    // Keep currency in sync when company settings resolve (LKR vs USD).
    ref.watch(selloCompanySettingsProvider);
    final active = ref.watch(activeCustomerVisitProvider).valueOrNull;

    final shopName = _isWalkIn && _customer == null
        ? 'Walk-in'
        : (_customer?.name ?? widget.customerName ?? 'Customer');
    final onCheckout = _stage == _VisitStage.checkout;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceMuted,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: _booting
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : _bootError != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelloStateView.error(
                    title: 'Visit unavailable',
                    message: _bootError,
                    actionLabel: 'Back to customers',
                    onAction: () => context.go(RoutePaths.selloCustomers),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (onCheckout)
                      _VisitCheckoutAppBar(onBack: _goCatalog)
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xxs,
                          AppSpacing.xxs,
                          AppSpacing.sm,
                          0,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _leaveWithoutSaving,
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Leave',
                            ),
                            Expanded(
                              child: VisitCustomerContextHeader(
                                shopName: shopName,
                                onTap: _openCustomerDetails,
                              ),
                            ),
                          ],
                        ),
                      ),
                    VisitOrderStatusBanner(
                      visitPendingSync: active?.pendingSync ?? false,
                    ),
                    if (!onCheckout && _pendingDraft != null)
                      VisitDraftRestoreBanner(
                        itemQuantity: _pendingDraft!.itemQuantity,
                        total: _pendingDraft!.runningTotal,
                        currencySymbol: _currency,
                        onContinue: _continueDraft,
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          Offstage(
                            offstage: onCheckout,
                            child: TickerMode(
                              enabled: !onCheckout,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: OrderEditorDialog(
                                  key: _orderKey,
                                  embedded: true,
                                  visitMode: true,
                                  hideCustomerPicker: true,
                                  hideEmptyBasket: true,
                                  hideCartBar: true,
                                  currencySymbol: _currency,
                                  visitId: active == null || active.isLocalOnly
                                      ? null
                                      : active.id,
                                  initialCustomerId: _customer?.id,
                                  initialCustomerName: _customer?.name,
                                  onBasketChanged: (_) {
                                    _syncBasketFromEditor();
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (onCheckout)
                            VisitCheckoutStage(
                              shopName: shopName,
                              itemQuantity:
                                  _orderKey.currentState?.itemQuantity ??
                                  _basketQty,
                              total:
                                  _orderKey.currentState?.runningTotal ??
                                  _basketTotal,
                              savings:
                                  _orderKey.currentState?.discountSavings ??
                                  _basketSavings,
                              currencySymbol: _currency,
                              discountAmount: _orderDiscount,
                              discountPercent: _orderDiscountPercent,
                              discountAmountFocus: _discountAmountFocus,
                              discountPercentFocus: _discountPercentFocus,
                              arrangement: _arrangement,
                              chequeDate: _chequeFollowUpDate,
                              onArrangementChanged: (value) {
                                setState(() {
                                  _arrangement = value;
                                  if (!value.allowsOptionalExpectedDate) {
                                    _chequeFollowUpDate = null;
                                  }
                                });
                                unawaited(_persistDraft());
                              },
                              onPickChequeDate: _pickChequeDate,
                              onClearChequeDate: _clearChequeDate,
                              onViewDetails: () =>
                                  _openBasketReview(fromCheckout: true),
                              notes: _visitNotes,
                              signatureKey: _signatureKey,
                              signed: _signed,
                              onSignedChanged: (signed) =>
                                  setState(() => _signed = signed),
                              saving: _saving,
                              onConfirm: _finishVisit,
                            ),
                        ],
                      ),
                    ),
                    if (!onCheckout && _basketCount > 0)
                      VisitCatalogFooter(
                        itemQuantity: _basketQty,
                        total: _basketTotal,
                        currencySymbol: _currency,
                        onReviewBasket: _openBasketReview,
                        onContinue: _goCheckout,
                      )
                    else if (!onCheckout)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          AppSpacing.md,
                        ),
                        child: TextButton(
                          onPressed: _saving ? null : _finishVisit,
                          child: Text(
                            _isWalkIn && _customer == null
                                ? 'Leave'
                                : 'End visit',
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

class _VisitCheckoutAppBar extends StatelessWidget {
  const _VisitCheckoutAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          const Expanded(
            child: Text(
              'Checkout',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
