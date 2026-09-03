import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/payments/application/hub_payments_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/payments/presentation/payment_details_dialog.dart';
import 'package:sello/features/payments/presentation/receive_payment_dialog.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubPaymentsPage extends ConsumerStatefulWidget {
  const HubPaymentsPage({super.key});

  @override
  ConsumerState<HubPaymentsPage> createState() => _HubPaymentsPageState();
}

class _HubPaymentsPageState extends ConsumerState<HubPaymentsPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _currencySymbol() {
    final currency = ref.read(companySettingsProvider).currency;
    return switch (currency) {
      'LKR' => 'Rs ',
      'EUR' => '€',
      'GBP' => '£',
      'INR' => '₹',
      'JPY' => '¥',
      _ => '\$',
    };
  }

  Future<void> _receivePayment() async {
    final input = await showDialog<ReceivePaymentInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ReceivePaymentDialog(currencySymbol: _currencySymbol()),
    );
    if (input == null) return;

    final result = await ref
        .read(hubPaymentsProvider.notifier)
        .receivePayment(input);
    if (!mounted) return;
    if (result == null) {
      final message = ref.read(hubPaymentsProvider).errorMessage;
      SelloSnackbars.error(context, message ?? 'Unable to record payment.');
    } else if (result.isPendingReview) {
      await presentCollectionAcknowledgement(context, result.acknowledgement);
    } else {
      SelloSnackbars.success(context, 'Payment recorded.');
    }
  }

  Future<void> _openDetails(PaymentSummary payment) async {
    final detail = await ref
        .read(paymentRepositoryProvider)
        .fetchById(payment.id);
    if (!mounted) return;
    if (detail == null) {
      SelloSnackbars.error(context, 'Unable to load that payment.');
      return;
    }
    final permissions = ref.read(permissionServiceProvider);
    final canReview =
        (permissions?.canApprove(AppModule.payments) ?? false) &&
        detail.summary.status.isPendingReview;

    await showDialog<void>(
      context: context,
      builder: (context) => PaymentDetailsDialog(
        detail: detail,
        currencySymbol: _currencySymbol(),
        canReview: canReview,
        onApprove: canReview
            ? () async {
                final error = await ref
                    .read(hubPaymentsProvider.notifier)
                    .approveCollection(detail.summary.id);
                if (!context.mounted) return;
                if (error != null) {
                  SelloSnackbars.error(context, error);
                  return;
                }
                SelloSnackbars.success(context, 'Collection approved.');
                Navigator.of(context).maybePop();
              }
            : null,
        onReject: canReview
            ? (reason) async {
                final error = await ref
                    .read(hubPaymentsProvider.notifier)
                    .rejectCollection(detail.summary.id, reason: reason);
                if (!context.mounted) return;
                if (error != null) {
                  SelloSnackbars.error(context, error);
                  return;
                }
                SelloSnackbars.success(context, 'Collection rejected.');
                Navigator.of(context).maybePop();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubPaymentsProvider);
    ref.watch(hubSettingsProvider);
    final currencySymbol = _currencySymbol();

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Payments',
      subtitle:
          'Your financial workspace — collect against orders, wallets, and credit.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaymentsToolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubPaymentsProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubPaymentsProvider.notifier).setStatusFilter(value);
              }
            },
            onMethodChanged: (value) {
              if (value != null) {
                ref.read(hubPaymentsProvider.notifier).setMethodFilter(value);
              }
            },
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubPaymentsProvider.notifier).refresh(),
            onReceive: state.isSaving ? null : _receivePayment,
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.pendingReviewCount > 0) ...[
            _PendingReviewBanner(
              count: state.pendingReviewCount,
              onReview: () {
                ref
                    .read(hubPaymentsProvider.notifier)
                    .setStatusFilter(PaymentStatusFilter.pending);
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 8),
          ] else ...[
            _PaymentsSummaryRow(
              stats: state.stats,
              currencySymbol: currencySymbol,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load payments',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubPaymentsProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: 'No payments yet',
                  message:
                      'Record your first collection against a customer’s '
                      'outstanding orders. Payments update balances and order '
                      'settlement status automatically.',
                  icon: Icons.payments_rounded,
                  actionLabel: 'Receive Payment',
                  onAction: _receivePayment,
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final payment in state.items) ...[
                      SelloCard(
                        onTap: () => _openDetails(payment),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    payment.paymentNumber,
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                _statusBadge(payment.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              payment.customerName ?? 'Customer',
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              SelloFormatters.currency(
                                payment.amount,
                                symbol: currencySymbol,
                              ),
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _Pager(
                      page: state.page,
                      hasMore: state.hasMore,
                      onPrev: state.page <= 0
                          ? null
                          : () => ref
                                .read(hubPaymentsProvider.notifier)
                                .goToPage(state.page - 1),
                      onNext: !state.hasMore
                          ? null
                          : () => ref
                                .read(hubPaymentsProvider.notifier)
                                .goToPage(state.page + 1),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  columns: [
                    selloDataColumn('Payment #'),
                    selloDataColumn('Customer'),
                    selloDataColumn('Related Order'),
                    selloDataColumn('Method'),
                    selloDataColumn('Amount', numeric: true),
                    selloDataColumn('Status'),
                    selloDataColumn('Received By'),
                    selloDataColumn('Date'),
                    selloDataColumn('Actions'),
                  ],
                  rows: [
                    for (final payment in state.items)
                      DataRow(
                        onSelectChanged: (_) => _openDetails(payment),
                        cells: [
                          DataCell(
                            SelloTableText(
                              payment.paymentNumber,
                              tone: SelloTableTone.strong,
                            ),
                          ),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SelloTableText(
                                  payment.customerName ?? '—',
                                  tone: SelloTableTone.strong,
                                ),
                                if (payment.customerPhone != null) ...[
                                  const SizedBox(height: 2),
                                  SelloTableText(
                                    payment.customerPhone!,
                                    tone: SelloTableTone.muted,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          DataCell(
                            SelloTableText(
                              payment.relatedOrderNumber ?? '—',
                              tone: payment.relatedOrderNumber == null
                                  ? SelloTableTone.muted
                                  : SelloTableTone.normal,
                            ),
                          ),
                          DataCell(SelloTableText(payment.method.label)),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.currency(
                                payment.amount,
                                symbol: currencySymbol,
                              ),
                              tone: SelloTableTone.strong,
                              numeric: true,
                            ),
                          ),
                          DataCell(_statusBadge(payment.status)),
                          DataCell(SelloTableText(payment.employeeName ?? '—')),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.date(payment.receivedAt),
                              tone: SelloTableTone.muted,
                            ),
                          ),
                          DataCell(
                            SelloButton(
                              label: 'View',
                              size: SelloButtonSize.small,
                              variant: SelloButtonVariant.ghost,
                              onPressed: () => _openDetails(payment),
                            ),
                          ),
                        ],
                      ),
                  ],
                  footer: _Pager(
                    page: state.page,
                    hasMore: state.hasMore,
                    onPrev: state.page <= 0
                        ? null
                        : () => ref
                              .read(hubPaymentsProvider.notifier)
                              .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                              .read(hubPaymentsProvider.notifier)
                              .goToPage(state.page + 1),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Widget _statusBadge(PaymentRecordStatus status) {
  return SelloStatusBadge(
    label: status.label,
    tone: switch (status) {
      PaymentRecordStatus.completed => SelloStatusTone.success,
      PaymentRecordStatus.pending => SelloStatusTone.warning,
      PaymentRecordStatus.refunded => SelloStatusTone.info,
      PaymentRecordStatus.cancelled ||
      PaymentRecordStatus.rejected => SelloStatusTone.danger,
    },
  );
}

class _PaymentsToolbar extends StatelessWidget {
  const _PaymentsToolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onMethodChanged,
    required this.onRefresh,
    required this.onReceive,
  });

  final TextEditingController searchController;
  final HubPaymentsState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PaymentStatusFilter?> onStatusChanged;
  final ValueChanged<PaymentMethodFilter?> onMethodChanged;
  final VoidCallback? onRefresh;
  final VoidCallback? onReceive;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 148,
      child: SelloDropdown<PaymentStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(value: PaymentStatusFilter.all, child: Text('All')),
          DropdownMenuItem(
            value: PaymentStatusFilter.completed,
            child: Text('Completed'),
          ),
          DropdownMenuItem(
            value: PaymentStatusFilter.pending,
            child: Text('Pending Review'),
          ),
          DropdownMenuItem(
            value: PaymentStatusFilter.rejected,
            child: Text('Rejected'),
          ),
          DropdownMenuItem(
            value: PaymentStatusFilter.refunded,
            child: Text('Refunded'),
          ),
          DropdownMenuItem(
            value: PaymentStatusFilter.cancelled,
            child: Text('Cancelled'),
          ),
        ],
      ),
    );

    final method = SizedBox(
      width: context.isMobile ? double.infinity : 168,
      child: SelloDropdown<PaymentMethodFilter>(
        value: state.methodFilter,
        compact: true,
        hint: 'Method',
        onChanged: onMethodChanged,
        items: const [
          DropdownMenuItem(
            value: PaymentMethodFilter.all,
            child: Text('All methods'),
          ),
          DropdownMenuItem(
            value: PaymentMethodFilter.cash,
            child: Text('Cash'),
          ),
          DropdownMenuItem(
            value: PaymentMethodFilter.card,
            child: Text('Card'),
          ),
          DropdownMenuItem(
            value: PaymentMethodFilter.bankTransfer,
            child: Text('Bank transfer'),
          ),
          DropdownMenuItem(
            value: PaymentMethodFilter.wallet,
            child: Text('Wallet'),
          ),
          DropdownMenuItem(
            value: PaymentMethodFilter.creditSettlement,
            child: Text('Credit settlement'),
          ),
        ],
      ),
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onRefresh,
    );

    final receive = SelloButton(
      label: 'Receive Payment',
      icon: Icons.add_rounded,
      variant: SelloButtonVariant.primary,
      onPressed: onReceive,
    );

    final search = SelloSearchBar(
      controller: searchController,
      hint: 'Search customer, invoice, reference or mobile…',
      onChanged: onSearchChanged,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      child: context.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpacing.sm),
                status,
                const SizedBox(height: AppSpacing.sm),
                method,
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: refresh),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: receive),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpacing.sm),
                status,
                const SizedBox(width: AppSpacing.sm),
                method,
                const SizedBox(width: AppSpacing.sm),
                refresh,
                const SizedBox(width: AppSpacing.xs),
                receive,
              ],
            ),
    );
  }
}

class _PaymentsSummaryRow extends StatelessWidget {
  const _PaymentsSummaryRow({
    required this.stats,
    required this.currencySymbol,
  });

  final PaymentDashboardStats stats;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Collected today',
          value: SelloFormatters.currency(
            stats.collectedToday,
            symbol: currencySymbol,
          ),
          hint: 'Completed receipts',
          icon: Icons.payments_outlined,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Outstanding',
          value: SelloFormatters.currency(
            stats.outstandingReceivables,
            symbol: currencySymbol,
          ),
          hint: 'Customer receivables',
          icon: Icons.account_balance_wallet_outlined,
          tone: AppColors.finance,
        ),
        SelloStatCard(
          label: 'Wallet issued',
          value: SelloFormatters.currency(
            stats.walletIssued,
            symbol: currencySymbol,
          ),
          hint: 'Store credit on accounts',
          icon: Icons.savings_outlined,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Pending credit',
          value: SelloFormatters.currency(
            stats.pendingCredit,
            symbol: currencySymbol,
          ),
          hint: 'Credit customers owing',
          icon: Icons.credit_score_outlined,
          tone: AppColors.warning,
        ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.hasMore,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final bool hasMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SelloButton(
            label: 'Previous',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.outline,
            onPressed: onPrev,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Page ${page + 1}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          SelloButton(
            label: 'Next',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.outline,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _PendingReviewBanner extends StatelessWidget {
  const _PendingReviewBanner({required this.count, required this.onReview});

  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final label = count == 1
        ? '1 collection awaiting review'
        : '$count collections awaiting review';

    return Material(
      color: AppColors.warning.withValues(alpha: 0.08),
      borderRadius: AppRadius.panelAll,
      child: InkWell(
        onTap: onReview,
        borderRadius: AppRadius.panelAll,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: AppRadius.panelAll,
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                'Review',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.brandAccent,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.brandAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
