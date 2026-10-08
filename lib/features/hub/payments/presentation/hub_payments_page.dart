import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/collections/application/sales_rep_options_provider.dart';
import 'package:sello/features/collections/presentation/collections_export_dialog.dart';
import 'package:sello/features/hub/payments/application/hub_cheques_provider.dart';
import 'package:sello/features/hub/payments/application/hub_payments_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/features/payments/presentation/add_existing_cheque_dialog.dart';
import 'package:sello/features/payments/presentation/cheque_details_dialog.dart';
import 'package:sello/features/corrections/application/correction_rules.dart';
import 'package:sello/features/corrections/presentation/correct_payment_dialog.dart';
import 'package:sello/features/corrections/presentation/edit_cheque_details_dialog.dart';
import 'package:sello/features/payments/presentation/payment_details_dialog.dart';
import 'package:sello/features/payments/presentation/receive_payment_dialog.dart';
import 'package:sello/features/payments/presentation/record_cheque_dialog.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/employee_summary.dart';
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
  final _selectedDepositIds = <String>{};
  final _selectedApprovalIds = <String>{};

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

  bool _canCorrectFinancials() {
    return ref.read(permissionServiceProvider)?.canCorrectFinancials ?? false;
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
      builder: (context) =>
          RecordChequeDialog(currencySymbol: _currencySymbol()),
    );
    if (input == null) return;

    final result = await ref
        .read(hubChequesProvider.notifier)
        .createCheque(input);
    if (!mounted) return;
    if (result == null) {
      final message = ref.read(hubChequesProvider).errorMessage;
      SelloSnackbars.error(context, message ?? 'Unable to record cheque.');
    } else {
      SelloSnackbars.success(
        context,
        result.status == ChequeStatus.awaitingCollection
            ? 'Saved. We do not have this cheque yet.'
            : 'Cheque received.',
      );
    }
  }

  Future<void> _addExistingCheque() async {
    final input = await showDialog<CreateExistingChequeInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AddExistingChequeDialog(currencySymbol: _currencySymbol()),
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
        onCorrect:
            _canCorrectFinancials() &&
                PaymentCorrectionRules.canCorrect(detail.summary.status)
            ? () async {
                final corrected = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => CorrectPaymentDialog(
                    detail: detail,
                    currencySymbol: _currencySymbol(),
                  ),
                );
                if (corrected == true && context.mounted) {
                  Navigator.of(context).maybePop();
                  ref.read(hubPaymentsProvider.notifier).refresh();
                  if (mounted) {
                    SelloSnackbars.success(context, 'Payment corrected.');
                  }
                }
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
                      'Could not mark this cheque as received.';
                }
                if (context.mounted) {
                  final label = result.isPendingApproval
                      ? 'Cheque received. Waiting for owner approval.'
                      : 'Cheque received.';
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
                  SelloSnackbars.success(context, 'Payment approved.');
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
                  SelloSnackbars.success(context, 'Cheque taken to the bank.');
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
                  SelloSnackbars.success(context, 'Bank paid this cheque.');
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
                  SelloSnackbars.success(context, 'Bank returned this cheque.');
                }
                return error;
              }
            : null,
        onCancel:
            (canManage ||
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
        onEditDetails:
            ChequeCorrectionRules.canEditDetails(
              status: cheque.status,
              isHubFinancialRole: _canCorrectFinancials(),
              isOwnCheque:
                  cheque.employeeId ==
                  (ref.read(currentSessionProvider)?.employee.id ?? ''),
            )
            ? () async {
                final saved = await showDialog<bool>(
                  context: context,
                  builder: (context) => EditChequeDetailsDialog(cheque: cheque),
                );
                if (saved == true && context.mounted) {
                  Navigator.of(context).maybePop();
                  ref.read(hubChequesProvider.notifier).refresh();
                  if (mounted) {
                    SelloSnackbars.success(context, 'Cheque details updated.');
                  }
                }
              }
            : null,
      ),
    );
  }

  ChequeForwardAction? _nextChequeAction(ChequeSummary cheque) {
    return chequeNextForwardAction(
      cheque: cheque,
      canCollect: _canCollectCheques(),
      canManageClearance: _canManageClearance(),
    );
  }

  Future<void> _collectChequeDirect(ChequeSummary cheque) async {
    var allocations = const <PaymentAllocationInput>[];
    if (!chequeCollectPreservesExistingAllocation(cheque)) {
      try {
        final orders = await ref
            .read(paymentRepositoryProvider)
            .fetchReceivableOrders(cheque.customerId);
        allocations = fifoChequeAllocations(
          amount: cheque.amount,
          orders: orders,
        );
      } on AppFailure catch (failure) {
        if (!mounted) return;
        SelloSnackbars.error(context, failure.message);
        return;
      }
    }

    final result = await ref
        .read(hubChequesProvider.notifier)
        .collectCheque(
          CollectChequeInput(
            chequeId: cheque.id,
            collectionDate: DateTime.now(),
            allocations: allocations,
            photoPath: cheque.photoPath,
            notes: cheque.notes,
          ),
        );
    if (!mounted) return;
    if (result == null) {
      final message = ref.read(hubChequesProvider).errorMessage;
      SelloSnackbars.error(
        context,
        message ?? 'Could not mark this cheque as received.',
      );
      return;
    }
    SelloSnackbars.success(
      context,
      result.isPendingApproval
          ? 'Cheque received. Waiting for owner approval.'
          : 'Cheque received.',
    );
  }

  Future<void> _approveChequeDirect(ChequeSummary cheque) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => SelloFormDialog(
        title: 'Approve this cheque',
        subtitle:
            'This will reduce what the customer still owes. Do this only once.',
        maxWidth: 440,
        body: const SizedBox.shrink(),
        footer: SelloDialogFooter(
          cancelLabel: 'Cancel',
          cancelVariant: SelloButtonVariant.outline,
          onCancel: () => Navigator.of(context).pop(false),
          primaryLabel: 'Approve',
          onPrimary: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final error = await ref
        .read(hubChequesProvider.notifier)
        .approveChequeCollection(cheque.id);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    SelloSnackbars.success(context, 'Payment approved.');
  }

  Future<void> _runListForward(ChequeSummary cheque) async {
    final next = _nextChequeAction(cheque);
    if (next == null) {
      await _openChequeDetails(cheque);
      return;
    }
    switch (next) {
      case ChequeForwardAction.collect:
        await _collectChequeDirect(cheque);
      case ChequeForwardAction.approve:
        await _approveChequeDirect(cheque);
      case ChequeForwardAction.deposit:
        final error = await ref
            .read(hubChequesProvider.notifier)
            .depositCheque(cheque.id);
        if (!mounted) return;
        if (error != null) {
          SelloSnackbars.error(context, error);
          return;
        }
        SelloSnackbars.success(context, 'Cheque taken to the bank.');
      case ChequeForwardAction.clear:
        final error = await ref
            .read(hubChequesProvider.notifier)
            .clearCheque(cheque.id);
        if (!mounted) return;
        if (error != null) {
          SelloSnackbars.error(context, error);
          return;
        }
        SelloSnackbars.success(context, 'Bank paid this cheque.');
    }
  }

  bool _canReviewCollections() =>
      ref.read(permissionServiceProvider)?.canApprove(AppModule.payments) ??
      false;

  void _toggleApprovalSelection(PaymentSummary payment) {
    if (!payment.status.isPendingReview) return;
    setState(() {
      if (!_selectedApprovalIds.add(payment.id)) {
        _selectedApprovalIds.remove(payment.id);
      }
    });
  }

  Future<void> _approveInline(PaymentSummary payment) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Approve collection?',
      message:
          '${payment.customerName ?? 'Customer'} · '
          '${SelloFormatters.currency(payment.amount, symbol: _currencySymbol())}'
          '${payment.employeeName == null ? '' : ' · collected by ${payment.employeeName}'}.\n\n'
          'The customer balance and order payments update now.',
      confirmLabel: 'Approve',
    );
    if (confirmed != true || !mounted) return;
    final error = await ref
        .read(hubPaymentsProvider.notifier)
        .approveCollection(payment.id);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    setState(() => _selectedApprovalIds.remove(payment.id));
    SelloSnackbars.success(context, 'Collection approved.');
  }

  Future<void> _rejectInline(PaymentSummary payment) async {
    final result = await showRejectCollectionDialog(context);
    if (result == null || !mounted) return;
    final error = await ref
        .read(hubPaymentsProvider.notifier)
        .rejectCollection(payment.id, reason: result.reason);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    setState(() => _selectedApprovalIds.remove(payment.id));
    SelloSnackbars.success(context, 'Collection rejected.');
  }

  Future<void> _approveSelected() async {
    final selected = ref
        .read(hubPaymentsProvider)
        .items
        .where(
          (p) =>
              _selectedApprovalIds.contains(p.id) && p.status.isPendingReview,
        )
        .toList(growable: false);
    if (selected.isEmpty) return;
    final total = selected.fold<num>(0, (sum, p) => sum + p.amount);
    final confirmed = await showSelloDialog(
      context: context,
      title: selected.length == 1
          ? 'Approve 1 collection?'
          : 'Approve ${selected.length} collections?',
      message:
          'Total ${SelloFormatters.currency(total, symbol: _currencySymbol())}. '
          'Customer balances and order payments update now.',
      confirmLabel: 'Approve all',
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(hubPaymentsProvider.notifier)
        .approveCollections([for (final p in selected) p.id]);
    if (!mounted) return;
    setState(_selectedApprovalIds.clear);
    if (result.error != null) {
      SelloSnackbars.error(
        context,
        '${result.approved} approved. Stopped: ${result.error}',
      );
      return;
    }
    SelloSnackbars.success(
      context,
      result.approved == 1
          ? 'Collection approved.'
          : '${result.approved} collections approved.',
    );
  }

  void _toggleDepositSelection(ChequeSummary cheque) {
    if (!chequeEligibleForBatchDeposit(cheque) || !_canManageClearance()) {
      return;
    }
    setState(() {
      if (!_selectedDepositIds.add(cheque.id)) {
        _selectedDepositIds.remove(cheque.id);
      }
    });
  }

  Future<void> _depositSelected() async {
    final ids = ref
        .read(hubChequesProvider)
        .items
        .where(
          (cheque) =>
              _selectedDepositIds.contains(cheque.id) &&
              chequeEligibleForBatchDeposit(cheque),
        )
        .map((cheque) => cheque.id)
        .toList(growable: false);
    if (ids.isEmpty) return;
    final error = await ref
        .read(hubChequesProvider.notifier)
        .depositCheques(ids);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      return;
    }
    setState(_selectedDepositIds.clear);
    SelloSnackbars.success(
      context,
      ids.length == 1
          ? 'Cheque taken to the bank.'
          : '${ids.length} cheques taken to the bank.',
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
        selection: TextSelection.collapsed(
          offset: chequeState.bankFilter.length,
        ),
      );
    }

    return AppPageScaffold(
      title: 'Payments',
      subtitle: _tab == _PaymentsWorkspaceTab.payments
          ? 'Collect money against orders and opening balances.'
          : 'Cheques from Sales Reps appear here automatically. Use Add existing cheque only for old cheques from before Sello.',
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
    final canReview = _canReviewCollections();
    final showApprovalSelect =
        canReview && state.items.any((p) => p.status.isPendingReview);
    final selectedPending = state.items
        .where(
          (p) =>
              _selectedApprovalIds.contains(p.id) && p.status.isPendingReview,
        )
        .toList(growable: false);
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
        salesReps: ref.watch(salesRepOptionsProvider).value ?? const [],
        onSalesRepChanged: (value) =>
            ref.read(hubPaymentsProvider.notifier).setEmployeeFilter(value),
        onExport: () => showDialog<void>(
          context: context,
          builder: (_) =>
              CollectionsExportDialog(initialEmployeeId: state.employeeId),
        ),
        onRefresh: state.isLoading
            ? null
            : () => ref.read(hubPaymentsProvider.notifier).refresh(),
        onReceive: state.isSaving ? null : _receivePayment,
      ),
      const SizedBox(height: AppSpacing.mdPlus),
      SelloClearFiltersBar(
        visible: state.hasActiveFilters,
        onClear: () {
          _searchController.clear();
          ref.read(hubPaymentsProvider.notifier).clearFilters();
        },
      ),
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
      if (selectedPending.isNotEmpty) ...[
        _ApprovalSelectionBar(
          count: selectedPending.length,
          total: SelloFormatters.currency(
            selectedPending.fold<num>(0, (sum, p) => sum + p.amount),
            symbol: currencySymbol,
          ),
          onClear: () => setState(_selectedApprovalIds.clear),
          onApprove: state.isSaving ? null : _approveSelected,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (state.errorMessage != null && state.items.isNotEmpty) ...[
        SelloInlineErrorBar(
          message: state.errorMessage,
          onRetry: () => ref.read(hubPaymentsProvider.notifier).refresh(),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (state.isLoading && state.items.isEmpty) ...[
        if (context.isMobile)
          const SelloListSkeleton()
        else
          const SelloTableSkeleton(columns: 8),
      ] else ...[
        _PaymentsSummaryRow(stats: state.stats, currencySymbol: currencySymbol),
        const SizedBox(height: AppSpacing.lg),
        if (state.errorMessage != null && state.items.isEmpty)
          SizedBox(
            height: 320,
            child: SelloStateView.error(
              title: 'Unable to load payments',
              message: state.errorMessage,
              actionLabel: 'Try again',
              onAction: () => ref.read(hubPaymentsProvider.notifier).refresh(),
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
                            if (showApprovalSelect &&
                                payment.status.isPendingReview) ...[
                              Checkbox(
                                value: _selectedApprovalIds.contains(
                                  payment.id,
                                ),
                                visualDensity: VisualDensity.compact,
                                onChanged: (_) =>
                                    _toggleApprovalSelection(payment),
                              ),
                              const SizedBox(width: 4),
                            ],
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
                            _statusBadge(payment),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          payment.employeeName == null
                              ? (payment.customerName ?? 'Customer')
                              : '${payment.customerName ?? 'Customer'} · '
                                    '${payment.employeeName}',
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
                        if (canReview && payment.status.isPendingReview) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SelloButton(
                                  label: 'Reject',
                                  variant: SelloButtonVariant.outline,
                                  expanded: true,
                                  onPressed: state.isSaving
                                      ? null
                                      : () => _rejectInline(payment),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelloButton(
                                  label: 'Approve',
                                  icon: Icons.check_rounded,
                                  expanded: true,
                                  onPressed: state.isSaving
                                      ? null
                                      : () => _approveInline(payment),
                                ),
                              ),
                            ],
                          ),
                        ],
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
              flexColumnIndex: showApprovalSelect ? 2 : 1,
              columns: [
                if (showApprovalSelect) selloSelectDataColumn(),
                selloDataColumn('Payment #'),
                selloDataColumn('Customer'),
                selloDataColumn('Paid for'),
                selloDataColumn('Method'),
                selloDataColumn('Amount', numeric: true),
                selloDataColumn('Status'),
                selloDataColumn('Collected by'),
                selloDataColumn('Date'),
                selloDataColumn('Actions'),
              ],
              rows: [
                for (final payment in state.items)
                  DataRow(
                    onSelectChanged: (_) => _openDetails(payment),
                    cells: [
                      if (showApprovalSelect)
                        DataCell(
                          payment.status.isPendingReview
                              ? Checkbox(
                                  value: _selectedApprovalIds.contains(
                                    payment.id,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (_) =>
                                      _toggleApprovalSelection(payment),
                                )
                              : const SizedBox.shrink(),
                        ),
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
                          payment.allocationSummary.isNotEmpty
                              ? payment.allocationSummary
                              : (payment.relatedOrderNumber ?? '—'),
                          tone:
                              payment.allocationSummary.isEmpty &&
                                  payment.relatedOrderNumber == null
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
                      DataCell(_statusBadge(payment)),
                      DataCell(SelloTableText(payment.employeeName ?? '—')),
                      DataCell(
                        SelloTableText(
                          SelloFormatters.date(payment.receivedAt),
                          tone: SelloTableTone.muted,
                        ),
                      ),
                      DataCell(
                        SelloRowIconGroup(
                          children: [
                            if (canReview &&
                                payment.status.isPendingReview) ...[
                              SelloRowIconButton(
                                tooltip: 'Approve collection',
                                icon: Icons.check_circle_outline_rounded,
                                onPressed: () => _approveInline(payment),
                              ),
                              SelloRowIconButton(
                                tooltip: 'Reject collection',
                                icon: Icons.highlight_off_rounded,
                                onPressed: () => _rejectInline(payment),
                              ),
                            ],
                            SelloRowIconButton(
                              tooltip: 'View payment',
                              icon: Icons.visibility_outlined,
                              onPressed: () => _openDetails(payment),
                            ),
                            if (_canCorrectFinancials() &&
                                PaymentCorrectionRules.canCorrect(
                                  payment.status,
                                ))
                              SelloRowIconButton(
                                tooltip: 'Correct payment',
                                icon: Icons.edit_outlined,
                                onPressed: () => _openDetails(payment),
                              ),
                          ],
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

  List<Widget> _buildChequesBody(HubChequesState state, String currencySymbol) {
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
        selectedDepositCount: state.items
            .where(
              (cheque) =>
                  _selectedDepositIds.contains(cheque.id) &&
                  chequeEligibleForBatchDeposit(cheque),
            )
            .length,
        onDepositSelected: !_canManageClearance() || state.isSaving
            ? null
            : _depositSelected,
      ),
      const SizedBox(height: AppSpacing.mdPlus),
      SelloClearFiltersBar(
        visible: state.hasActiveFilters,
        onClear: () {
          _chequeSearchController.clear();
          _bankFilterController.clear();
          ref.read(hubChequesProvider.notifier).clearFilters();
        },
      ),
      if (state.isLoading && state.items.isEmpty) ...[
        if (context.isMobile)
          const SelloListSkeleton()
        else
          const SelloTableSkeleton(columns: 7),
      ] else ...[
        _ChequesSummaryRow(stats: state.stats),
        const SizedBox(height: AppSpacing.lg),
        if (state.errorMessage != null && state.items.isNotEmpty)
          SelloInlineErrorBar(
            message: state.errorMessage,
            onRetry: () => ref.read(hubChequesProvider.notifier).refresh(),
          ),
        if (state.errorMessage != null && state.items.isEmpty)
          SizedBox(
            height: 320,
            child: SelloStateView.error(
              title: 'Unable to load cheques',
              message: state.errorMessage,
              actionLabel: 'Try again',
              onAction: () => ref.read(hubChequesProvider.notifier).refresh(),
            ),
          )
        else if (state.isEmpty)
          SelloCard(
            child: SelloEmptyState(
              title: 'No cheques yet',
              message:
                  'Cheques your team records appear here. Add a promised cheque, '
                  'or an old cheque from before Sello. What they owe updates when '
                  'you receive it (or after approval).',
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
                            if (_canManageClearance() &&
                                chequeEligibleForBatchDeposit(cheque)) ...[
                              Checkbox(
                                value: _selectedDepositIds.contains(cheque.id),
                                visualDensity: VisualDensity.compact,
                                onChanged: (_) =>
                                    _toggleDepositSelection(cheque),
                              ),
                              const SizedBox(width: 4),
                            ],
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
                        if (_nextChequeAction(cheque) != null) ...[
                          const SizedBox(height: 12),
                          SelloButton(
                            label: chequeForwardActionLabel(
                              _nextChequeAction(cheque)!,
                            ),
                            tooltip: chequeForwardActionHint(
                              _nextChequeAction(cheque)!,
                            ),
                            expanded: true,
                            onPressed: state.isSaving
                                ? null
                                : () => _runListForward(cheque),
                          ),
                        ],
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
              flexColumnIndex: 1,
              columns: [
                selloSelectDataColumn(),
                selloDataColumn('Cheque'),
                selloDataColumn('Customer'),
                selloDataColumn('Bank'),
                selloDataColumn('Amount', numeric: true),
                selloDataColumn('Status'),
                selloDataColumn('Cheque date'),
                selloDataColumn('Received'),
                selloDataColumn('Actions'),
              ],
              rows: [
                for (final cheque in state.items)
                  DataRow(
                    cells: [
                      DataCell(
                        chequeEligibleForBatchDeposit(cheque) &&
                                _canManageClearance()
                            ? Checkbox(
                                value: _selectedDepositIds.contains(cheque.id),
                                visualDensity: VisualDensity.compact,
                                onChanged: (_) =>
                                    _toggleDepositSelection(cheque),
                              )
                            : const SizedBox.shrink(),
                      ),
                      DataCell(
                        SelloTableText(
                          cheque.chequeNumberLabel.isEmpty
                              ? cheque.chequeNumber
                              : cheque.chequeNumberLabel,
                          tone: SelloTableTone.strong,
                        ),
                        onTap: () => _openChequeDetails(cheque),
                      ),
                      DataCell(
                        SelloTableText(
                          cheque.customerName ?? '—',
                          tone: SelloTableTone.strong,
                        ),
                        onTap: () => _openChequeDetails(cheque),
                      ),
                      DataCell(
                        SelloTableText(cheque.bankName),
                        onTap: () => _openChequeDetails(cheque),
                      ),
                      DataCell(
                        SelloTableText(
                          SelloFormatters.currency(
                            cheque.amount,
                            symbol: currencySymbol,
                          ),
                          tone: SelloTableTone.strong,
                          numeric: true,
                        ),
                        onTap: () => _openChequeDetails(cheque),
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
                        SelloRowIconGroup(
                          children: [
                            SelloRowIconButton(
                              tooltip: 'View cheque',
                              icon: Icons.visibility_outlined,
                              onPressed: () => _openChequeDetails(cheque),
                            ),
                            if (ChequeCorrectionRules.canEditDetails(
                              status: cheque.status,
                              isHubFinancialRole: _canCorrectFinancials(),
                              isOwnCheque:
                                  cheque.employeeId ==
                                  (ref
                                          .read(currentSessionProvider)
                                          ?.employee
                                          .id ??
                                      ''),
                            ))
                              SelloRowIconButton(
                                tooltip: 'Edit details',
                                icon: Icons.edit_outlined,
                                onPressed: () => _openChequeDetails(cheque),
                              ),
                            if (_nextChequeAction(cheque) != null)
                              SelloRowIconButton(
                                tooltip: chequeForwardActionHint(
                                  _nextChequeAction(cheque)!,
                                ),
                                icon: Icons.arrow_forward_rounded,
                                onPressed: state.isSaving
                                    ? () {}
                                    : () => _runListForward(cheque),
                              ),
                          ],
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

Widget _statusBadge(PaymentSummary payment) {
  return SelloStatusBadge(
    label: payment.displayStatusLabel,
    tone: switch (payment.status) {
      PaymentRecordStatus.completed => SelloStatusTone.success,
      PaymentRecordStatus.pending => SelloStatusTone.warning,
      PaymentRecordStatus.refunded => SelloStatusTone.info,
      PaymentRecordStatus.cancelled || PaymentRecordStatus.rejected =>
        payment.isCorrected ? SelloStatusTone.info : SelloStatusTone.danger,
    },
  );
}

Widget _chequeStatusBadge(ChequeSummary cheque) {
  return Tooltip(
    message: cheque.statusHelpText,
    child: SelloStatusBadge(
      label: cheque.displayLabel,
      tone: switch (cheque.status) {
        ChequeStatus.awaitingCollection => SelloStatusTone.warning,
        ChequeStatus.collected when cheque.isPendingApproval =>
          SelloStatusTone.warning,
        ChequeStatus.collected ||
        ChequeStatus.deposited => SelloStatusTone.info,
        ChequeStatus.cleared => SelloStatusTone.success,
        ChequeStatus.bounced ||
        ChequeStatus.cancelled => SelloStatusTone.danger,
      },
    ),
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
    required this.salesReps,
    required this.onSalesRepChanged,
    required this.onExport,
    required this.onRefresh,
    required this.onReceive,
  });

  final TextEditingController searchController;
  final HubPaymentsState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PaymentStatusFilter?> onStatusChanged;
  final ValueChanged<PaymentMethodFilter?> onMethodChanged;
  final List<EmployeeSummary> salesReps;
  final ValueChanged<String?> onSalesRepChanged;
  final VoidCallback? onExport;
  final VoidCallback? onRefresh;
  final VoidCallback? onReceive;

  @override
  Widget build(BuildContext context) {
    final knownRep = salesReps.any((rep) => rep.id == state.employeeId);
    final salesRep = SizedBox(
      width: context.isMobile ? double.infinity : 176,
      child: SelloDropdown<String>(
        value: knownRep ? state.employeeId! : '',
        compact: true,
        hint: 'Sales rep',
        onChanged: (value) =>
            onSalesRepChanged(value == null || value.isEmpty ? null : value),
        items: [
          const DropdownMenuItem(value: '', child: Text('All sales reps')),
          for (final rep in salesReps)
            DropdownMenuItem(value: rep.id, child: Text(rep.fullName)),
        ],
      ),
    );

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

    final export = SelloButton(
      label: 'Export',
      icon: Icons.download_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onExport,
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
      child: SelloToolbarBody(
        search: search,
        filters: [status, method, salesRep],
        actions: [export, refresh, receive],
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
    this.selectedDepositCount = 0,
    this.onDepositSelected,
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
  final int selectedDepositCount;
  final VoidCallback? onDepositSelected;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 196,
      child: SelloDropdown<ChequeStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: [
          for (final filter in ChequeStatusFilter.values)
            DropdownMenuItem(value: filter, child: Text(filter.label)),
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

    final depositSelected = selectedDepositCount <= 0
        ? null
        : SelloButton(
            label: 'Take to bank ($selectedDepositCount)',
            icon: Icons.account_balance_outlined,
            tooltip: chequeBatchDepositHint,
            onPressed: onDepositSelected,
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
      child: SelloToolbarBody(
        search: search,
        filters: [status, bank, dueToday],
        actions: [refresh, ?depositSelected, existing, record],
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
          hint: 'All customers still owing',
          icon: Icons.account_balance_wallet_outlined,
          tone: AppColors.finance,
        ),
        SelloStatCard(
          label: 'Wallet issued',
          value: SelloFormatters.currency(
            stats.walletIssued,
            symbol: currencySymbol,
          ),
          hint: 'Credit sitting on customer wallets',
          icon: Icons.savings_outlined,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Credit owing',
          value: SelloFormatters.currency(
            stats.pendingCredit,
            symbol: currencySymbol,
          ),
          hint: 'Only customers allowed to buy on credit',
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
          label: 'Waiting',
          value: '${stats.awaitingCollection}',
          hint: 'Not received yet',
          icon: Icons.schedule_rounded,
          tone: AppColors.warning,
        ),
        SelloStatCard(
          label: 'Due today',
          value: '${stats.dueToday}',
          hint: 'Receive today',
          icon: Icons.today_rounded,
          tone: AppColors.finance,
        ),
        SelloStatCard(
          label: 'Needs approval',
          value: '${stats.pendingApproval}',
          hint: 'Owner must check',
          icon: Icons.hourglass_top_rounded,
          tone: AppColors.warning,
        ),
        SelloStatCard(
          label: 'In hand',
          value: '${stats.collected}',
          hint: 'Take to your bank',
          icon: Icons.inbox_outlined,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'At the bank',
          value: '${stats.deposited}',
          hint: 'Waiting on the bank',
          icon: Icons.account_balance_outlined,
          tone: AppColors.info,
        ),
        SelloStatCard(
          label: 'Bank paid',
          value: '${stats.cleared}',
          hint: 'Money received',
          icon: Icons.verified_outlined,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Bank returned',
          value: '${stats.bounced}',
          hint: 'Cheque did not pay',
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

class _ApprovalSelectionBar extends StatelessWidget {
  const _ApprovalSelectionBar({
    required this.count,
    required this.total,
    required this.onClear,
    required this.onApprove,
  });

  final int count;
  final String total;
  final VoidCallback onClear;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 selected' : '$count selected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.brandAccent.withValues(alpha: 0.06),
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: context.brandAccent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label · $total',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear')),
          const SizedBox(width: 6),
          SelloButton(
            label: context.isMobile ? 'Approve' : 'Approve selected',
            icon: Icons.done_all_rounded,
            size: SelloButtonSize.small,
            onPressed: onApprove,
          ),
        ],
      ),
    );
  }
}
