import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/customers/application/hub_customers_provider.dart';
import 'package:sello/features/corrections/presentation/correct_opening_balance_dialog.dart';
import 'package:sello/features/customers/application/customers_excel_exporter.dart';
import 'package:sello/features/customers/presentation/add_opening_balance_dialog.dart';
import 'package:sello/features/customers/presentation/customer_details_dialog.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/payments/presentation/add_existing_cheque_dialog.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/quick_actions/quick_actions_launcher.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/customer_receivable_adjustment.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/utils/browser_file_download.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/utils/quick_new_query.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubCustomersPage extends ConsumerStatefulWidget {
  const HubCustomersPage({super.key});

  @override
  ConsumerState<HubCustomersPage> createState() => _HubCustomersPageState();
}

class _HubCustomersPageState extends ConsumerState<HubCustomersPage>
    with QuickNewQueryMixin {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    consumeQuickNewQuery(
      cleanPath: RoutePaths.hubCustomers,
      open: () => _openEditor(),
    );
  }

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

  bool _exporting = false;

  String _filterLabel(HubCustomersState state) {
    final parts = <String>[
      if (state.statusFilter != CustomerStatusFilter.active)
        'Status: ${switch (state.statusFilter) {
          CustomerStatusFilter.all => 'All',
          CustomerStatusFilter.active => 'Active',
          CustomerStatusFilter.inactive => 'Inactive',
        }}',
      if (state.typeFilter != CustomerTypeFilter.all)
        'Type: ${switch (state.typeFilter) {
          CustomerTypeFilter.all => 'All',
          CustomerTypeFilter.retail => 'Retail',
          CustomerTypeFilter.wholesale => 'Wholesale',
        }}',
      if (state.owingOnly) 'Owes money',
      if (state.search.trim().isNotEmpty) 'Search: "${state.search.trim()}"',
    ];
    return parts.isEmpty ? 'Active customers' : parts.join(' · ');
  }

  Future<void> _exportCustomers() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = await ref
          .read(hubCustomersProvider.notifier)
          .fetchAllForExport();
      if (!mounted) return;
      if (rows.isEmpty) {
        SelloSnackbars.info(context, 'No customers match these filters.');
        return;
      }
      downloadBrowserFile(
        bytes: CustomersExcelExporter.buildBytes(
          customers: rows,
          filterLabel: _filterLabel(ref.read(hubCustomersProvider)),
        ),
        filename: CustomersExcelExporter.filename(),
        mimeType: 'application/vnd.ms-excel',
      );
      SelloSnackbars.success(
        context,
        rows.length == 1
            ? '1 customer exported.'
            : '${rows.length} customers exported.',
      );
    } on AppFailure catch (failure) {
      if (mounted) SelloSnackbars.error(context, failure.message);
    } on UnsupportedError {
      if (mounted) {
        SelloSnackbars.warning(
          context,
          'Export download is available in the web app.',
        );
      }
    } catch (_) {
      if (mounted) {
        SelloSnackbars.error(context, 'Unable to export customers right now.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openEditor({CustomerSummary? customer}) async {
    final result = await showDialog<CustomerUpsertInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CustomerEditorDialog(customer: customer),
    );

    if (result == null) return;

    final outcome = await ref
        .read(hubCustomersProvider.notifier)
        .saveCustomer(result);

    if (!mounted) return;
    if (!outcome.isOk) {
      SelloSnackbars.error(
        context,
        outcome.error ?? 'Unable to save customer.',
      );
      return;
    }

    if (customer == null) {
      final created = await _promptExistingChequeAfterCreate(
        customerId: outcome.customerId!,
        customerName: result.name.trim(),
      );
      if (!mounted) return;
      if (created) {
        SelloSnackbars.success(context, 'Customer and existing cheque saved.');
      } else {
        SelloSnackbars.success(context, 'Customer created.');
      }
    } else {
      SelloSnackbars.success(context, 'Customer updated.');
    }
  }

  Future<bool> _promptExistingChequeAfterCreate({
    required String customerId,
    required String customerName,
  }) async {
    final choice = await showSelloDialog(
      context: context,
      title: '$customerName has been added',
      message:
          'Already have cheques from this customer?\n'
          'Record cheques received before you started using Sello.',
      confirmLabel: 'Add existing cheque',
      cancelLabel: 'Done',
    );
    if (choice != true || !mounted) return false;

    final listed = ref
        .read(hubCustomersProvider)
        .items
        .where((c) => c.id == customerId)
        .firstOrNull;
    final summary =
        listed ??
        CustomerSummary(
          id: customerId,
          companyId: ref.read(currentSessionProvider)?.company.id ?? '',
          name: customerName,
          customerType: CustomerType.retail,
          creditAllowed: false,
          creditLimit: 0,
          openingBalance: 0,
          outstandingBalance: 0,
          walletBalance: 0,
          isActive: true,
        );

    return _openAddExistingCheque(summary);
  }

  Future<bool> _openAddExistingCheque(CustomerSummary customer) async {
    final input = await showDialog<CreateExistingChequeInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddExistingChequeDialog(
        currencySymbol: _currencySymbol(),
        initialCustomer: customer,
        lockCustomer: true,
      ),
    );
    if (input == null || !mounted) return false;
    try {
      await ref.read(chequeRepositoryProvider).createExistingCheque(input);
      return true;
    } on AppFailure catch (failure) {
      if (mounted) SelloSnackbars.error(context, failure.message);
      return false;
    } catch (_) {
      if (mounted) {
        SelloSnackbars.error(context, 'Unable to save that existing cheque.');
      }
      return false;
    }
  }

  Future<void> _openDetails(CustomerSummary customer) async {
    final currencySymbol = _currencySymbol();
    final session = ref.read(currentSessionProvider);
    final employees = ref.read(employeeRepositoryProvider);
    final Future<String?>? assigneeName = session == null
        ? null
        : employees
              .fetchCustomerAssignee(
                companyId: session.company.id,
                customerId: customer.id,
              )
              .then<String?>((a) => a.employeeName)
              .catchError((Object _) => null);
    final permissions = ref.read(permissionServiceProvider);
    final canOrder = permissions?.canCreate(AppModule.orders) ?? false;
    final canCollect = permissions?.canCreate(AppModule.payments) ?? false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _HubCustomerDetailsHost(
        customer: customer,
        currencySymbol: currencySymbol,
        assignedRepresentativeName: assigneeName,
        onNewOrder: !canOrder
            ? null
            : () {
                Navigator.of(dialogContext).pop();
                QuickActionsLauncher.newOrder(
                  context,
                  ref,
                  customerId: customer.id,
                );
              },
        onReceivePayment: !canCollect
            ? null
            : () async {
                Navigator.of(dialogContext).pop();
                await QuickActionsLauncher.receivePayment(
                  context,
                  ref,
                  customer: customer,
                );
              },
        onAddExistingCheque: () async {
          Navigator.of(dialogContext).pop();
          final saved = await _openAddExistingCheque(customer);
          if (!mounted) return;
          if (saved) {
            SelloSnackbars.success(context, 'Existing cheque saved.');
          }
        },
        onEdit: () {
          Navigator.of(dialogContext).pop();
          _openEditor(customer: customer);
        },
        onToggleArchive: () async {
          Navigator.of(dialogContext).pop();
          await _toggleArchive(customer);
        },
        onDeletePermanently: customer.isActive
            ? null
            : () async {
                Navigator.of(dialogContext).pop();
                await _deletePermanently(customer);
              },
      ),
    );
  }

  Future<void> _toggleArchive(CustomerSummary customer) async {
    final archived = customer.isActive;
    final confirmed = await showSelloDialog(
      context: context,
      title: archived ? 'Deactivate customer?' : 'Reactivate customer?',
      message: archived
          ? '"${customer.name}" will be hidden from new sales. '
                'Past orders and payments still show this customer. '
                'You can reactivate them from the Inactive filter.'
          : '"${customer.name}" will be available for new sales again.',
      confirmLabel: archived ? 'Deactivate' : 'Reactivate',
      cancelLabel: 'Cancel',
      destructive: archived,
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(hubCustomersProvider.notifier)
        .setArchived(customer, archived: archived);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(
        context,
        archived ? 'Customer deactivated.' : 'Customer reactivated.',
      );
    }
  }

  Future<void> _deletePermanently(CustomerSummary customer) async {
    if (customer.isActive) {
      SelloSnackbars.warning(
        context,
        'Deactivate the customer before permanently deleting them.',
      );
      return;
    }

    final confirmed = await showSelloDialog(
      context: context,
      title: 'Delete permanently?',
      message:
          '"${customer.name}" will be removed permanently. '
          'This is only for a customer with no orders, payments, or visits. '
          'This cannot be undone.',
      confirmLabel: 'Delete permanently',
      cancelLabel: 'Keep inactive',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(hubCustomersProvider.notifier)
        .permanentlyDelete(customer);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Customer permanently deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubCustomersProvider);
    ref.watch(hubSettingsProvider);
    final currencySymbol = _currencySymbol();
    DataColumnSortCallback sortBy(CustomerSort sort) =>
        (_, _) => ref.read(hubCustomersProvider.notifier).setSort(sort);

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Customers',
      subtitle:
          'Your customer relationships — who you sell to and how you stay in touch.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CustomersToolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubCustomersProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubCustomersProvider.notifier).setStatusFilter(value);
              }
            },
            onTypeChanged: (value) {
              if (value != null) {
                ref.read(hubCustomersProvider.notifier).setTypeFilter(value);
              }
            },
            onOwingChanged: (value) =>
                ref.read(hubCustomersProvider.notifier).setOwingOnly(value),
            onRefresh: () => ref.read(hubCustomersProvider.notifier).refresh(),
            isRefreshing: state.isLoading,
            onExport: _exporting ? null : _exportCustomers,
            isExporting: _exporting,
            onAdd: state.isSaving ? null : () => _openEditor(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          SelloClearFiltersBar(
            visible: state.hasActiveFilters,
            onClear: () {
              _searchController.clear();
              ref.read(hubCustomersProvider.notifier).clearFilters();
            },
          ),
          if (state.statusFilter == CustomerStatusFilter.inactive) ...[
            const _ArchivedCustomersBanner(),
            const SizedBox(height: AppSpacing.md),
          ],
          SelloInlineRefreshBar(
            active: state.isLoading && state.items.isNotEmpty,
          ),
          if (state.errorMessage != null && state.items.isNotEmpty)
            SelloInlineErrorBar(
              message: state.errorMessage,
              onRetry: () => ref.read(hubCustomersProvider.notifier).refresh(),
            ),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 9),
          ] else ...[
            _CustomersSummaryRow(
              totalCount: state.items.length,
              activeCount: state.items.where((item) => item.isActive).length,
              archivedCount: state.items.where((item) => !item.isActive).length,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load customers',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubCustomersProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: state.statusFilter == CustomerStatusFilter.inactive
                      ? 'No inactive customers'
                      : 'Start building your customer base',
                  message: state.statusFilter == CustomerStatusFilter.inactive
                      ? 'Inactive customers stay out of new sales. Past orders '
                            'and payments still show them. Reactivate one here '
                            'when you need them again.'
                      : 'Add your first customer with contact details, credit terms, '
                            'and opening balance. Orders, payments, and reporting build on these relationships.',
                  icon: state.statusFilter == CustomerStatusFilter.inactive
                      ? Icons.people_outline_rounded
                      : Icons.people_rounded,
                  actionLabel:
                      state.statusFilter == CustomerStatusFilter.inactive
                      ? null
                      : 'Add Customer',
                  onAction: state.statusFilter == CustomerStatusFilter.inactive
                      ? null
                      : () => _openEditor(),
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final customer in state.items) ...[
                      _CustomerListCard(
                        customer: customer,
                        currencySymbol: currencySymbol,
                        onTap: () => _openDetails(customer),
                        onEdit: () => _openEditor(customer: customer),
                        onToggleArchive: () => _toggleArchive(customer),
                        onDeletePermanently: customer.isActive
                            ? null
                            : () => _deletePermanently(customer),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.panelAll,
                        border: Border.all(color: AppColors.outlinePanel),
                        boxShadow: AppShadows.panel,
                      ),
                      child: _TablePaginationFooter(
                        page: state.page,
                        pageSize: state.pageSize,
                        itemCount: state.items.length,
                        hasMore: state.hasMore,
                        onPrevious: state.page == 0
                            ? null
                            : () => ref
                                  .read(hubCustomersProvider.notifier)
                                  .goToPage(state.page - 1),
                        onNext: !state.hasMore
                            ? null
                            : () => ref
                                  .read(hubCustomersProvider.notifier)
                                  .goToPage(state.page + 1),
                      ),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  sortColumnIndex: switch (state.sort) {
                    CustomerSort.recent => null,
                    CustomerSort.name => 0,
                    CustomerSort.outstanding => 3,
                    CustomerSort.wallet => 4,
                    CustomerSort.lastPurchase => 5,
                    CustomerSort.updated => 7,
                  },
                  sortAscending: state.sortAscending,
                  columns: [
                    selloDataColumn(
                      'Customer',
                      onSort: sortBy(CustomerSort.name),
                    ),
                    selloDataColumn('Type'),
                    selloDataColumn('Phone'),
                    selloDataColumn(
                      'Outstanding',
                      numeric: true,
                      onSort: sortBy(CustomerSort.outstanding),
                    ),
                    selloDataColumn(
                      'Wallet',
                      numeric: true,
                      onSort: sortBy(CustomerSort.wallet),
                    ),
                    selloDataColumn(
                      'Last Purchase',
                      onSort: sortBy(CustomerSort.lastPurchase),
                    ),
                    selloDataColumn('Status'),
                    selloDataColumn(
                      'Updated',
                      onSort: sortBy(CustomerSort.updated),
                    ),
                    selloDataColumn('Actions'),
                  ],
                  rows: [
                    for (final customer in state.items)
                      DataRow(
                        onSelectChanged: (_) => _openDetails(customer),
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                SelloEntityThumb(
                                  width: 44,
                                  name: customer.name,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SelloTableText(
                                        customer.name,
                                        tone: SelloTableTone.strong,
                                      ),
                                      if (customer.code != null ||
                                          customer.companyName != null) ...[
                                        const SizedBox(height: 2),
                                        SelloTableText(
                                          [
                                            if (customer.code != null)
                                              customer.code!,
                                            if (customer.companyName != null)
                                              customer.companyName!,
                                          ].join(' · '),
                                          tone: SelloTableTone.muted,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            _CustomerTypeBadge(type: customer.customerType),
                          ),
                          DataCell(
                            SelloTableText(
                              PhoneNumber.displayOrNull(customer.phone) ?? '-',
                              tone: customer.phone == null
                                  ? SelloTableTone.muted
                                  : SelloTableTone.normal,
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.centerRight,
                              child: SelloTableText(
                                SelloFormatters.currency(
                                  customer.outstandingBalance,
                                  symbol: currencySymbol,
                                ),
                                tone: SelloTableTone.strong,
                                numeric: true,
                              ),
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.centerRight,
                              child: SelloTableText(
                                SelloFormatters.currency(
                                  customer.walletBalance,
                                  symbol: currencySymbol,
                                ),
                                numeric: true,
                              ),
                            ),
                          ),
                          DataCell(
                            SelloTableText(
                              customer.lastPurchaseAt != null
                                  ? SelloFormatters.date(
                                      customer.lastPurchaseAt,
                                    )
                                  : '-',
                              tone: customer.lastPurchaseAt == null
                                  ? SelloTableTone.muted
                                  : SelloTableTone.normal,
                            ),
                          ),
                          DataCell(
                            _CustomerStatusBadge(active: customer.isActive),
                          ),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.date(customer.updatedAt),
                              tone: SelloTableTone.muted,
                            ),
                          ),
                          DataCell(
                            _RowActionGroup(
                              onView: () => _openDetails(customer),
                              onEdit: () => _openEditor(customer: customer),
                              onToggleArchive: () => _toggleArchive(customer),
                              onDeletePermanently: customer.isActive
                                  ? null
                                  : () => _deletePermanently(customer),
                              isActive: customer.isActive,
                            ),
                          ),
                        ],
                      ),
                  ],
                  footer: _TablePaginationFooter(
                    page: state.page,
                    pageSize: state.pageSize,
                    itemCount: state.items.length,
                    hasMore: state.hasMore,
                    onPrevious: state.page == 0
                        ? null
                        : () => ref
                              .read(hubCustomersProvider.notifier)
                              .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                              .read(hubCustomersProvider.notifier)
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

class _CustomersToolbar extends StatelessWidget {
  const _CustomersToolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onTypeChanged,
    required this.onOwingChanged,
    required this.onRefresh,
    required this.isRefreshing,
    required this.onExport,
    required this.isExporting,
    required this.onAdd,
  });

  final TextEditingController searchController;
  final HubCustomersState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CustomerStatusFilter?> onStatusChanged;
  final ValueChanged<CustomerTypeFilter?> onTypeChanged;
  final ValueChanged<bool> onOwingChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final VoidCallback? onExport;
  final bool isExporting;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 148,
      child: SelloDropdown<CustomerStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(value: CustomerStatusFilter.all, child: Text('All')),
          DropdownMenuItem(
            value: CustomerStatusFilter.active,
            child: Text('Active'),
          ),
          DropdownMenuItem(
            value: CustomerStatusFilter.inactive,
            child: Text('Inactive'),
          ),
        ],
      ),
    );

    final type = SizedBox(
      width: context.isMobile ? double.infinity : 148,
      child: SelloDropdown<CustomerTypeFilter>(
        value: state.typeFilter,
        compact: true,
        hint: 'Type',
        onChanged: onTypeChanged,
        items: const [
          DropdownMenuItem(value: CustomerTypeFilter.all, child: Text('All')),
          DropdownMenuItem(
            value: CustomerTypeFilter.retail,
            child: Text('Retail'),
          ),
          DropdownMenuItem(
            value: CustomerTypeFilter.wholesale,
            child: Text('Wholesale'),
          ),
        ],
      ),
    );

    final owing = SizedBox(
      width: context.isMobile ? double.infinity : 168,
      child: SelloDropdown<bool>(
        value: state.owingOnly,
        compact: true,
        hint: 'Balance',
        onChanged: (value) {
          if (value != null) onOwingChanged(value);
        },
        items: const [
          DropdownMenuItem(value: false, child: Text('Any balance')),
          DropdownMenuItem(value: true, child: Text('Owes money')),
        ],
      ),
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      loading: isRefreshing,
      onPressed: isRefreshing ? null : onRefresh,
    );

    final export = SelloButton(
      label: 'Export',
      icon: Icons.download_rounded,
      variant: SelloButtonVariant.outline,
      loading: isExporting,
      onPressed: onExport,
    );

    final add = SelloButton(
      label: 'Add Customer',
      icon: Icons.add_rounded,
      variant: SelloButtonVariant.primary,
      onPressed: onAdd,
    );

    final search = SelloSearchBar(
      controller: searchController,
      hint: 'Search by name, phone, email, company or code…',
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
        filters: [status, type, owing],
        actions: [refresh, export, add],
      ),
    );
  }
}

class _CustomersSummaryRow extends StatelessWidget {
  const _CustomersSummaryRow({
    required this.totalCount,
    required this.activeCount,
    required this.archivedCount,
  });

  final int totalCount;
  final int activeCount;
  final int archivedCount;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Total',
          value: '$totalCount',
          hint: 'Visible on this page',
          icon: Icons.people_outline_rounded,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Active',
          value: '$activeCount',
          hint: 'Ready for sales',
          icon: Icons.check_circle_outline_rounded,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Inactive',
          value: '$archivedCount',
          hint: 'Hidden from new sales',
          icon: Icons.archive_outlined,
          tone: AppColors.textTertiary,
        ),
      ],
    );
  }
}

class _ArchivedCustomersBanner extends StatelessWidget {
  const _ArchivedCustomersBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: AppColors.info,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Inactive customers are hidden from new sales. Past orders '
              'and payments still show them.',
              style: context.texts.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowActionGroup extends StatelessWidget {
  const _RowActionGroup({
    required this.onView,
    required this.onEdit,
    required this.onToggleArchive,
    required this.isActive,
    this.onDeletePermanently,
  });

  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchive;
  final VoidCallback? onDeletePermanently;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionIconButton(
            tooltip: 'View details',
            icon: Icons.visibility_outlined,
            onPressed: onView,
          ),
          _ActionIconButton(
            tooltip: 'Edit customer',
            icon: Icons.edit_outlined,
            onPressed: onEdit,
          ),
          _ActionIconButton(
            tooltip: isActive ? 'Deactivate' : 'Reactivate',
            icon: isActive ? Icons.archive_outlined : Icons.unarchive_outlined,
            onPressed: onToggleArchive,
          ),
          if (!isActive && onDeletePermanently != null)
            _ActionIconButton(
              tooltip: 'Delete permanently',
              icon: Icons.delete_outline_rounded,
              onPressed: onDeletePermanently!,
              danger: true,
            ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatefulWidget {
  const _ActionIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<_ActionIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AppColors.error : context.brandAccent;
    final idle = widget.danger ? AppColors.error : AppColors.textTertiary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: _hovered
              ? (widget.danger ? AppColors.errorContainer : AppColors.veil)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.transparent,
            splashColor: accent.withValues(alpha: 0.08),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                widget.icon,
                size: 17,
                color: _hovered ? accent : idle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TablePaginationFooter extends StatelessWidget {
  const _TablePaginationFooter({
    required this.page,
    required this.pageSize,
    required this.itemCount,
    required this.hasMore,
    this.onPrevious,
    this.onNext,
  });

  final int page;
  final int pageSize;
  final int itemCount;
  final bool hasMore;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = itemCount == 0 ? 0 : page * pageSize + 1;
    final end = page * pageSize + itemCount;
    final rangeLabel = itemCount == 0
        ? 'No customers'
        : 'Showing $start–$end customers';

    final currentPage = page + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.mdPlus,
        AppSpacing.lg,
        AppSpacing.mdPlus,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rangeLabel,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          SelloButton(
            label: 'Previous',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.outline,
            onPressed: onPrevious,
          ),
          const SizedBox(width: AppSpacing.xs),
          _PageChip(label: '$currentPage', selected: true),
          if (hasMore) ...[
            const SizedBox(width: 6),
            _PageChip(
              label: '${currentPage + 1}',
              selected: false,
              onTap: onNext,
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
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

class _PageChip extends StatelessWidget {
  const _PageChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.brandAccentContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Container(
          height: AppSpacing.controlHeightCompact,
          constraints: const BoxConstraints(minWidth: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(
              color: selected ? context.brandMid : AppColors.outlineStrong,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1,
              color: selected ? context.brandAccent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerListCard extends StatelessWidget {
  const _CustomerListCard({
    required this.customer,
    required this.currencySymbol,
    required this.onTap,
    required this.onEdit,
    required this.onToggleArchive,
    this.onDeletePermanently,
  });

  final CustomerSummary customer;
  final String currencySymbol;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchive;
  final VoidCallback? onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      onTap: onTap,
      enableHoverLift: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SelloEntityThumb(width: 52, name: customer.name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (customer.phone != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        PhoneNumber.displayOf(customer.phone),
                        style: context.texts.bodySmall?.copyWith(
                          color: context.selloColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _CustomerTypeBadge(type: customer.customerType),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SelloMetaPill(
            label: 'Outstanding',
            value: SelloFormatters.currency(
              customer.outstandingBalance,
              symbol: currencySymbol,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: onToggleArchive,
                icon: Icon(
                  customer.isActive
                      ? Icons.archive_outlined
                      : Icons.unarchive_outlined,
                ),
                label: Text(customer.isActive ? 'Deactivate' : 'Reactivate'),
              ),
              if (onDeletePermanently != null)
                TextButton.icon(
                  onPressed: onDeletePermanently,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerStatusBadge extends StatelessWidget {
  const _CustomerStatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return SelloStatusBadge(
      label: active ? 'Active' : 'Inactive',
      tone: active ? SelloStatusTone.success : SelloStatusTone.neutral,
    );
  }
}

class _CustomerTypeBadge extends StatelessWidget {
  const _CustomerTypeBadge({required this.type});

  final CustomerType type;

  @override
  Widget build(BuildContext context) {
    return SelloStatusBadge(
      label: type.label,
      tone: type == CustomerType.wholesale
          ? SelloStatusTone.brand
          : SelloStatusTone.neutral,
    );
  }
}

class CustomerEditorDialog extends StatefulWidget {
  const CustomerEditorDialog({super.key, this.customer});

  final CustomerSummary? customer;

  @override
  State<CustomerEditorDialog> createState() => CustomerEditorDialogState();
}

class CustomerEditorDialogState extends State<CustomerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _companyName;
  late final TextEditingController _taxNumber;
  late final TextEditingController _creditLimit;
  late final TextEditingController _openingBalance;
  late final TextEditingController _notes;
  late CustomerType _customerType;
  late bool _creditAllowed;
  late bool _isActive;
  bool _submitted = false;

  bool get _isCreate => widget.customer == null;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _name = TextEditingController(text: customer?.name ?? '');
    _code = TextEditingController(text: customer?.code ?? '');
    _phone = TextEditingController(
      text: PhoneNumber.displayOf(customer?.phone),
    );
    _whatsapp = TextEditingController(
      text: PhoneNumber.displayOf(customer?.whatsapp),
    );
    _email = TextEditingController(text: customer?.email ?? '');
    _address = TextEditingController(text: customer?.addressLine1 ?? '');
    _city = TextEditingController(text: customer?.city ?? '');
    _companyName = TextEditingController(text: customer?.companyName ?? '');
    _taxNumber = TextEditingController(text: customer?.taxNumber ?? '');
    _creditLimit = TextEditingController(
      text: customer == null ? '' : customer.creditLimit.toString(),
    );
    _openingBalance = TextEditingController(
      text: customer == null ? '' : customer.openingBalance.toString(),
    );
    _notes = TextEditingController(text: customer?.notes ?? '');
    _customerType = customer?.customerType ?? CustomerType.retail;
    _creditAllowed = customer?.creditAllowed ?? false;
    _isActive = customer?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _email.dispose();
    _address.dispose();
    _city.dispose();
    _companyName.dispose();
    _taxNumber.dispose();
    _creditLimit.dispose();
    _openingBalance.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      CustomerUpsertInput(
        customerId: widget.customer?.id,
        name: _name.text.trim(),
        code: _trimOrNull(_code.text),
        companyName: _trimOrNull(_companyName.text),
        customerType: _customerType,
        phone: PhoneNumber.normalizeStorage(_phone.text),
        whatsapp: PhoneNumber.normalizeStorage(_whatsapp.text),
        email: _trimOrNull(_email.text),
        addressLine1: _trimOrNull(_address.text),
        city: _trimOrNull(_city.text),
        taxNumber: _trimOrNull(_taxNumber.text),
        notes: _trimOrNull(_notes.text),
        creditAllowed: _creditAllowed,
        creditLimit: num.tryParse(_creditLimit.text.trim()) ?? 0,
        openingBalance: num.tryParse(_openingBalance.text.trim()) ?? 0,
        isActive: _isActive,
      ),
    );
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      formKey: _formKey,
      maxWidth: kSelloFormDialogWidth,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      title: _isCreate ? 'Add Customer' : 'Edit Customer',
      subtitle: _isCreate
          ? 'Create a new customer profile. Contact details, credit terms, and balances apply to future orders and payments.'
          : 'Update this customer profile. Changes apply to future orders, payments, and reporting.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloDialogSection(
            title: 'Identity',
            children: [
              SelloTextField(
                controller: _name,
                label: 'Customer name',
                required: true,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a customer name.'
                    : null,
              ),
              SelloFormRow(
                left: SelloTextField(controller: _code, label: 'Customer code'),
                right: SelloDropdown<CustomerType>(
                  value: _customerType,
                  label: 'Customer type',
                  items: const [
                    DropdownMenuItem(
                      value: CustomerType.retail,
                      child: Text('Retail'),
                    ),
                    DropdownMenuItem(
                      value: CustomerType.wholesale,
                      child: Text('Wholesale'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _customerType = value);
                    }
                  },
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Contact',
            children: [
              SelloFormRow(
                left: SelloTextField(
                  controller: _phone,
                  label: 'Mobile',
                  keyboardType: TextInputType.phone,
                  validator: PhoneNumber.validator,
                ),
                right: SelloTextField(
                  controller: _whatsapp,
                  label: 'WhatsApp',
                  keyboardType: TextInputType.phone,
                  validator: PhoneNumber.validator,
                ),
              ),
              SelloTextField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Address',
            children: [
              SelloFormRow(
                left: SelloTextField(controller: _address, label: 'Address'),
                right: SelloTextField(controller: _city, label: 'City'),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Business',
            children: [
              SelloFormRow(
                left: SelloTextField(
                  controller: _companyName,
                  label: 'Company name',
                ),
                right: SelloTextField(
                  controller: _taxNumber,
                  label: 'Tax number',
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Financial',
            children: [
              SelloStatusToggle(
                value: _creditAllowed,
                onChanged: (value) => setState(() => _creditAllowed = value),
                label: 'Credit allowed',
                helper:
                    'Allow this customer to buy now and pay later. Credit limit is shown for guidance — Sello does not currently block orders above it.',
              ),
              SelloFormRow(
                left: SelloTextField(
                  controller: _creditLimit,
                  label: 'Credit limit',
                  required: _creditAllowed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _creditAllowed
                      ? _validateNumber
                      : _validateOptionalNumber,
                ),
                right: SelloTextField(
                  controller: _openingBalance,
                  label: 'Opening balance',
                  hint: _isCreate
                      ? 'Amount they already owed — added to Outstanding'
                      : 'Set at create — use Add opening balance later',
                  enabled: _isCreate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _isCreate ? _validateOptionalNumber : null,
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Notes',
            children: [
              SelloTextField(
                controller: _notes,
                label: 'Internal notes',
                hint: 'Staff-only notes about this customer…',
                maxLines: 4,
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Status',
            bottomSpacing: 8,
            children: [
              SelloStatusToggle(
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                label: 'Active',
                helper:
                    'Inactive customers remain available in reports and history but cannot be used in new sales.',
              ),
            ],
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: _isCreate ? 'Create Customer' : 'Save Changes',
        onPrimary: _submit,
      ),
    );
  }

  String? _validateNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required.';
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < 0) return 'Value cannot be negative.';
    return null;
  }

  String? _validateOptionalNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < 0) return 'Value cannot be negative.';
    return null;
  }
}

class _HubCustomerDetailsHost extends ConsumerStatefulWidget {
  const _HubCustomerDetailsHost({
    required this.customer,
    required this.currencySymbol,
    this.assignedRepresentativeName,
    this.onNewOrder,
    this.onReceivePayment,
    this.onAddExistingCheque,
    this.onEdit,
    this.onToggleArchive,
    this.onDeletePermanently,
  });

  final CustomerSummary customer;
  final String currencySymbol;

  /// Resolved after the dialog opens so details appear immediately.
  final Future<String?>? assignedRepresentativeName;
  final VoidCallback? onNewOrder;
  final VoidCallback? onReceivePayment;
  final VoidCallback? onAddExistingCheque;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleArchive;
  final VoidCallback? onDeletePermanently;

  @override
  ConsumerState<_HubCustomerDetailsHost> createState() =>
      _HubCustomerDetailsHostState();
}

class _HubCustomerDetailsHostState
    extends ConsumerState<_HubCustomerDetailsHost> {
  late CustomerSummary _customer;
  int _historyEpoch = 0;
  String? _assigneeName;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    widget.assignedRepresentativeName?.then((name) {
      if (mounted && name != null) setState(() => _assigneeName = name);
    });
  }

  Future<void> _addOpeningBalance() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddOpeningBalanceDialog(
        customer: _customer,
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (saved != true || !mounted) return;
    final fresh = await ref
        .read(customerRepositoryProvider)
        .fetchById(_customer.id);
    if (!mounted) return;
    if (fresh != null) {
      setState(() {
        _customer = fresh;
        _historyEpoch++;
      });
    }
    await ref
        .read(hubCustomersProvider.notifier)
        .loadCustomers(showLoading: false);
    if (!mounted) return;
    SelloSnackbars.success(context, 'Opening balance added.');
  }

  Future<void> _correctOpeningBalance(CustomerReceivableAdjustment item) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CorrectOpeningBalanceDialog(
        customer: _customer,
        adjustment: item,
        currencySymbol: widget.currencySymbol,
      ),
    );
    if (saved != true || !mounted) return;
    final fresh = await ref
        .read(customerRepositoryProvider)
        .fetchById(_customer.id);
    if (!mounted) return;
    if (fresh != null) {
      setState(() {
        _customer = fresh;
        _historyEpoch++;
      });
    }
    await ref
        .read(hubCustomersProvider.notifier)
        .loadCustomers(showLoading: false);
    if (!mounted) return;
    SelloSnackbars.success(context, 'Opening balance corrected.');
  }

  @override
  Widget build(BuildContext context) {
    final canAdd =
        ref
            .watch(permissionServiceProvider)
            ?.canRecordOpeningBalanceAdjustment ??
        false;
    return CustomerDetailsDialog(
      customer: _customer,
      currencySymbol: widget.currencySymbol,
      assignedRepresentativeName: _assigneeName,
      openingBalanceHistoryEpoch: _historyEpoch,
      onAddOpeningBalance: canAdd && _customer.isActive
          ? _addOpeningBalance
          : null,
      onCorrectOpeningBalance: canAdd && _customer.isActive
          ? _correctOpeningBalance
          : null,
      onNewOrder: widget.onNewOrder,
      onReceivePayment: widget.onReceivePayment,
      onAddExistingCheque: widget.onAddExistingCheque,
      onEdit: widget.onEdit,
      onToggleArchive: widget.onToggleArchive,
      onDeletePermanently: widget.onDeletePermanently,
    );
  }
}
