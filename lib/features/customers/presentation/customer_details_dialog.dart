import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Customer Workspace — relationship profile, not a plain info popup.
///
/// Shared by Hub (manage) and Sales (lookup). Pass [readOnly] for field sales
/// so edit/archive/delete stay Owner/Manager-only.
class CustomerDetailsDialog extends StatelessWidget {
  const CustomerDetailsDialog({
    super.key,
    required this.customer,
    this.onEdit,
    this.onToggleArchive,
    this.onDeletePermanently,
    this.readOnly = false,
    this.currencySymbol = '\$',
    this.assignedRepresentativeName,
    this.enableVisitActions = false,
  });

  final CustomerSummary customer;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleArchive;
  final VoidCallback? onDeletePermanently;
  final bool readOnly;
  final String currencySymbol;

  /// From employee customer assignments — not duplicated customer logic.
  final String? assignedRepresentativeName;

  /// Sales field actions: Start / Complete visit.
  final bool enableVisitActions;

  static const double _sectionGap = 36;

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final dash = '—';
    final canManage = !readOnly && onEdit != null && onToggleArchive != null;

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
          if (enableVisitActions)
            _FieldSalesFocus(
              customer: customer,
              currencySymbol: currencySymbol,
              assignedRepresentativeName: assignedRepresentativeName,
            )
          else ...[
          const SelloIntelligenceBanner(
            message:
                'Purchase patterns, risk signals, and growth insights will '
                'appear here as Sello Intelligence rolls out.',
          ),
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Financial summary',
            child: Column(
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
                const SizedBox(height: 18),
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
                const SizedBox(height: 18),
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
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Relationship',
            child: Column(
              children: [
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Customer since',
                    value: customer.createdAt != null
                        ? SelloFormatters.date(customer.createdAt)
                        : dash,
                    mutedEmpty: customer.createdAt == null,
                  ),
                  right: _ProfileField(
                    label: 'Last purchase',
                    value: customer.lastPurchaseAt != null
                        ? SelloFormatters.date(customer.lastPurchaseAt)
                        : dash,
                    mutedEmpty: customer.lastPurchaseAt == null,
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Type',
                    value: customer.customerType.label,
                  ),
                  right: _ProfileField(
                    label: 'Company',
                    value: customer.companyName ?? dash,
                    mutedEmpty: customer.companyName == null,
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Upcoming visit',
                    value: customer.nextVisitAt != null
                        ? SelloFormatters.date(customer.nextVisitAt)
                        : dash,
                    mutedEmpty: customer.nextVisitAt == null,
                  ),
                  right: _ProfileField(
                    label: 'Last completed visit',
                    value: customer.lastVisitAt != null
                        ? SelloFormatters.date(customer.lastVisitAt)
                        : dash,
                    mutedEmpty: customer.lastVisitAt == null,
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Assigned representative',
                    value: assignedRepresentativeName ?? dash,
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
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Visit history',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  () {
                    final parts = <String>[
                      if (customer.lastVisitAt != null)
                        'Last visit ${SelloFormatters.date(customer.lastVisitAt)}',
                      if (customer.nextVisitAt != null)
                        'Upcoming ${SelloFormatters.date(customer.nextVisitAt)}',
                    ];
                    return parts.isEmpty
                        ? 'Field visit activity for this customer.'
                        : parts.join(' · ');
                  }(),
                  style: _CustomerDetailType.label.copyWith(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                _CustomerVisitTimeline(customerId: customer.id),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Contact',
            child: Column(
              children: [
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Phone',
                    value: PhoneNumber.displayOrNull(customer.phone) ?? dash,
                    mutedEmpty: customer.phone == null,
                  ),
                  right: _ProfileField(
                    label: 'WhatsApp',
                    value: PhoneNumber.displayOrNull(customer.whatsapp) ?? dash,
                    mutedEmpty: customer.whatsapp == null,
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Email',
                    value: customer.email ?? dash,
                    mutedEmpty: customer.email == null,
                  ),
                  right: _ProfileField(
                    label: 'Tax number',
                    value: customer.taxNumber ?? dash,
                    mutedEmpty: customer.taxNumber == null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Address',
            child: SelloFormRow(
              left: _ProfileField(
                label: 'Address',
                value: customer.addressLine1 ?? dash,
                mutedEmpty: customer.addressLine1 == null,
              ),
              right: _ProfileField(
                label: 'City',
                value: customer.city ?? dash,
                mutedEmpty: customer.city == null,
              ),
            ),
          ),
          if (customer.notes != null &&
              customer.notes!.trim().isNotEmpty &&
              !readOnly) ...[
            const SizedBox(height: _sectionGap),
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
          const SizedBox(height: _sectionGap),
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
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _ProfileField(
                    label: 'Created',
                    value: customer.createdAt != null
                        ? SelloFormatters.date(customer.createdAt)
                        : dash,
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
        ],
      ),
      footer: canManage
          ? SelloDialogFooter(
              cancelLabel: customer.isActive ? 'Archive' : 'Restore',
              cancelVariant: SelloButtonVariant.ghost,
              onCancel: onToggleArchive,
              primaryLabel: 'Edit Customer',
              onPrimary: onEdit,
              destructiveLabel:
                  customer.isActive ? null : 'Delete permanently',
              onDestructive:
                  customer.isActive ? null : onDeletePermanently,
            )
          : enableVisitActions
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
      return Text(
        'No completed visits yet.',
        style: _CustomerDetailType.label.copyWith(
          color: AppColors.textFaint,
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
          label: customer.isActive ? 'Active' : 'Archived',
          tone: customer.isActive
              ? SelloStatusTone.success
              : SelloStatusTone.neutral,
        ),
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
              'Archived customers are hidden from new sales but remain '
              'available for reports and history.',
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
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        const SizedBox(height: 14),
        Text(label.toUpperCase(), style: _CustomerDetailType.section),
        const SizedBox(height: 16),
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
