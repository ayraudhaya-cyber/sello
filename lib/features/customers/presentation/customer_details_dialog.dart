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
import 'package:sello/shared/models/customer_receivable_adjustment.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_visit.dart';
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

  @override
  State<CustomerDetailsDialog> createState() => _CustomerDetailsDialogState();
}

enum _CustomerDetailTab { overview, visitHistory }

class _CustomerDetailsDialogState extends State<CustomerDetailsDialog> {
  static const double _sectionGap = 36;
  static const double _fieldGap = 18;

  _CustomerDetailTab _tab = _CustomerDetailTab.overview;

  CustomerSummary get customer => widget.customer;

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final canManage =
        !widget.readOnly && widget.onEdit != null && widget.onToggleArchive != null;

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
            if (_tab == _CustomerDetailTab.overview)
              _HubOverviewBody(
                customer: customer,
                currencySymbol: widget.currencySymbol,
                assignedRepresentativeName: widget.assignedRepresentativeName,
                readOnly: widget.readOnly,
                openingBalanceHistoryEpoch: widget.openingBalanceHistoryEpoch,
                onAddOpeningBalance: widget.onAddOpeningBalance,
                onCorrectOpeningBalance: widget.onCorrectOpeningBalance,
                onAddExistingCheque: widget.onAddExistingCheque,
                sectionGap: _sectionGap,
                fieldGap: _fieldGap,
              )
            else
              _HubVisitHistoryBody(customer: customer),
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
              destructiveLabel:
                  customer.isActive ? null : 'Delete permanently',
              onDestructive:
                  customer.isActive ? null : widget.onDeletePermanently,
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
  const _CustomerDetailTabs({
    required this.tab,
    required this.onChanged,
  });

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
          _tab(context, 'Visit History', _CustomerDetailTab.visitHistory),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String label,
    _CustomerDetailTab value,
  ) {
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

class _HubOverviewBody extends StatelessWidget {
  const _HubOverviewBody({
    required this.customer,
    required this.currencySymbol,
    required this.readOnly,
    required this.openingBalanceHistoryEpoch,
    required this.sectionGap,
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
  final double sectionGap;
  final double fieldGap;

  static const _dash = '—';

  @override
  Widget build(BuildContext context) {
    final hasFinancialActions =
        onAddOpeningBalance != null || onAddExistingCheque != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SelloIntelligenceBanner(
          message:
              'Purchase patterns, risk signals, and growth insights will '
              'appear here as Sello Intelligence rolls out.',
        ),
        SizedBox(height: sectionGap),
        _ProfileSection(
          label: 'Financial summary',
          showDivider: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelloFormRow(
                left: _ProfileField(
                  label: 'Outstanding balance',
                  value: SelloFormatters.currency(
                    customer.outstandingBalance,
                    symbol: currencySymbol,
                  ),
                ),
                right: _ProfileField(
                  label: 'Wallet balance',
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
                  label: 'Opening balance',
                  value: SelloFormatters.currency(
                    customer.openingBalance,
                    symbol: currencySymbol,
                  ),
                ),
              ),
              if (hasFinancialActions) ...[
                SizedBox(height: fieldGap),
                Text(
                  'Financial actions',
                  style: _CustomerDetailType.label.copyWith(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    if (onAddOpeningBalance != null)
                      _FinancialAction(
                        button: SelloButton(
                          label: 'Add opening balance',
                          icon: Icons.add_card_outlined,
                          variant: SelloButtonVariant.secondary,
                          onPressed: onAddOpeningBalance,
                        ),
                        hint:
                            'Add money this customer already owed before Sello.',
                      ),
                    if (onAddExistingCheque != null)
                      _FinancialAction(
                        button: SelloButton(
                          label: 'Add existing cheque',
                          icon: Icons.account_balance_outlined,
                          variant: SelloButtonVariant.outline,
                          onPressed: onAddExistingCheque,
                        ),
                        hint:
                            'Record a cheque received before you started using Sello.',
                      ),
                  ],
                ),
              ],
              _OpeningBalanceHistory(
                customerId: customer.id,
                currencySymbol: currencySymbol,
                epoch: openingBalanceHistoryEpoch,
                onCorrect: onCorrectOpeningBalance,
              ),
            ],
          ),
        ),
        SizedBox(height: sectionGap),
        _ProfileSection(
          label: 'Customer information',
          child: Column(
            children: [
              const SelloFormRow(
                left: _ProfileField(
                  label: 'Lifetime sales',
                  value: 'Coming soon',
                  mutedEmpty: true,
                ),
                right: _ProfileField(
                  label: 'Total orders',
                  value: 'Coming soon',
                  mutedEmpty: true,
                ),
              ),
              SizedBox(height: fieldGap),
              SelloFormRow(
                left: _ProfileField(
                  label: 'Customer since',
                  value: customer.createdAt != null
                      ? SelloFormatters.date(customer.createdAt)
                      : _dash,
                  mutedEmpty: customer.createdAt == null,
                ),
                right: _ProfileField(
                  label: 'Last purchase',
                  value: customer.lastPurchaseAt != null
                      ? SelloFormatters.date(customer.lastPurchaseAt)
                      : _dash,
                  mutedEmpty: customer.lastPurchaseAt == null,
                ),
              ),
              SizedBox(height: fieldGap),
              SelloFormRow(
                left: _ProfileField(
                  label: 'Type',
                  value: customer.customerType.label,
                ),
                right: _ProfileField(
                  label: 'Company',
                  value: customer.companyName ?? _dash,
                  mutedEmpty: customer.companyName == null,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: sectionGap),
        _ProfileSection(
          label: 'Relationship',
          child: Column(
            children: [
              SelloFormRow(
                left: _ProfileField(
                  label: 'Upcoming visit',
                  value: customer.nextVisitAt != null
                      ? SelloFormatters.date(customer.nextVisitAt)
                      : _dash,
                  mutedEmpty: customer.nextVisitAt == null,
                ),
                right: _ProfileField(
                  label: 'Last completed visit',
                  value: customer.lastVisitAt != null
                      ? SelloFormatters.date(customer.lastVisitAt)
                      : _dash,
                  mutedEmpty: customer.lastVisitAt == null,
                ),
              ),
              SizedBox(height: fieldGap),
              SelloFormRow(
                left: _ProfileField(
                  label: 'Assigned representative',
                  value: assignedRepresentativeName ?? _dash,
                  mutedEmpty: assignedRepresentativeName == null,
                ),
                right: const _ProfileField(
                  label: 'Visit frequency',
                  value: 'Coming soon',
                  mutedEmpty: true,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: sectionGap),
        _ProfileSection(
          label: 'Contact',
          child: Column(
            children: [
              SelloFormRow(
                left: _ProfileField(
                  label: 'Phone',
                  value: PhoneNumber.displayOrNull(customer.phone) ?? _dash,
                  mutedEmpty: customer.phone == null,
                ),
                right: _ProfileField(
                  label: 'WhatsApp',
                  value: PhoneNumber.displayOrNull(customer.whatsapp) ?? _dash,
                  mutedEmpty: customer.whatsapp == null,
                ),
              ),
              SizedBox(height: fieldGap),
              SelloFormRow(
                left: _ProfileField(
                  label: 'Email',
                  value: customer.email ?? _dash,
                  mutedEmpty: customer.email == null,
                ),
                right: _ProfileField(
                  label: 'Tax number',
                  value: customer.taxNumber ?? _dash,
                  mutedEmpty: customer.taxNumber == null,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: sectionGap),
        _ProfileSection(
          label: 'Address',
          child: SelloFormRow(
            left: _ProfileField(
              label: 'Address',
              value: customer.addressLine1 ?? _dash,
              mutedEmpty: customer.addressLine1 == null,
            ),
            right: _ProfileField(
              label: 'City',
              value: customer.city ?? _dash,
              mutedEmpty: customer.city == null,
            ),
          ),
        ),
        if (customer.notes != null &&
            customer.notes!.trim().isNotEmpty &&
            !readOnly) ...[
          SizedBox(height: sectionGap),
          _ProfileSection(
            label: 'Notes',
            child: Text(
              customer.notes!,
              style: _CustomerDetailType.value.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        SizedBox(height: sectionGap),
        _ProfileSection(
          label: 'Activity',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EntityActivityPanel(
                referenceType: 'customer',
                referenceId: customer.id,
                emptyMessage: 'No company activity for this customer yet.',
                limit: 12,
              ),
              SizedBox(height: fieldGap),
              SelloFormRow(
                left: _ProfileField(
                  label: 'Created',
                  value: customer.createdAt != null
                      ? SelloFormatters.date(customer.createdAt)
                      : _dash,
                  mutedEmpty: customer.createdAt == null,
                ),
                right: _ProfileField(
                  label: 'Updated',
                  value: SelloFormatters.date(customer.updatedAt),
                ),
              ),
            ],
          ),
        ),
      ],
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
  const _FinancialAction({
    required this.button,
    required this.hint,
  });

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
              _ProfileField(
                label: 'Type',
                value: customer.customerType.label,
              ),
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
      final items =
          await ref.read(visitRepositoryProvider).fetchCustomerVisitHistory(
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
                        if (_items[i].outcome != null)
                          _items[i].outcome!.label,
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
                    if (_items[i].orderCount > 0 ||
                        _items[i].paymentCount > 0)
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

class _OpeningBalanceHistory extends ConsumerStatefulWidget {
  const _OpeningBalanceHistory({
    required this.customerId,
    required this.currencySymbol,
    required this.epoch,
    this.onCorrect,
  });

  final String customerId;
  final String currencySymbol;
  final int epoch;
  final Future<void> Function(CustomerReceivableAdjustment item)? onCorrect;

  @override
  ConsumerState<_OpeningBalanceHistory> createState() =>
      _OpeningBalanceHistoryState();
}

class _OpeningBalanceHistoryState
    extends ConsumerState<_OpeningBalanceHistory> {
  List<CustomerReceivableAdjustment> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _OpeningBalanceHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.epoch != widget.epoch ||
        oldWidget.customerId != widget.customerId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ref
          .read(customerRepositoryProvider)
          .fetchOpeningBalanceAdjustments(widget.customerId);
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
        padding: EdgeInsets.only(top: 18),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Opening balance adjustments',
            style: _CustomerDetailType.label.copyWith(
              color: AppColors.textFaint,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _OpeningBalanceRow(
              item: _items[i],
              currencySymbol: widget.currencySymbol,
              onCorrect: widget.onCorrect,
            ),
          ],
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Opening balance', style: _title),
        const SizedBox(height: 2),
        Text(item.adjustmentNumber, style: _title),
        if (reference != null && reference.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('Old invoice / reference: $reference', style: _meta),
        ],
        const SizedBox(height: 6),
        Text(
          'Original: ${SelloFormatters.currency(item.amount, symbol: currencySymbol)}',
          style: _CustomerDetailType.label.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Remaining: ${SelloFormatters.currency(item.remaining, symbol: currencySymbol)}',
          style: _CustomerDetailType.label.copyWith(
            color: AppColors.textTertiary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Date: ${SelloFormatters.date(item.recognizedAt)}',
          style: _meta,
        ),
        if (onCorrect != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SelloButton(
              label: 'Correct',
              size: SelloButtonSize.small,
              variant: SelloButtonVariant.outline,
              onPressed: () => onCorrect!(item),
            ),
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
  });

  final String label;
  final String value;
  final bool mutedEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _CustomerDetailType.label),
        const SizedBox(height: 6),
        Text(
          value,
          style: mutedEmpty
              ? _CustomerDetailType.value.copyWith(
                  color: AppColors.textFaint.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                )
              : _CustomerDetailType.value,
        ),
      ],
    );
  }
}
