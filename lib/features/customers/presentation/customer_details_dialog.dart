import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:sello/shared/models/customer_receivable_adjustment.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Customer Workspace — relationship profile, not a plain info popup.
///
/// Shared by Hub (manage) and Sales (lookup). Pass [readOnly] for field sales
/// so edit/archive/delete stay Owner/Manager-only.
class CustomerDetailsDialog extends StatefulWidget {
  const CustomerDetailsDialog({
    super.key,
    required this.customer,
    this.onEdit,
    this.onToggleArchive,
    this.onDeletePermanently,
    this.onAddExistingCheque,
    this.onAddOpeningBalance,
    this.onCorrectOpeningBalance,
    this.openingBalanceHistoryEpoch = 0,
    this.readOnly = false,
    this.currencySymbol = '\$',
    this.assignedRepresentativeName,
    this.enableVisitActions = false,
    this.onNewOrder,
    this.onReceivePayment,
    this.onViewOrder,
    this.onReceiveOrderPayment,
  });

  final CustomerSummary customer;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleArchive;
  final VoidCallback? onDeletePermanently;
  final VoidCallback? onAddExistingCheque;
  final VoidCallback? onAddOpeningBalance;
  final Future<void> Function(CustomerReceivableAdjustment item)?
  onCorrectOpeningBalance;
  final int openingBalanceHistoryEpoch;
  final bool readOnly;
  final String currencySymbol;

  /// From employee customer assignments — not duplicated customer logic.
  final String? assignedRepresentativeName;

  /// Sales field actions: Start / Complete visit.
  final bool enableVisitActions;

  /// Hub shortcuts shown above the tabs (active customers only).
  final VoidCallback? onNewOrder;
  final VoidCallback? onReceivePayment;
  final Future<void> Function(OrderSummary order)? onViewOrder;
  final void Function(OrderSummary order)? onReceiveOrderPayment;

  @override
  State<CustomerDetailsDialog> createState() => _CustomerDetailsDialogState();
}

enum _CustomerDetailTab { overview, orders, visitHistory }

class _CustomerDetailsDialogState extends State<CustomerDetailsDialog> {
  static const double _sectionGap = 36;
  static const double _fieldGap = 18;

  _CustomerDetailTab _tab = _CustomerDetailTab.overview;

  CustomerSummary get customer => widget.customer;

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final canManage =
        !widget.readOnly &&
        widget.onEdit != null &&
        widget.onToggleArchive != null;

    return SelloFormDialog(
      header: _CustomerHero(customer: customer),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 36,
        isMobile ? 16 : 20,
        isMobile ? 20 : 36,
        16,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!customer.isActive) ...[
            const _ArchivedNotice(),
            const SizedBox(height: _sectionGap),
          ],
          if (widget.enableVisitActions)
            _FieldSalesFocus(
              customer: customer,
              currencySymbol: widget.currencySymbol,
              assignedRepresentativeName: widget.assignedRepresentativeName,
            )
          else ...[
            if (customer.isActive &&
                (widget.onNewOrder != null ||
                    widget.onReceivePayment != null)) ...[
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (widget.onNewOrder != null)
                    SelloButton(
                      label: 'New order',
                      icon: Icons.add_shopping_cart_rounded,
                      size: SelloButtonSize.small,
                      variant: SelloButtonVariant.outline,
                      onPressed: widget.onNewOrder,
                    ),
                  if (widget.onReceivePayment != null)
                    SelloButton(
                      label: 'Receive payment',
                      icon: Icons.payments_outlined,
                      size: SelloButtonSize.small,
                      variant: SelloButtonVariant.outline,
                      onPressed: widget.onReceivePayment,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _CustomerDetailTabs(
              tab: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
            const SizedBox(height: AppSpacing.mdPlus),
            switch (_tab) {
              _CustomerDetailTab.overview => _HubOverviewBody(
                customer: customer,
                currencySymbol: widget.currencySymbol,
                assignedRepresentativeName: widget.assignedRepresentativeName,
                readOnly: widget.readOnly,
                openingBalanceHistoryEpoch: widget.openingBalanceHistoryEpoch,
                onAddOpeningBalance: widget.onAddOpeningBalance,
                onCorrectOpeningBalance: widget.onCorrectOpeningBalance,
                onAddExistingCheque: widget.onAddExistingCheque,
                fieldGap: _fieldGap,
              ),
              _CustomerDetailTab.orders => _HubCustomerOrdersBody(
                customer: customer,
                currencySymbol: widget.currencySymbol,
                onNewOrder: widget.onNewOrder,
                onViewOrder: widget.onViewOrder,
                onReceivePayment: widget.onReceiveOrderPayment,
              ),
              _CustomerDetailTab.visitHistory => _HubVisitHistoryBody(
                customer: customer,
              ),
            },
          ],
        ],
      ),
      footer: canManage
          ? SelloDialogFooter(
              cancelLabel: customer.isActive ? 'Deactivate' : 'Reactivate',
              cancelVariant: SelloButtonVariant.ghost,
              cancelAtStart: true,
              onCancel: widget.onToggleArchive,
              primaryLabel: 'Edit Customer',
              onPrimary: widget.onEdit,
              destructiveLabel: customer.isActive ? null : 'Delete permanently',
              onDestructive: customer.isActive
                  ? null
                  : widget.onDeletePermanently,
            )
          : widget.enableVisitActions
          ? _SalesVisitFooter(customer: customer)
          : SelloDialogFooter(
              cancelLabel: 'Close',
              cancelVariant: SelloButtonVariant.outline,
              onCancel: () => Navigator.of(context).maybePop(),
              primaryLabel: 'New order',
              onPrimary: null,
              primaryEnabled: false,
            ),
    );
  }
}

class _CustomerDetailTabs extends StatelessWidget {
  const _CustomerDetailTabs({required this.tab, required this.onChanged});

  final _CustomerDetailTab tab;
  final ValueChanged<_CustomerDetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlinePanel)),
      ),
      child: Row(
        children: [
          _tab(context, 'Overview', _CustomerDetailTab.overview),
          const SizedBox(width: AppSpacing.lg),
          _tab(context, 'Orders', _CustomerDetailTab.orders),
          const SizedBox(width: AppSpacing.lg),
          _tab(context, 'Visit History', _CustomerDetailTab.visitHistory),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, _CustomerDetailTab value) {
    final selected = tab == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10, right: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            AnimatedContainer(
              duration: AppDurations.fast,
              curve: AppCurves.standard,
              height: 2,
              color: selected ? context.brandAccent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _HubOverviewBody extends ConsumerStatefulWidget {
  const _HubOverviewBody({
    required this.customer,
    required this.currencySymbol,
    required this.readOnly,
    required this.openingBalanceHistoryEpoch,
    required this.fieldGap,
    this.assignedRepresentativeName,
    this.onAddOpeningBalance,
    this.onCorrectOpeningBalance,
    this.onAddExistingCheque,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final String? assignedRepresentativeName;
  final bool readOnly;
  final int openingBalanceHistoryEpoch;
  final VoidCallback? onAddOpeningBalance;
  final Future<void> Function(CustomerReceivableAdjustment item)?
  onCorrectOpeningBalance;
  final VoidCallback? onAddExistingCheque;
  final double fieldGap;

  @override
  ConsumerState<_HubOverviewBody> createState() => _HubOverviewBodyState();
}

class _HubOverviewBodyState extends ConsumerState<_HubOverviewBody> {
  static const _sectionGap = 22.0;

  List<CustomerReceivableAdjustment> _adjustments = const [];
  bool _adjustmentsLoading = true;
  bool _adjustmentsFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdjustments());
  }

  @override
  void didUpdateWidget(covariant _HubOverviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.id != widget.customer.id ||
        oldWidget.openingBalanceHistoryEpoch !=
            widget.openingBalanceHistoryEpoch) {
      _loadAdjustments();
    }
  }

  Future<void> _loadAdjustments() async {
    setState(() {
      _adjustmentsLoading = true;
      _adjustmentsFailed = false;
    });
    try {
      final items = await ref
          .read(customerRepositoryProvider)
          .fetchOpeningBalanceAdjustments(widget.customer.id);
      if (!mounted) return;
      setState(() {
        _adjustments = items;
        _adjustmentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adjustments = const [];
        _adjustmentsLoading = false;
        _adjustmentsFailed = true;
      });
    }
  }

  ({String? label, SelloStatusTone? tone}) get _openingStatus {
    final original = _adjustments.fold<num>(
      0,
      (total, item) => total + item.amount,
    );
    final remaining = _adjustments.fold<num>(
      0,
      (total, item) => total + item.remaining,
    );
    if (original <= 0.001 || remaining + 0.001 >= original) {
      return (label: null, tone: null);
    }
    if (remaining <= 0.001) {
      return (label: 'Collected', tone: SelloStatusTone.success);
    }
    return (label: 'Partially collected', tone: SelloStatusTone.warning);
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final currencySymbol = widget.currencySymbol;
    final fieldGap = widget.fieldGap;
    final status = _adjustmentsFailed ? null : _openingStatus;
    final hasFinancialActions =
        widget.onAddOpeningBalance != null ||
        widget.onAddExistingCheque != null;
    final company = _distinctCompanyName(customer);
    final customerFields = <Widget>[
      if (customer.createdAt != null)
        _ProfileField(
          label: 'Customer since',
          value: SelloFormatters.date(customer.createdAt),
        ),
      _ProfileField(label: 'Type', value: customer.customerType.label),
      if (customer.lastPurchaseAt != null)
        _ProfileField(
          label: 'Last purchase',
          value: SelloFormatters.date(customer.lastPurchaseAt),
        ),
      if (company != null) _ProfileField(label: 'Company', value: company),
    ];
    final contactFields = _contactFields(customer);
    final relationshipFields = _relationshipFields(customer);
    final notes = customer.notes?.trim();
    final showNotes = notes != null && notes.isNotEmpty && !widget.readOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSection(
          label: 'Financial summary',
          showDivider: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.veil,
              borderRadius: AppRadius.panelAll,
              border: Border.all(color: AppColors.outlinePanel),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Outstanding now',
                    value: SelloFormatters.currency(
                      customer.outstandingBalance,
                      symbol: currencySymbol,
                    ),
                  ),
                  right: _ProfileField(
                    label: 'Wallet credit',
                    value: SelloFormatters.currency(
                      customer.walletBalance,
                      symbol: currencySymbol,
                    ),
                  ),
                ),
                SizedBox(height: fieldGap),
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Credit limit',
                    value: customer.creditAllowed
                        ? SelloFormatters.currency(
                            customer.creditLimit,
                            symbol: currencySymbol,
                          )
                        : 'Credit not allowed',
                    mutedEmpty: !customer.creditAllowed,
                  ),
                  right: _ProfileField(
                    label: 'Opening balance recorded',
                    value: SelloFormatters.currency(
                      customer.openingBalance,
                      symbol: currencySymbol,
                    ),
                    statusLabel: _adjustmentsLoading ? null : status?.label,
                    statusTone: _adjustmentsLoading ? null : status?.tone,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Outstanding now includes unpaid orders and the remaining '
                  'opening balance. Wallet credit is money available for a '
                  'future payment.',
                  style: _CustomerDetailType.label.copyWith(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_adjustmentsLoading) ...[
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ] else if (_adjustmentsFailed) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Opening balance adjustments',
            child: Text(
              'Couldn\'t load opening balance adjustments.',
              style: _CustomerDetailType.label.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ] else if (_adjustments.isNotEmpty) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Opening balance adjustments',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _adjustments.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.outlineSubtle),
                    const SizedBox(height: 12),
                  ],
                  _OpeningBalanceRow(
                    item: _adjustments[i],
                    currencySymbol: currencySymbol,
                    onCorrect: widget.onCorrectOpeningBalance,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (hasFinancialActions) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Financial actions',
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                if (widget.onAddOpeningBalance != null)
                  _FinancialAction(
                    button: SelloButton(
                      label: 'Add opening balance',
                      icon: Icons.add_card_outlined,
                      variant: SelloButtonVariant.secondary,
                      onPressed: widget.onAddOpeningBalance,
                    ),
                    hint: 'Add money this customer already owed before Sello.',
                  ),
                if (widget.onAddExistingCheque != null)
                  _FinancialAction(
                    button: SelloButton(
                      label: 'Add existing cheque',
                      icon: Icons.account_balance_outlined,
                      variant: SelloButtonVariant.outline,
                      onPressed: widget.onAddExistingCheque,
                    ),
                    hint:
                        'Record a cheque received before you started using Sello.',
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: _sectionGap),
        _ProfileSection(
          label: 'Customer information',
          child: _FieldGrid(fields: customerFields, gap: fieldGap),
        ),
        if (contactFields.isNotEmpty) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Contact & address',
            child: _FieldGrid(fields: contactFields, gap: fieldGap),
          ),
        ],
        if (relationshipFields.isNotEmpty) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Relationship',
            child: _FieldGrid(fields: relationshipFields, gap: fieldGap),
          ),
        ],
        if (showNotes) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Notes',
            child: Text(
              notes,
              style: _CustomerDetailType.value.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: _sectionGap),
        _CustomerActivitySection(customerId: customer.id),
        const SizedBox(height: 18),
        Text(
          'Updated ${SelloFormatters.date(customer.updatedAt)}',
          style: _CustomerDetailType.label.copyWith(
            fontSize: 12,
            color: AppColors.textFaint,
          ),
        ),
      ],
    );
  }

  List<Widget> _contactFields(CustomerSummary customer) {
    final phone = PhoneNumber.displayOrNull(customer.phone);
    final whatsapp = PhoneNumber.displayOrNull(customer.whatsapp);
    final email = customer.email?.trim();
    final tax = customer.taxNumber?.trim();
    final address = customer.addressLine1?.trim();
    final city = customer.city?.trim();
    return [
      if (phone != null) _ProfileField(label: 'Phone', value: phone),
      if (whatsapp != null) _ProfileField(label: 'WhatsApp', value: whatsapp),
      if (email != null && email.isNotEmpty)
        _ProfileField(label: 'Email', value: email),
      if (tax != null && tax.isNotEmpty)
        _ProfileField(label: 'Tax number', value: tax),
      if (address != null && address.isNotEmpty)
        _ProfileField(label: 'Address', value: address),
      if (city != null && city.isNotEmpty)
        _ProfileField(label: 'City', value: city),
    ];
  }

  List<Widget> _relationshipFields(CustomerSummary customer) {
    final rep = widget.assignedRepresentativeName?.trim();
    return [
      if (rep != null && rep.isNotEmpty)
        _ProfileField(label: 'Assigned representative', value: rep),
      if (customer.nextVisitAt != null)
        _ProfileField(
          label: 'Upcoming visit',
          value: SelloFormatters.date(customer.nextVisitAt),
        ),
      if (customer.lastVisitAt != null)
        _ProfileField(
          label: 'Last completed visit',
          value: SelloFormatters.date(customer.lastVisitAt),
        ),
    ];
  }
}

String? _distinctCompanyName(CustomerSummary customer) {
  final company = customer.companyName?.trim();
  if (company == null || company.isEmpty) return null;
  if (company.toLowerCase() == customer.name.trim().toLowerCase()) return null;
  return company;
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.fields, required this.gap});

  final List<Widget> fields;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < fields.length; i += 2) ...[
          if (i > 0) SizedBox(height: gap),
          if (i + 1 < fields.length)
            SelloFormRow(left: fields[i], right: fields[i + 1])
          else
            fields[i],
        ],
      ],
    );
  }
}

class _HubCustomerOrdersBody extends ConsumerStatefulWidget {
  const _HubCustomerOrdersBody({
    required this.customer,
    required this.currencySymbol,
    this.onNewOrder,
    this.onViewOrder,
    this.onReceivePayment,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final VoidCallback? onNewOrder;
  final Future<void> Function(OrderSummary order)? onViewOrder;
  final void Function(OrderSummary order)? onReceivePayment;

  @override
  ConsumerState<_HubCustomerOrdersBody> createState() =>
      _HubCustomerOrdersBodyState();
}

class _HubCustomerOrdersBodyState
    extends ConsumerState<_HubCustomerOrdersBody> {
  static const _pageSize = 20;

  List<OrderSummary> _orders = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool more = false}) async {
    if (more && _loadingMore) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await ref
          .read(orderRepositoryProvider)
          .fetchOrders(
            customerId: widget.customer.id,
            page: more ? _orders.length ~/ _pageSize : 0,
            pageSize: _pageSize,
          );
      if (!mounted) return;
      setState(() {
        _orders = more ? [..._orders, ...page.items] : page.items;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load this customer’s orders.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileSection(
      label: 'Customer orders',
      showDivider: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _orders.isEmpty
                      ? 'Sales and payment status for this customer.'
                      : '${_orders.length} recent order${_orders.length == 1 ? '' : 's'}',
                  style: _CustomerDetailType.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.onNewOrder != null)
                SelloButton(
                  label: 'New order',
                  icon: Icons.add_shopping_cart_rounded,
                  size: SelloButtonSize.small,
                  variant: SelloButtonVariant.outline,
                  onPressed: widget.onNewOrder,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            SelloStateView.error(
              title: 'Orders unavailable',
              message: _error,
              actionLabel: 'Try again',
              onAction: _load,
            )
          else if (_orders.isEmpty)
            SelloEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'New orders for this customer will appear here.',
              actionLabel: widget.onNewOrder == null
                  ? null
                  : 'Create first order',
              onAction: widget.onNewOrder,
            )
          else ...[
            for (var index = 0; index < _orders.length; index++) ...[
              if (index > 0) const SizedBox(height: AppSpacing.sm),
              _CustomerOrderCard(
                order: _orders[index],
                currencySymbol: widget.currencySymbol,
                onView: widget.onViewOrder == null
                    ? null
                    : () => widget.onViewOrder!(_orders[index]),
                onReceivePayment:
                    _canReceivePayment(_orders[index]) &&
                        widget.onReceivePayment != null
                    ? () => widget.onReceivePayment!(_orders[index])
                    : null,
              ),
            ],
            if (_hasMore) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.center,
                child: SelloButton(
                  label: 'Load more',
                  size: SelloButtonSize.small,
                  variant: SelloButtonVariant.outline,
                  loading: _loadingMore,
                  onPressed: _loadingMore ? null : () => _load(more: true),
                ),
              ),
            ],
          ],
        ],
                ),
    );
  }

  bool _canReceivePayment(OrderSummary order) {
    return order.status.isSubmitted &&
        order.paymentStatus != PaymentStatus.paid &&
        order.paymentStatus != PaymentStatus.refunded;
  }
}

class _CustomerOrderCard extends StatelessWidget {
  const _CustomerOrderCard({
    required this.order,
    required this.currencySymbol,
    this.onView,
    this.onReceivePayment,
  });

  final OrderSummary order;
  final String currencySymbol;
  final VoidCallback? onView;
  final VoidCallback? onReceivePayment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                      order.orderNumber,
                      style: _CustomerDetailType.label.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        SelloFormatters.date(order.orderedAt),
                        if (order.employeeName != null) order.employeeName!,
                      ].join(' · '),
                      style: _CustomerDetailType.label.copyWith(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        SelloStatusBadge(
                          label: order.status.label,
                          tone: _orderTone(order.status),
                        ),
                        SelloStatusBadge(
                          label: order.paymentStatus.label,
                          emphasis: SelloBadgeEmphasis.quiet,
                          tone: _paymentTone(order.paymentStatus),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                SelloFormatters.currency(order.total, symbol: currencySymbol),
                style: _CustomerDetailType.value.copyWith(fontSize: 16),
              ),
              if (onView != null) ...[
                const SizedBox(width: AppSpacing.xs),
                _OrderIconAction(
                  icon: Icons.visibility_outlined,
                  tooltip: 'View order',
                  onPressed: onView!,
                ),
              ],
              if (onReceivePayment != null) ...[
                const SizedBox(width: AppSpacing.xs),
                _OrderIconAction(
                  icon: Icons.payments_outlined,
                  tooltip: 'Receive payment',
                  emphasized: true,
                  onPressed: onReceivePayment!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static SelloStatusTone _orderTone(OrderStatus status) => switch (status) {
    OrderStatus.completed => SelloStatusTone.success,
    OrderStatus.cancelled => SelloStatusTone.neutral,
    OrderStatus.partiallyDelivered => SelloStatusTone.warning,
    OrderStatus.placed => SelloStatusTone.info,
    OrderStatus.draft => SelloStatusTone.neutral,
  };

  static SelloStatusTone _paymentTone(PaymentStatus status) => switch (status) {
    PaymentStatus.paid => SelloStatusTone.success,
    PaymentStatus.partial => SelloStatusTone.warning,
    PaymentStatus.refunded => SelloStatusTone.neutral,
    PaymentStatus.unpaid => SelloStatusTone.danger,
  };
}

class _OrderIconAction extends StatelessWidget {
  const _OrderIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: emphasized
            ? AppColors.primary
            : AppColors.textSecondary,
        backgroundColor: emphasized
            ? AppColors.primaryContainer
            : AppColors.surface,
        side: BorderSide(
          color: emphasized
              ? AppColors.primary.withValues(alpha: 0.24)
              : AppColors.outlinePanel,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

class _HubVisitHistoryBody extends StatelessWidget {
  const _HubVisitHistoryBody({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (customer.lastVisitAt != null)
        'Last visit ${SelloFormatters.date(customer.lastVisitAt)}',
      if (customer.nextVisitAt != null)
        'Upcoming ${SelloFormatters.date(customer.nextVisitAt)}',
    ];

    return _ProfileSection(
      label: 'Visit history',
      showDivider: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (parts.isNotEmpty) ...[
            Text(
              parts.join(' · '),
              style: _CustomerDetailType.label.copyWith(
                color: AppColors.textFaint,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _CustomerVisitTimeline(customerId: customer.id),
        ],
      ),
    );
  }
}

class _FinancialAction extends StatelessWidget {
  const _FinancialAction({required this.button, required this.hint});

  final Widget button;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          button,
          const SizedBox(height: AppSpacing.xs),
          Text(
            hint,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Field-sales first view — outstanding, contact, last order; rest behind expand.
class _CustomerActivitySection extends ConsumerStatefulWidget {
  const _CustomerActivitySection({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_CustomerActivitySection> createState() =>
      _CustomerActivitySectionState();
}

class _CustomerActivitySectionState
    extends ConsumerState<_CustomerActivitySection> {
  static const _historyLimit = 12;
  static const _previewLimit = 3;

  List<CompanyActivityEvent> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _CustomerActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId) _load();
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      setState(() {
        _events = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await ref
          .read(notificationRepositoryProvider)
          .fetchCompanyActivity(
            companyId: session.company.id,
            referenceType: 'customer',
            referenceId: widget.customerId,
            limit: _historyLimit,
          );
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load company activity.';
      });
    }
  }

  void _openHistory() {
    final events = _events;
    showDialog<void>(
      context: context,
      builder: (context) => SelloFormDialog(
        title: 'Customer activity',
        maxWidth: 720,
        fullscreenOnMobile: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Showing the latest events, up to $_historyLimit. '
              'Older events stay on record and are not listed here.',
              style: _CustomerDetailType.label.copyWith(
                fontSize: 12.5,
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SelloActivityTimeline(
              events: events,
              dense: true,
              emptyMessage: 'No company activity for this customer yet.',
            ),
          ],
        ),
        footer: Align(
          alignment: Alignment.centerRight,
          child: SelloButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _events.take(_previewLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text('RECENT ACTIVITY', style: _CustomerDetailType.section),
            ),
            if (!_loading && _error == null)
              SelloButton(
                label: 'View activity',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.outline,
                onPressed: _openHistory,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_error != null)
          Text(
            _error!,
            style: _CustomerDetailType.label.copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          )
        else
          SelloActivityTimeline(
            events: preview,
            dense: true,
            emptyMessage: 'No company activity for this customer yet.',
          ),
      ],
    );
  }
}

class _FieldSalesFocus extends StatelessWidget {
  const _FieldSalesFocus({
    required this.customer,
    required this.currencySymbol,
    this.assignedRepresentativeName,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final String? assignedRepresentativeName;

  @override
  Widget build(BuildContext context) {
    final dash = '—';
    final location = [
      if (customer.addressLine1 != null) customer.addressLine1!,
      if (customer.city != null) customer.city!,
    ].join(', ');

    final recentBits = <String>[
      if (customer.lastPurchaseAt != null)
        'Last order ${SelloFormatters.date(customer.lastPurchaseAt)}',
      if (customer.lastVisitAt != null)
        'Last visit ${SelloFormatters.date(customer.lastVisitAt)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          SelloFormatters.currency(
            customer.outstandingBalance,
            symbol: currencySymbol,
          ),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Outstanding',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 20),
        if (customer.phone != null || location.isNotEmpty) ...[
          Text(
            [
              if (customer.phone != null) PhoneNumber.displayOf(customer.phone),
              if (location.isNotEmpty) location,
            ].join(' · '),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          recentBits.isEmpty ? 'No recent orders yet' : recentBits.join(' · '),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text(
              'Customer details',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            children: [
              _ProfileField(
                label: 'Credit',
                value: customer.creditAllowed
                    ? SelloFormatters.currency(
                        customer.creditLimit,
                        symbol: currencySymbol,
                      )
                    : 'Not allowed',
                mutedEmpty: !customer.creditAllowed,
              ),
              const SizedBox(height: 12),
              _ProfileField(
                label: 'Customer since',
                value: customer.createdAt != null
                    ? SelloFormatters.date(customer.createdAt)
                    : dash,
                mutedEmpty: customer.createdAt == null,
              ),
              const SizedBox(height: 12),
              _ProfileField(label: 'Type', value: customer.customerType.label),
              if (assignedRepresentativeName != null) ...[
                const SizedBox(height: 12),
                _ProfileField(
                  label: 'Assigned rep',
                  value: assignedRepresentativeName!,
                ),
              ],
              if (customer.email != null) ...[
                const SizedBox(height: 12),
                _ProfileField(label: 'Email', value: customer.email!),
              ],
              const SizedBox(height: 16),
              _CustomerVisitTimeline(customerId: customer.id),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesVisitFooter extends ConsumerWidget {
  const _SalesVisitFooter({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCustomerVisitProvider).valueOrNull;
    final visitingThis = active?.customerId == customer.id;

    Future<void> start() async {
      if (!context.mounted) return;
      Navigator.of(context).maybePop();
      context.go(
        '${RoutePaths.selloVisit}'
        '?customer=${customer.id}'
        '&name=${Uri.encodeComponent(customer.name)}',
      );
    }

    Future<void> complete() async {
      if (!context.mounted) return;
      Navigator.of(context).maybePop();
      context.go(
        '${RoutePaths.selloVisit}'
        '?customer=${customer.id}'
        '&name=${Uri.encodeComponent(customer.name)}',
      );
    }

    return SelloDialogFooter(
      cancelLabel: 'Close',
      cancelVariant: SelloButtonVariant.outline,
      onCancel: () => Navigator.of(context).maybePop(),
      primaryLabel: visitingThis
          ? 'Open visit'
          : active == null
              ? 'Open visit'
              : 'Busy',
      primaryEnabled: visitingThis || active == null,
      onPrimary: visitingThis
          ? complete
          : active == null
              ? start
              : null,
    );
  }
}

class _CustomerVisitTimeline extends ConsumerStatefulWidget {
  const _CustomerVisitTimeline({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_CustomerVisitTimeline> createState() =>
      _CustomerVisitTimelineState();
}

class _CustomerVisitTimelineState
    extends ConsumerState<_CustomerVisitTimeline> {
  List<CustomerVisit> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await ref
          .read(visitRepositoryProvider)
          .fetchCustomerVisitHistory(
                companyId: session.company.id,
                customerId: widget.customerId,
              );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No visits yet',
              style: _CustomerDetailType.label.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Completed field visits will appear here.',
        style: _CustomerDetailType.label.copyWith(
          color: AppColors.textFaint,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: context.brandAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        SelloFormatters.dateTime(_items[i].startedAt),
                        if (_items[i].outcome != null) _items[i].outcome!.label,
                        _items[i].durationLabel,
                      ].join(' · '),
                      style: _CustomerDetailType.label.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_items[i].employeeName != null)
                      Text(
                        _items[i].employeeName!,
                        style: _CustomerDetailType.label.copyWith(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    if (_items[i].notes != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _items[i].notes!,
                          style: _CustomerDetailType.label.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    if (_items[i].orderCount > 0 || _items[i].paymentCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            if (_items[i].orderCount > 0)
                              '${_items[i].orderCount} orders',
                            if (_items[i].paymentCount > 0)
                              '${_items[i].paymentCount} payments',
                          ].join(' · '),
                          style: _CustomerDetailType.label.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

abstract final class _CustomerDetailType {
  static const TextStyle title = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.45,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle section = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.08 * 11,
    height: 1.2,
    color: AppColors.textFaint,
  );

  static const TextStyle label = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  static const TextStyle value = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: AppColors.textPrimary,
  );
}

class _CustomerHero extends StatelessWidget {
  const _CustomerHero({required this.customer});

  final CustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      if (customer.companyName != null) customer.companyName!,
      customer.customerType.label,
      if (customer.code != null) customer.code!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(customer.name, style: _CustomerDetailType.title),
        if (metaParts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(metaParts.join(' · '), style: _CustomerDetailType.subtitle),
        ],
        const SizedBox(height: 14),
        SelloStatusBadge(
          label: customer.isActive ? 'Active' : 'Inactive',
          tone: customer.isActive
              ? SelloStatusTone.success
              : SelloStatusTone.neutral,
        ),
      ],
    );
  }
}

class _OpeningBalanceRow extends StatelessWidget {
  const _OpeningBalanceRow({
    required this.item,
    required this.currencySymbol,
    this.onCorrect,
  });

  final CustomerReceivableAdjustment item;
  final String currencySymbol;
  final Future<void> Function(CustomerReceivableAdjustment item)? onCorrect;

  TextStyle get _title => _CustomerDetailType.label.copyWith(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  TextStyle get _meta => _CustomerDetailType.label.copyWith(
    color: AppColors.textFaint,
    fontSize: 12,
  );

  @override
  Widget build(BuildContext context) {
    final reference = item.referenceNumber?.trim();
    final collected = item.remaining <= 0.001;
    final partiallyCollected =
        !collected && item.remaining + 0.001 < item.amount;
    final status = collected
        ? 'Collected'
        : partiallyCollected
        ? 'Partially collected'
        : null;
    final tone = collected
        ? SelloStatusTone.success
        : SelloStatusTone.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${item.adjustmentNumber} · ${SelloFormatters.date(item.recognizedAt)}',
              style: _title,
            ),
            if (status != null)
              SelloStatusBadge(label: status, tone: tone, compact: true),
          ],
        ),
        if (reference != null && reference.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('Old invoice / reference: $reference', style: _meta),
        ],
        const SizedBox(height: 4),
        Text(
          'Original ${SelloFormatters.currency(item.amount, symbol: currencySymbol)}'
          ' · Remaining ${SelloFormatters.currency(item.remaining, symbol: currencySymbol)}',
          style: _meta.copyWith(color: AppColors.textSecondary),
        ),
        if (onCorrect != null) ...[
          const SizedBox(height: 8),
          SelloButton(
            label: 'Correct',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.outline,
            onPressed: () => onCorrect!(item),
          ),
        ],
      ],
    );
  }
}

class _ArchivedNotice extends StatelessWidget {
  const _ArchivedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This customer is inactive and is hidden from new sales. '
              'Past orders and payments still show them.',
              style: _CustomerDetailType.label.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.label,
    required this.child,
    this.showDivider = true,
  });

  final String label;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider) ...[
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        const SizedBox(height: 14),
        ],
        Text(label.toUpperCase(), style: _CustomerDetailType.section),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.value,
    this.mutedEmpty = false,
    this.statusLabel,
    this.statusTone,
  });

  final String label;
  final String value;
  final bool mutedEmpty;
  final String? statusLabel;
  final SelloStatusTone? statusTone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _CustomerDetailType.label),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
        Text(
          value,
          style: mutedEmpty
              ? _CustomerDetailType.value.copyWith(
                  color: AppColors.textFaint.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                )
              : _CustomerDetailType.value,
            ),
            if (statusLabel != null)
              SelloStatusBadge(
                label: statusLabel!,
                tone: statusTone ?? SelloStatusTone.neutral,
              ),
          ],
        ),
      ],
    );
  }
}
