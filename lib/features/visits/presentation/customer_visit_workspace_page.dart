import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/mobile/orders/application/sello_orders_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/orders/presentation/order_editor_dialog.dart';
import 'package:sello/features/payments/presentation/receive_payment_dialog.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/features/visits/presentation/signature_pad.dart';
import 'package:sello/features/visits/presentation/visit_basket_bar.dart';
import 'package:sello/features/visits/presentation/visit_basket_sheet.dart';
import 'package:sello/features/visits/presentation/visit_checkout_stage.dart';
import 'package:sello/features/visits/presentation/walk_in_customer_sheet.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/scheduled_visit.dart';
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

  CustomerSummary? _customer;
  bool _booting = true;
  String? _bootError;
  bool _detailsExpanded = false;
  int _basketCount = 0;
  num _basketQty = 0;
  num _basketTotal = 0;
  _VisitStage _stage = _VisitStage.catalog;
  VisitPaymentArrangement _arrangement = VisitPaymentArrangement.noneYet;
  DateTime? _chequeFollowUpDate;
  bool _saving = false;
  bool _signed = false;
  late bool _isWalkIn;

  @override
  void initState() {
    super.initState();
    _isWalkIn = widget.walkIn;
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _visitNotes.dispose();
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

      if (active == null || active.customerId != customerId) {
        await ref
            .read(activeCustomerVisitProvider.notifier)
            .startVisit(
              customerId: customerId,
              scheduledVisitId: widget.scheduledVisitId,
              customerName: widget.customerName,
            );
      }

      final customer = await ref
          .read(customerRepositoryProvider)
          .fetchById(customerId);
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _isWalkIn = false;
        _booting = false;
      });
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

  Future<CustomerSummary?> _registerWalkInCustomer() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;

    final input = await WalkInCustomerSheet.show(context);
    if (input == null || !mounted) return null;

    final customerId = await ref
        .read(customerRepositoryProvider)
        .upsertCustomer(
          companyId: session.company.id,
          employeeId: session.employee.id,
          branchId: session.employee.branchId,
          input: input,
        );

    await ref
        .read(activeCustomerVisitProvider.notifier)
        .startVisit(
          customerId: customerId,
          customerName: input.name,
          branchId: session.employee.branchId,
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

  Future<void> _leaveWithoutSaving() async {
    final orderState = _orderKey.currentState;
    final hasLines = orderState?.lines.isNotEmpty ?? false;
    final active = ref.read(activeCustomerVisitProvider).valueOrNull;

    if (_isWalkIn && active == null) {
      if (hasLines) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Leave walk-in?'),
            content: const Text(
              'The basket will be discarded and no customer will be saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep browsing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
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
    if (_basketCount == count && _basketQty == qty && _basketTotal == total) {
      return;
    }
    setState(() {
      _basketCount = count;
      _basketQty = qty;
      _basketTotal = total;
      if (count == 0) {
        _stage = _VisitStage.catalog;
      }
    });
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
    final settings =
        ref.read(selloCompanySettingsProvider).valueOrNull ??
        CompanySettings.defaults;
    return SelloFormatters.currencySymbol(settings.currency);
  }

  Future<void> _scheduleChequeFollowUp() async {
    final session = ref.read(currentSessionProvider);
    final customer = _customer;
    final when = _chequeFollowUpDate;
    if (session == null || customer == null || when == null) return;

    await ref
        .read(visitRepositoryProvider)
        .upsertVisit(
          companyId: session.company.id,
          actorEmployeeId: session.employee.id,
          input: VisitUpsertInput(
            customerId: customer.id,
            employeeId: session.employee.id,
            branchId: session.employee.branchId,
            visitDate: when,
            priority: VisitPriority.high,
            purpose: 'Cheque collection',
            notes: 'Follow-up scheduled from visit — collect cheque.',
          ),
        );
  }

  Future<void> _finishVisit() async {
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
      if (hasLines && orderState != null) {
        final wantComplete =
            _arrangement == VisitPaymentArrangement.paidToday ||
            _arrangement == VisitPaymentArrangement.chequeReceived ||
            _arrangement == VisitPaymentArrangement.creditSale;
        final result = orderState.tryBuildResult(complete: wantComplete);
        if (result == null) {
          setState(() => _saving = false);
          return;
        }
        var input = result.input;
        if (_arrangement == VisitPaymentArrangement.creditSale) {
          input = OrderUpsertInput(
            orderId: input.orderId,
            customerId: input.customerId,
            lines: input.lines,
            notes: input.notes,
            paymentMethod: PaymentMethod.credit,
            paymentStatus: PaymentStatus.unpaid,
            orderDiscount: input.orderDiscount,
            taxAmount: input.taxAmount,
            status: input.status,
            visitId: visit.isLocalOnly ? null : visit.id,
            offlineClientId: input.offlineClientId,
          );
        } else if (input.visitId == null && !visit.isLocalOnly) {
          input = OrderUpsertInput(
            orderId: input.orderId,
            customerId: input.customerId,
            lines: input.lines,
            notes: input.notes,
            paymentMethod: input.paymentMethod,
            paymentStatus: input.paymentStatus,
            orderDiscount: input.orderDiscount,
            taxAmount: input.taxAmount,
            status: input.status,
            visitId: visit.id,
            offlineClientId: input.offlineClientId,
          );
        }
        final saved = await ref
            .read(selloOrdersProvider.notifier)
            .saveOrder(
              input,
              complete:
                  result.complete ||
                  _arrangement == VisitPaymentArrangement.creditSale,
              reloadList: false,
            );
        if (!saved.isOk) {
          if (!mounted) return;
          setState(() => _saving = false);
          SelloSnackbars.error(context, saved.error!);
          return;
        }
        confirmation = saved.confirmation;
      }

      if (_arrangement == VisitPaymentArrangement.paidToday ||
          _arrangement == VisitPaymentArrangement.chequeReceived) {
        if (!mounted) return;
        final payment = await showDialog<ReceivePaymentInput>(
          context: context,
          builder: (_) => ReceivePaymentDialog(
            currencySymbol: _currency,
            visitId: visit.isLocalOnly ? null : visit.id,
            initialCustomer: customer,
          ),
        );
        if (!mounted) return;
        if (payment != null) {
          final reference =
              _arrangement == VisitPaymentArrangement.chequeReceived
              ? (payment.reference == null || payment.reference!.trim().isEmpty
                    ? 'Cheque'
                    : 'Cheque · ${payment.reference}')
              : payment.reference;
          final result = await ref
              .read(paymentRepositoryProvider)
              .receivePayment(
                ReceivePaymentInput(
                  customerId: payment.customerId,
                  amount: payment.amount,
                  method: payment.method,
                  allocations: payment.allocations,
                  reference: reference,
                  notes: payment.notes,
                  visitId: payment.visitId,
                ),
              );
          if (!mounted) return;
          if (result.isPendingReview) {
            await presentCollectionAcknowledgement(
              context,
              result.acknowledgement,
            );
          }
        }
      }

      if (_arrangement.schedulesFollowUp) {
        _chequeFollowUpDate ??= DateTime.now().add(const Duration(days: 3));
        await _scheduleChequeFollowUp();
      }

      final signaturePath = _signed
          ? 'pending:visit-signature:${visit.id}:${DateTime.now().millisecondsSinceEpoch}'
          : null;

      final outcome = hasLines
          ? VisitOutcome.orderCreated
          : (_arrangement == VisitPaymentArrangement.paidToday ||
                    _arrangement == VisitPaymentArrangement.chequeReceived
                ? VisitOutcome.paymentCollected
                : (_arrangement.schedulesFollowUp
                      ? VisitOutcome.followUpRequired
                      : VisitOutcome.noOrderToday));

      final noteParts = <String>[
        if (_visitNotes.text.trim().isNotEmpty) _visitNotes.text.trim(),
        if (_arrangement != VisitPaymentArrangement.noneYet)
          'Payment: ${_arrangement.label}',
      ];

      await ref
          .read(activeCustomerVisitProvider.notifier)
          .completeVisit(
            outcome: outcome,
            notes: noteParts.isEmpty ? null : noteParts.join('\n'),
            signatureStoragePath: signaturePath,
          );

      if (!mounted) return;
      SelloSnackbars.success(context, 'Visit saved.');
      if (confirmation != null && confirmation.hasShareActions && mounted) {
        await showOrderConfirmationShareSheet(context, confirmation);
      } else if (confirmation?.customerWasSkipped == true && mounted) {
        SelloSnackbars.warning(context, confirmation!.customerSkippedReason!);
      }
      if (!mounted) return;
      context.go(RoutePaths.selloDashboard);
    } on AppFailure catch (error) {
      if (!mounted) return;
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
      initialDate: _chequeFollowUpDate ?? now.add(const Duration(days: 3)),
    );
    if (picked == null) return;
    setState(() => _chequeFollowUpDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeCustomerVisitProvider).valueOrNull;
    final settings =
        ref.watch(selloCompanySettingsProvider).valueOrNull ??
        CompanySettings.defaults;

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
                    _VisitAppBar(
                      customerName: onCheckout ? 'Checkout' : shopName,
                      durationLabel: onCheckout ? null : active?.durationLabel,
                      pendingSync: active?.pendingSync ?? false,
                      showBack: onCheckout,
                      onClose: onCheckout ? _goCatalog : _leaveWithoutSaving,
                    ),
                    if (!onCheckout && _customer != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.xs,
                        ),
                        child: _VisitActionHeader(
                          customer: _customer!,
                          currencySymbol: _currency,
                          showOutstanding:
                              settings.salesCanViewOutstandingBalances,
                          detailsExpanded: _detailsExpanded,
                          onToggleDetails: () => setState(
                            () => _detailsExpanded = !_detailsExpanded,
                          ),
                        ),
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
                                  onBasketChanged: (_) =>
                                      _syncBasketFromEditor(),
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
                              currencySymbol: _currency,
                              arrangement: _arrangement,
                              chequeDate: _chequeFollowUpDate,
                              onArrangementChanged: (value) => setState(() {
                                _arrangement = value;
                                if (value.schedulesFollowUp &&
                                    _chequeFollowUpDate == null) {
                                  _chequeFollowUpDate = DateTime.now().add(
                                    const Duration(days: 3),
                                  );
                                }
                              }),
                              onPickChequeDate: _pickChequeDate,
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

class _VisitAppBar extends StatelessWidget {
  const _VisitAppBar({
    required this.customerName,
    required this.onClose,
    this.durationLabel,
    this.pendingSync = false,
    this.showBack = false,
  });

  final String customerName;
  final String? durationLabel;
  final bool pendingSync;
  final bool showBack;
  final VoidCallback onClose;

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
            onPressed: onClose,
            icon: Icon(
              showBack ? Icons.arrow_back_rounded : Icons.close_rounded,
            ),
            tooltip: showBack ? 'Back' : 'Leave',
          ),
          Expanded(
            child: Text(
              customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
          if (pendingSync)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 16,
                color: AppColors.warning,
              ),
            ),
          if (durationLabel != null)
            Text(
              durationLabel!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact chips — details stay secondary.
class _VisitActionHeader extends StatelessWidget {
  const _VisitActionHeader({
    required this.customer,
    required this.currencySymbol,
    required this.showOutstanding,
    required this.detailsExpanded,
    required this.onToggleDetails,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final bool showOutstanding;
  final bool detailsExpanded;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (showOutstanding && customer.outstandingBalance > 0)
                    _MetaChip(
                      label: SelloFormatters.currency(
                        customer.outstandingBalance,
                        symbol: currencySymbol,
                      ),
                      emphasis: true,
                    ),
                  if (customer.phone != null) _MetaChip(label: customer.phone!),
                  if (customer.lastPurchaseAt != null)
                    _MetaChip(
                      label: DateFormat(
                        'd MMM',
                      ).format(customer.lastPurchaseAt!.toLocal()),
                    ),
                ],
              ),
            ),
            InkWell(
              onTap: onToggleDetails,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  detailsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        if (detailsExpanded) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (customer.createdAt != null)
                _MetaChip(
                  label: DateFormat(
                    'MMM yyyy',
                  ).format(customer.createdAt!.toLocal()),
                ),
              if (customer.addressLine1 != null || customer.city != null)
                _MetaChip(
                  label: [
                    if (customer.addressLine1 != null) customer.addressLine1!,
                    if (customer.city != null) customer.city!,
                  ].join(', '),
                ),
              _MetaChip(
                label: customer.creditAllowed
                    ? SelloFormatters.currency(
                        customer.creditLimit,
                        symbol: currencySymbol,
                      )
                    : 'Cash',
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.emphasis = false});
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: emphasis
            ? AppColors.warningContainer.withValues(alpha: 0.55)
            : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: emphasis ? AppColors.warning : AppColors.textSecondary,
        ),
      ),
    );
  }
}
