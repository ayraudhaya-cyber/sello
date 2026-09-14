import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/payments/application/hub_cheques_provider.dart';
import 'package:sello/features/hub/payments/application/hub_payments_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/payments/presentation/add_existing_cheque_dialog.dart';
import 'package:sello/features/payments/presentation/cheque_details_dialog.dart';
import 'package:sello/features/payments/presentation/payment_details_dialog.dart';
import 'package:sello/features/payments/presentation/receive_payment_dialog.dart';
import 'package:sello/features/payments/presentation/record_cheque_dialog.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

enum _PaymentsWorkspaceTab { payments, cheques }

class HubPaymentsPage extends ConsumerStatefulWidget {
  const HubPaymentsPage({super.key});

  @override
  ConsumerState<HubPaymentsPage> createState() => _HubPaymentsPageState();
}

class _HubPaymentsPageState extends ConsumerState<HubPaymentsPage> {
  final _searchController = TextEditingController();
  final _chequeSearchController = TextEditingController();
  final _bankFilterController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _chequeSearchDebounce;
  Timer? _bankDebounce;
  _PaymentsWorkspaceTab _tab = _PaymentsWorkspaceTab.payments;
  String? _pendingChequeId;
  bool _handledDeepLink = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledDeepLink) return;
    _handledDeepLink = true;
    final query = GoRouterState.of(context).uri.queryParameters;
    if (query['tab'] == 'cheques') {
      _tab = _PaymentsWorkspaceTab.cheques;
    }
    final id = query['id'];
    if (id != null && id.isNotEmpty) {
      _pendingChequeId = id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingChequeId != null) {
          _openChequeById(_pendingChequeId!);
          _pendingChequeId = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _chequeSearchDebounce?.cancel();
    _bankDebounce?.cancel();
    _searchController.dispose();
    _chequeSearchController.dispose();
    _bankFilterController.dispose();
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

  bool _canManageClearance() {
    final permissions = ref.read(permissionServiceProvider);
    if (permissions?.canApprove(AppModule.payments) ?? false) return true;
    final role = ref.read(currentSessionProvider)?.appRole;
    return role == UserRole.owner || role == UserRole.manager;
  }

  bool _canCollectCheques() {
    final permissions = ref.read(permissionServiceProvider);
    if (permissions == null) return true;
    return permissions.canEdit(AppModule.payments) ||
        permissions.canCreate(AppModule.payments) ||
        permissions.canManage(AppModule.payments);
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

  Future<void> _recordCheque() async {
    final input = await showDialog<CreateChequeInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RecordChequeDialog(
        currencySymbol: _currencySymbol(),
      ),
    );
    if (input == null) return;

    final result =
        await ref.read(hubChequesProvider.notifier).createCheque(input);
    if (!mounted) return;
    if (result == null) {
      final message = ref.read(hubChequesProvider).errorMessage;
      SelloSnackbars.error(context, message ?? 'Unable to record cheque.');
    } else {
      SelloSnackbars.success(
        context,
        result.status == ChequeStatus.awaitingCollection
            ? 'Cheque recorded — awaiting collection.'
            : 'Cheque collected.',
      );
    }
  }

  Future<void> _addExistingCheque() async {
    final input = await showDialog<CreateExistingChequeInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddExistingChequeDialog(
        currencySymbol: _currencySymbol(),
      ),
    );
    if (input == null) return;

    final result = await ref
        .read(hubChequesProvider.notifier)
        .createExistingCheque(input);
    if (!mounted) return;
    if (result == null) {
      final message = ref.read(hubChequesProvider).errorMessage;
      SelloSnackbars.error(
        context,
        message ?? 'Unable to save that existing cheque.',
      );
    } else {
      SelloSnackbars.success(
        context,
        'Existing cheque saved — customer balance unchanged.',
      );
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

  Future<void> _openChequeById(String id) async {
    final detail = await ref.read(chequeRepositoryProvider).fetchById(id);
    if (!mounted) return;
    if (detail == null) {
      SelloSnackbars.error(context, 'Unable to load that cheque.');
      return;
    }
    await _openChequeDetails(detail);
  }

  Future<void> _openChequeDetails(ChequeSummary cheque) async {
    final canManage = _canManageClearance();
    final canCollect = _canCollectCheques();
    final currencySymbol = _currencySymbol();

    await showDialog<bool>(
      context: context,
      builder: (context) => ChequeDetailsDialog(
        cheque: cheque,
        currencySymbol: currencySymbol,
        canCollect: canCollect,
        canManageClearance: canManage,
        onCollect: canCollect
            ? (input) async {
                final result = await ref
                    .read(hubChequesProvider.notifier)
                    .collectCheque(input);
                if (result == null) {
                  return ref.read(hubChequesProvider).errorMessage ??
                      'Unable to collect cheque.';
                }
                if (context.mounted) {
                  final label = result.isPendingApproval
                      ? 'Cheque collected — pending approval.'
                      : 'Cheque collected.';
                  SelloSnackbars.success(context, label);
                }
                return null;
              }
            : null,
        onApprove: canManage
            ? () async {
                final error = await ref
                    .read(hubChequesProvider.notifier)
                    .approveChequeCollection(cheque.id);
                if (error == null && context.mounted) {
                  SelloSnackbars.success(
                    context,
                    'Collection approved.',
                  );
                }
                return error;
              }
            : null,
        onDeposit: canManage
            ? () async {
                final error = await ref
                    .read(hubChequesProvider.notifier)
                    .depositCheque(cheque.id);
                if (error == null && context.mounted) {
                  SelloSnackbars.success(context, 'Cheque deposited.');
                }
                return error;
              }
            : null,
        onClear: canManage
            ? () async {
                final error = await ref
                    .read(hubChequesProvider.notifier)
                    .clearCheque(cheque.id);
                if (error == null && context.mounted) {
                  SelloSnackbars.success(context, 'Cheque cleared.');
                }
                return error;
              }
            : null,
        onBounce: canManage
            ? (reason) async {
                final error = await ref
                    .read(hubChequesProvider.notifier)
                    .bounceCheque(cheque.id, reason: reason);
                if (error == null && context.mounted) {
                  SelloSnackbars.success(context, 'Cheque bounced.');
                }
                return error;
              }
            : null,
        onCancel: (canManage ||
                (canCollect &&
                    cheque.status == ChequeStatus.awaitingCollection))
            ? (reason) async {
                final error = await ref
                    .read(hubChequesProvider.notifier)
                    .cancelCheque(cheque.id, reason: reason);
                if (error == null && context.mounted) {
                  SelloSnackbars.success(context, 'Cheque cancelled.');
                }
                return error;
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentState = ref.watch(hubPaymentsProvider);
    final chequeState = ref.watch(hubChequesProvider);
    ref.watch(hubSettingsProvider);
    final currencySymbol = _currencySymbol();

    if (_searchController.text != paymentState.search) {
      _searchController.value = TextEditingValue(
        text: paymentState.search,
        selection: TextSelection.collapsed(offset: paymentState.search.length),
      );
    }
    if (_chequeSearchController.text != chequeState.search) {
      _chequeSearchController.value = TextEditingValue(
        text: chequeState.search,
        selection: TextSelection.collapsed(offset: chequeState.search.length),
      );
    }
    if (_bankFilterController.text != chequeState.bankFilter) {
      _bankFilterController.value = TextEditingValue(
        text: chequeState.bankFilter,
        selection:
            TextSelection.collapsed(offset: chequeState.bankFilter.length),
      );
    }

    return AppPageScaffold(
      title: 'Payments',
      subtitle: _tab == _PaymentsWorkspaceTab.payments
          ? 'Your financial workspace — collect against orders, wallets, and credit.'
          : 'Cheque instruments — collection, deposit, clearance, and bounce.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkspaceTabBar(
            tab: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (_tab == _PaymentsWorkspaceTab.payments)
            ..._buildPaymentsBody(paymentState, currencySymbol)
          else
            ..._buildChequesBody(chequeState, currencySymbol),
        ],
      ),
    );
  }

  List<Widget> _buildPaymentsBody(
    HubPaymentsState state,
    String currencySymbol,
  ) {
    return [
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
        onRecordCheque: state.isSaving
            ? null
            : () {
                setState(() => _tab = _PaymentsWorkspaceTab.cheques);
                _recordCheque();
              },
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
    ];
  }

  List<Widget> _buildChequesBody(
    HubChequesState state,
    String currencySymbol,
  ) {
    return [
      _ChequesToolbar(
        searchController: _chequeSearchController,
        bankController: _bankFilterController,
        state: state,
        onSearchChanged: (value) {
          _chequeSearchDebounce?.cancel();
          _chequeSearchDebounce = Timer(
            const Duration(milliseconds: 300),
            () => ref.read(hubChequesProvider.notifier).setSearch(value),
          );
        },
        onBankChanged: (value) {
          _bankDebounce?.cancel();
          _bankDebounce = Timer(
            const Duration(milliseconds: 300),
            () => ref.read(hubChequesProvider.notifier).setBankFilter(value),
          );
        },
        onStatusChanged: (value) {
          if (value != null) {
            ref.read(hubChequesProvider.notifier).setStatusFilter(value);
          }
        },
        onDueTodayChanged: (value) {
          ref.read(hubChequesProvider.notifier).setDueToday(value);
        },
        onRefresh: state.isLoading
            ? null
            : () => ref.read(hubChequesProvider.notifier).refresh(),
        onRecord: state.isSaving ? null : _recordCheque,
        onAddExisting: state.isSaving ? null : _addExistingCheque,
      ),
      const SizedBox(height: AppSpacing.mdPlus),
      if (state.isLoading && state.items.isEmpty) ...[
        if (context.isMobile)
          const SelloListSkeleton()
        else
          const SelloTableSkeleton(columns: 7),
      ] else ...[
        _ChequesSummaryRow(stats: state.stats),
        const SizedBox(height: AppSpacing.lg),
        if (state.errorMessage != null && state.items.isEmpty)
          SizedBox(
            height: 320,
            child: SelloStateView.error(
              title: 'Unable to load cheques',
              message: state.errorMessage,
              actionLabel: 'Try again',
              onAction: () =>
                  ref.read(hubChequesProvider.notifier).refresh(),
            ),
          )
        else if (state.isEmpty)
          SelloCard(
            child: SelloEmptyState(
              title: 'No cheques yet',
              message:
                  'Record a cheque received in hand or a promised collection. '
                  'Balances update when collected (or after approval when required).',
              icon: Icons.receipt_long_rounded,
              actionLabel: 'Record cheque',
              onAction: _recordCheque,
            ),
          )
        else if (context.isMobile)
          SelloFadeIn(
            child: Column(
              children: [
                for (final cheque in state.items) ...[
                  SelloCard(
                    onTap: () => _openChequeDetails(cheque),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cheque.chequeNumberLabel.isEmpty
                                    ? cheque.chequeNumber
                                    : cheque.chequeNumberLabel,
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _chequeStatusBadge(cheque),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${cheque.customerName ?? 'Customer'} · ${cheque.bankName}',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          SelloFormatters.currency(
                            cheque.amount,
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
                          .read(hubChequesProvider.notifier)
                          .goToPage(state.page - 1),
                  onNext: !state.hasMore
                      ? null
                      : () => ref
                          .read(hubChequesProvider.notifier)
                          .goToPage(state.page + 1),
                ),
              ],
            ),
          )
        else
          SelloFadeIn(
            child: SelloDataTable(
              columns: [
                selloDataColumn('Cheque'),
                selloDataColumn('Customer'),
                selloDataColumn('Bank'),
                selloDataColumn('Amount', numeric: true),
                selloDataColumn('Status'),
                selloDataColumn('Cheque date'),
                selloDataColumn('Collection'),
                selloDataColumn('Actions'),
              ],
              rows: [
                for (final cheque in state.items)
                  DataRow(
                    onSelectChanged: (_) => _openChequeDetails(cheque),
                    cells: [
                      DataCell(
                        SelloTableText(
                          cheque.chequeNumberLabel.isEmpty
                              ? cheque.chequeNumber
                              : cheque.chequeNumberLabel,
                          tone: SelloTableTone.strong,
                        ),
                      ),
                      DataCell(
                        SelloTableText(
                          cheque.customerName ?? '—',
                          tone: SelloTableTone.strong,
                        ),
                      ),
                      DataCell(SelloTableText(cheque.bankName)),
                      DataCell(
                        SelloTableText(
                          SelloFormatters.currency(
                            cheque.amount,
                            symbol: currencySymbol,
                          ),
                          tone: SelloTableTone.strong,
                          numeric: true,
                        ),
                      ),
                      DataCell(_chequeStatusBadge(cheque)),
                      DataCell(
                        SelloTableText(
                          SelloFormatters.date(cheque.chequeDate),
                          tone: SelloTableTone.muted,
                        ),
                      ),
                      DataCell(
                        SelloTableText(
                          cheque.collectionDate == null
                              ? '—'
                              : SelloFormatters.date(cheque.collectionDate),
                          tone: cheque.collectionDate == null
                              ? SelloTableTone.muted
                              : SelloTableTone.normal,
                        ),
                      ),
                      DataCell(
                        SelloButton(
                          label: 'View',
                          size: SelloButtonSize.small,
                          variant: SelloButtonVariant.ghost,
                          onPressed: () => _openChequeDetails(cheque),
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
                        .read(hubChequesProvider.notifier)
                        .goToPage(state.page - 1),
                onNext: !state.hasMore
                    ? null
                    : () => ref
                        .read(hubChequesProvider.notifier)
                        .goToPage(state.page + 1),
              ),
            ),
          ),
      ],
    ];
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
      PaymentRecordStatus.rejected =>
        SelloStatusTone.danger,
    },
  );
}

Widget _chequeStatusBadge(ChequeSummary cheque) {
  return SelloStatusBadge(
    label: cheque.displayLabel,
    tone: switch (cheque.status) {
      ChequeStatus.awaitingCollection => SelloStatusTone.warning,
      ChequeStatus.collected when cheque.isPendingApproval =>
        SelloStatusTone.warning,
      ChequeStatus.collected || ChequeStatus.deposited => SelloStatusTone.info,
      ChequeStatus.cleared => SelloStatusTone.success,
      ChequeStatus.bounced || ChequeStatus.cancelled => SelloStatusTone.danger,
    },
  );
}

class _WorkspaceTabBar extends StatelessWidget {
  const _WorkspaceTabBar({required this.tab, required this.onChanged});

  final _PaymentsWorkspaceTab tab;
  final ValueChanged<_PaymentsWorkspaceTab> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _PaymentsWorkspaceTab value) {
      final selected = tab == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(value),
        selectedColor: context.brandAccentContainer,
        labelStyle: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w600,
          color: selected ? context.brandAccent : AppColors.textSecondary,
        ),
        side: BorderSide(
          color: selected
              ? context.brandAccent.withValues(alpha: 0.35)
              : AppColors.outlinePanel,
        ),
        backgroundColor: AppColors.surface,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        children: [
          chip('Payments', _PaymentsWorkspaceTab.payments),
          chip('Cheques', _PaymentsWorkspaceTab.cheques),
        ],
      ),
    );
  }
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
    this.onRecordCheque,
  });

  final TextEditingController searchController;
  final HubPaymentsState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PaymentStatusFilter?> onStatusChanged;
  final ValueChanged<PaymentMethodFilter?> onMethodChanged;
  final VoidCallback? onRefresh;
  final VoidCallback? onReceive;
  final VoidCallback? onRecordCheque;

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
          DropdownMenuItem(
            value: PaymentMethodFilter.cheque,
            child: Text('Cheque'),
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

    final cheque = SelloButton(
      label: 'Record cheque',
      icon: Icons.receipt_long_outlined,
      variant: SelloButtonVariant.outline,
      onPressed: onRecordCheque,
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
                if (onRecordCheque != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  cheque,
                ],
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
                if (onRecordCheque != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  cheque,
                ],
                const SizedBox(width: AppSpacing.xs),
                receive,
              ],
            ),
    );
  }
}

class _ChequesToolbar extends StatelessWidget {
  const _ChequesToolbar({
    required this.searchController,
    required this.bankController,
    required this.state,
    required this.onSearchChanged,
    required this.onBankChanged,
    required this.onStatusChanged,
    required this.onDueTodayChanged,
    required this.onRefresh,
    required this.onRecord,
    required this.onAddExisting,
  });

  final TextEditingController searchController;
  final TextEditingController bankController;
  final HubChequesState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onBankChanged;
  final ValueChanged<ChequeStatusFilter?> onStatusChanged;
  final ValueChanged<bool> onDueTodayChanged;
  final VoidCallback? onRefresh;
  final VoidCallback? onRecord;
  final VoidCallback? onAddExisting;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 168,
      child: SelloDropdown<ChequeStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(
            value: ChequeStatusFilter.all,
            child: Text('All'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.awaitingCollection,
            child: Text('Awaiting'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.pendingApproval,
            child: Text('Pending approval'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.collected,
            child: Text('Collected'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.deposited,
            child: Text('Deposited'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.cleared,
            child: Text('Cleared'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.bounced,
            child: Text('Bounced'),
          ),
          DropdownMenuItem(
            value: ChequeStatusFilter.cancelled,
            child: Text('Cancelled'),
          ),
        ],
      ),
    );

    final bank = SizedBox(
      width: context.isMobile ? double.infinity : 140,
      child: SelloTextField(
        controller: bankController,
        label: null,
        hint: 'Bank…',
        onChanged: onBankChanged,
      ),
    );

    final dueToday = FilterChip(
      label: const Text('Due today'),
      selected: state.dueToday,
      onSelected: onDueTodayChanged,
      selectedColor: context.brandAccentContainer,
      labelStyle: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontWeight: FontWeight.w600,
        color: state.dueToday ? context.brandAccent : AppColors.textSecondary,
      ),
      side: BorderSide(
        color: state.dueToday
            ? context.brandAccent.withValues(alpha: 0.35)
            : AppColors.outlinePanel,
      ),
      backgroundColor: AppColors.surface,
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onRefresh,
    );

    final record = SelloButton(
      label: 'Record cheque',
      icon: Icons.add_rounded,
      variant: SelloButtonVariant.primary,
      onPressed: onRecord,
    );

    final existing = SelloButton(
      label: 'Add existing cheque',
      icon: Icons.history_edu_outlined,
      variant: SelloButtonVariant.outline,
      onPressed: onAddExisting,
    );

    final search = SelloSearchBar(
      controller: searchController,
      hint: 'Search customer, cheque no, bank or holder…',
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
                bank,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: dueToday),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: refresh),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: record),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                existing,
              ],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: AppSpacing.sm),
                status,
                const SizedBox(width: AppSpacing.sm),
                bank,
                const SizedBox(width: AppSpacing.sm),
                dueToday,
                const SizedBox(width: AppSpacing.sm),
                refresh,
                const SizedBox(width: AppSpacing.xs),
                existing,
                const SizedBox(width: AppSpacing.xs),
                record,
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

class _ChequesSummaryRow extends StatelessWidget {
  const _ChequesSummaryRow({required this.stats});

  final ChequeDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Awaiting',
          value: '${stats.awaitingCollection}',
          hint: 'Not yet collected',
          icon: Icons.schedule_rounded,
          tone: AppColors.warning,
        ),
        SelloStatCard(
          label: 'Due today',
          value: '${stats.dueToday}',
          hint: 'Collection due',
          icon: Icons.today_rounded,
          tone: AppColors.finance,
        ),
        SelloStatCard(
          label: 'Pending approval',
          value: '${stats.pendingApproval}',
          hint: 'Awaiting Hub review',
          icon: Icons.hourglass_top_rounded,
          tone: AppColors.warning,
        ),
        SelloStatCard(
          label: 'Collected',
          value: '${stats.collected}',
          hint: 'Pending clearance',
          icon: Icons.inbox_outlined,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Deposited',
          value: '${stats.deposited}',
          hint: 'At the bank',
          icon: Icons.account_balance_outlined,
          tone: AppColors.info,
        ),
        SelloStatCard(
          label: 'Cleared',
          value: '${stats.cleared}',
          hint: 'Cleared by bank',
          icon: Icons.verified_outlined,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Bounced',
          value: '${stats.bounced}',
          hint: 'Returned unpaid',
          icon: Icons.undo_rounded,
          tone: AppColors.error,
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
