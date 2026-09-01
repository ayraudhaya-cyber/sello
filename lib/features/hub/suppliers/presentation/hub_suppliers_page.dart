import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/hub/suppliers/application/hub_suppliers_provider.dart';
import 'package:sello/features/hub/suppliers/presentation/supplier_details_dialog.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/supplier_summary.dart';
import 'package:sello/shared/models/supplier_upsert_input.dart';
import 'package:sello/shared/utils/country_catalog.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/utils/quick_new_query.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubSuppliersPage extends ConsumerStatefulWidget {
  const HubSuppliersPage({super.key});

  @override
  ConsumerState<HubSuppliersPage> createState() => _HubSuppliersPageState();
}

class _HubSuppliersPageState extends ConsumerState<HubSuppliersPage>
    with QuickNewQueryMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    consumeQuickNewQuery(
      cleanPath: RoutePaths.hubSuppliers,
      open: () => _openEditor(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  Future<void> _openEditor({SupplierSummary? supplier}) async {
    final result = await showDialog<SupplierUpsertInput>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SupplierEditorDialog(supplier: supplier),
    );
    if (result == null) return;

    final error = await ref
        .read(hubSuppliersProvider.notifier)
        .saveSupplier(result);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(
        context,
        supplier == null ? 'Supplier created.' : 'Supplier updated.',
      );
    }
  }

  Future<void> _openDetails(SupplierSummary supplier) async {
    final currencySymbol = _currencySymbol();
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      SelloSnackbars.error(context, 'Sign in required.');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );

    try {
      final detail = await ref
          .read(supplierRepositoryProvider)
          .fetchDetail(companyId: session.company.id, supplierId: supplier.id);
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      if (detail == null) {
        SelloSnackbars.error(context, 'Unable to load that supplier.');
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) => SupplierDetailsDialog(
          detail: detail,
          currencySymbol: currencySymbol,
          onEdit: () {
            Navigator.of(context).pop();
            _openEditor(supplier: detail.supplier);
          },
          onToggleArchive: () async {
            Navigator.of(context).pop();
            await _toggleArchive(detail.supplier);
          },
          onDeletePermanently: detail.supplier.isActive
              ? null
              : () async {
                  Navigator.of(context).pop();
                  await _deletePermanently(detail.supplier);
                },
        ),
      );
    } on AppFailure catch (failure) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      SelloSnackbars.error(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      SelloSnackbars.error(context, 'Unable to load supplier details.');
    }
  }

  Future<void> _toggleArchive(SupplierSummary supplier) async {
    final archived = supplier.isActive;
    final error = await ref
        .read(hubSuppliersProvider.notifier)
        .setArchived(supplier, archived: archived);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(
        context,
        archived ? 'Supplier archived.' : 'Supplier restored.',
      );
    }
  }

  Future<void> _deletePermanently(SupplierSummary supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete supplier permanently?'),
        content: Text(
          '${supplier.name} will be removed from the directory. '
          'Historical procurement records will keep their references.',
        ),
        actions: [
          SelloButton(
            label: 'Cancel',
            variant: SelloButtonVariant.outline,
            onPressed: () => Navigator.pop(context, false),
          ),
          SelloButton(
            label: 'Delete',
            variant: SelloButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await ref
        .read(hubSuppliersProvider.notifier)
        .permanentlyDelete(supplier);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Supplier deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubSuppliersProvider);
    final currencySymbol = _currencySymbol();

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Suppliers',
      subtitle:
          'Procurement directory — vendors that supply products and will '
          'power purchase orders and goods received.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      actions: [
        SelloButton(
          label: 'Add supplier',
          icon: Icons.add_business_rounded,
          onPressed: state.isSaving ? null : () => _openEditor(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubSuppliersProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubSuppliersProvider.notifier).setStatusFilter(value);
              }
            },
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubSuppliersProvider.notifier).refresh(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 8),
          ] else ...[
            _SummaryRow(stats: state.stats),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load suppliers',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubSuppliersProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: state.statusFilter == SupplierStatusFilter.archived
                      ? 'No archived suppliers'
                      : 'Add your first supplier',
                  message: state.statusFilter == SupplierStatusFilter.archived
                      ? 'Archived suppliers remain for historical purchase '
                            'orders and payments.'
                      : 'Capture vendor contact, payment terms, and opening '
                            'payable balance. Purchase orders and GRN will build '
                            'on this directory.',
                  icon: Icons.local_shipping_outlined,
                  actionLabel:
                      state.statusFilter == SupplierStatusFilter.archived
                      ? null
                      : 'Add supplier',
                  onAction: state.statusFilter == SupplierStatusFilter.archived
                      ? null
                      : () => _openEditor(),
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final supplier in state.items) ...[
                      SelloCard(
                        onTap: () => _openDetails(supplier),
                        child: Row(
                          children: [
                            SelloEntityThumb(
                              name: supplier.name,
                              width: 48,
                              height: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    supplier.name,
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    supplier.contactName ??
                                        PhoneNumber.displayOrNull(
                                          supplier.phone,
                                        ) ??
                                        'No contact',
                                    style: const TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SelloStatusBadge(
                              label: supplier.isActive ? 'Active' : 'Archived',
                              tone: supplier.isActive
                                  ? SelloStatusTone.success
                                  : SelloStatusTone.neutral,
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
                                .read(hubSuppliersProvider.notifier)
                                .goToPage(state.page - 1),
                      onNext: !state.hasMore
                          ? null
                          : () => ref
                                .read(hubSuppliersProvider.notifier)
                                .goToPage(state.page + 1),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  columns: [
                    selloDataColumn('Supplier'),
                    selloDataColumn('Contact'),
                    selloDataColumn('Phone'),
                    selloDataColumn('Email'),
                    selloDataColumn('Outstanding', numeric: true),
                    selloDataColumn('Last purchase'),
                    selloDataColumn('Status'),
                    selloDataColumn('Actions'),
                  ],
                  rows: [
                    for (final supplier in state.items)
                      DataRow(
                        onSelectChanged: (_) => _openDetails(supplier),
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                SelloEntityThumb(
                                  name: supplier.name,
                                  width: 44,
                                  height: 44,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SelloTableText(
                                        supplier.name,
                                        tone: SelloTableTone.strong,
                                      ),
                                      if (supplier.code != null) ...[
                                        const SizedBox(height: 2),
                                        SelloTableText(
                                          supplier.code!,
                                          tone: SelloTableTone.muted,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(SelloTableText(supplier.contactName ?? '—')),
                          DataCell(
                            SelloTableText(
                              PhoneNumber.displayOrNull(supplier.phone) ?? '—',
                            ),
                          ),
                          DataCell(SelloTableText(supplier.email ?? '—')),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.currency(
                                supplier.outstandingBalance,
                                symbol: currencySymbol,
                              ),
                            ),
                          ),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.date(supplier.lastPurchaseAt),
                            ),
                          ),
                          DataCell(
                            SelloStatusBadge(
                              label: supplier.isActive ? 'Active' : 'Archived',
                              tone: supplier.isActive
                                  ? SelloStatusTone.success
                                  : SelloStatusTone.neutral,
                            ),
                          ),
                          DataCell(
                            SelloButton(
                              label: 'View',
                              variant: SelloButtonVariant.ghost,
                              size: SelloButtonSize.small,
                              onPressed: () => _openDetails(supplier),
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
                              .read(hubSuppliersProvider.notifier)
                              .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                              .read(hubSuppliersProvider.notifier)
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final HubSuppliersState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<SupplierStatusFilter?> onStatusChanged;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 150,
      child: SelloDropdown<SupplierStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(
            value: SupplierStatusFilter.all,
            child: Text('All statuses'),
          ),
          DropdownMenuItem(
            value: SupplierStatusFilter.active,
            child: Text('Active'),
          ),
          DropdownMenuItem(
            value: SupplierStatusFilter.archived,
            child: Text('Archived'),
          ),
        ],
      ),
    );

    // Category filter is future-ready (provider accepts category).
    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onRefresh,
    );

    return SelloListToolbar(
      searchController: searchController,
      searchHint: 'Search name, contact, phone, email…',
      onSearchChanged: onSearchChanged,
      filters: [status],
      actions: [refresh],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});

  final SupplierDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _Metric(
        label: 'Total suppliers',
        value: '${stats.total}',
        icon: Icons.local_shipping_outlined,
        accent: context.brandAccent,
        soft: context.brandAccentContainer,
      ),
      _Metric(
        label: 'Active',
        value: '${stats.active}',
        icon: Icons.check_circle_outline,
        accent: AppColors.success,
        soft: AppColors.successContainer,
      ),
      _Metric(
        label: 'Recently added',
        value: '${stats.recentlyAdded}',
        icon: Icons.fiber_new_rounded,
        accent: AppColors.inventory,
        soft: context.brandAccentContainer,
      ),
    ];

    if (context.isMobile) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          Expanded(child: cards[i]),
          if (i < cards.length - 1) const SizedBox(width: AppSpacing.md),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.soft,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.hasMore,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final bool hasMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Page ${page + 1}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _SupplierEditorDialog extends StatefulWidget {
  const _SupplierEditorDialog({this.supplier});

  final SupplierSummary? supplier;

  @override
  State<_SupplierEditorDialog> createState() => _SupplierEditorDialogState();
}

class _SupplierEditorDialogState extends State<_SupplierEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _contact;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _email;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _postal;
  String _countryCode = '';
  late final TextEditingController _tax;
  late final TextEditingController _category;
  late final TextEditingController _paymentTerms;
  late final TextEditingController _bankName;
  late final TextEditingController _bankAccount;
  late final TextEditingController _creditLimit;
  late final TextEditingController _openingBalance;
  late final TextEditingController _leadTime;
  late final TextEditingController _notes;
  late bool _isActive;
  bool _submitted = false;

  bool get _isCreate => widget.supplier == null;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _name = TextEditingController(text: s?.name ?? '');
    _code = TextEditingController(text: s?.code ?? '');
    _contact = TextEditingController(text: s?.contactName ?? '');
    _phone = TextEditingController(text: PhoneNumber.displayOf(s?.phone));
    _whatsapp = TextEditingController(text: PhoneNumber.displayOf(s?.whatsapp));
    _email = TextEditingController(text: s?.email ?? '');
    _address1 = TextEditingController(text: s?.addressLine1 ?? '');
    _address2 = TextEditingController(text: s?.addressLine2 ?? '');
    _city = TextEditingController(text: s?.city ?? '');
    _state = TextEditingController(text: s?.state ?? '');
    _postal = TextEditingController(text: s?.postalCode ?? '');
    _countryCode = s?.country ?? '';
    _tax = TextEditingController(text: s?.taxNumber ?? '');
    _category = TextEditingController(text: s?.category ?? '');
    _paymentTerms = TextEditingController(text: s?.paymentTerms ?? '');
    _bankName = TextEditingController(text: s?.bankName ?? '');
    _bankAccount = TextEditingController(text: s?.bankAccount ?? '');
    _creditLimit = TextEditingController(
      text: s == null ? '0' : s.creditLimit.toString(),
    );
    _openingBalance = TextEditingController(
      text: s == null ? '0' : s.openingBalance.toString(),
    );
    _leadTime = TextEditingController(text: s?.leadTimeDays?.toString() ?? '');
    _notes = TextEditingController(text: s?.notes ?? '');
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _contact.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _email.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _state.dispose();
    _postal.dispose();
    _tax.dispose();
    _category.dispose();
    _paymentTerms.dispose();
    _bankName.dispose();
    _bankAccount.dispose();
    _creditLimit.dispose();
    _openingBalance.dispose();
    _leadTime.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      SupplierUpsertInput(
        supplierId: widget.supplier?.id,
        name: _name.text.trim(),
        code: _trimOrNull(_code.text),
        contactName: _trimOrNull(_contact.text),
        phone: PhoneNumber.normalizeStorage(_phone.text),
        whatsapp: PhoneNumber.normalizeStorage(_whatsapp.text),
        email: _trimOrNull(_email.text),
        addressLine1: _trimOrNull(_address1.text),
        addressLine2: _trimOrNull(_address2.text),
        city: _trimOrNull(_city.text),
        state: _trimOrNull(_state.text),
        postalCode: _trimOrNull(_postal.text),
        country: _trimOrNull(_countryCode),
        taxNumber: _trimOrNull(_tax.text),
        category: _trimOrNull(_category.text),
        paymentTerms: _trimOrNull(_paymentTerms.text),
        bankName: _trimOrNull(_bankName.text),
        bankAccount: _trimOrNull(_bankAccount.text),
        notes: _trimOrNull(_notes.text),
        creditLimit: num.tryParse(_creditLimit.text.trim()) ?? 0,
        openingBalance: num.tryParse(_openingBalance.text.trim()) ?? 0,
        leadTimeDays: int.tryParse(_leadTime.text.trim()),
        isActive: _isActive,
      ),
    );
  }

  String? _trimOrNull(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      formKey: _formKey,
      maxWidth: kSelloFormDialogWidth,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      title: _isCreate ? 'Add supplier' : 'Edit supplier',
      subtitle: _isCreate
          ? 'Create a vendor profile for procurement. Purchase orders and '
                'goods received will use this record later.'
          : 'Update vendor details. Outstanding balances stay ledger-driven '
                'once supplier payments ship.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloDialogSection(
            title: 'Business',
            children: [
              SelloTextField(
                controller: _name,
                label: 'Supplier name',
                required: true,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name.' : null,
              ),
              SelloFormRow(
                left: SelloTextField(controller: _code, label: 'Supplier code'),
                right: SelloTextField(
                  controller: _category,
                  label: 'Category',
                  hint: 'Future filter',
                ),
              ),
              SelloFormRow(
                left: SelloTextField(controller: _tax, label: 'Tax number'),
                right: SelloTextField(
                  controller: _leadTime,
                  label: 'Lead time (days)',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Contact',
            children: [
              SelloTextField(controller: _contact, label: 'Contact person'),
              SelloFormRow(
                left: SelloTextField(
                  controller: _phone,
                  label: 'Phone',
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
              SelloTextField(controller: _address1, label: 'Address line 1'),
              SelloTextField(controller: _address2, label: 'Address line 2'),
              SelloFormRow(
                left: SelloTextField(controller: _city, label: 'City'),
                right: SelloTextField(controller: _state, label: 'State'),
              ),
              SelloFormRow(
                left: SelloTextField(controller: _postal, label: 'Postal code'),
                right: SelloCountryField(
                  value: _countryCode,
                  label: 'Country',
                  options: CountryCatalog.asSelectOptions(),
                  onChanged: (value) => setState(() => _countryCode = value),
                ),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Financial',
            children: [
              SelloFormRow(
                left: SelloTextField(
                  controller: _creditLimit,
                  label: 'Credit limit',
                  keyboardType: TextInputType.number,
                ),
                right: SelloTextField(
                  controller: _openingBalance,
                  label: 'Opening balance',
                  keyboardType: TextInputType.number,
                  enabled: _isCreate,
                  hint: _isCreate ? null : 'Set at create only',
                ),
              ),
              SelloTextField(
                controller: _paymentTerms,
                label: 'Payment terms',
                hint: 'e.g. Net 30',
              ),
              SelloFormRow(
                left: SelloTextField(controller: _bankName, label: 'Bank name'),
                right: SelloTextField(
                  controller: _bankAccount,
                  label: 'Bank account',
                ),
              ),
              if (!_isCreate)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Active',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Inactive suppliers are archived from the default list.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
            ],
          ),
          SelloDialogSection(
            title: 'Notes',
            children: [
              SelloTextField(controller: _notes, label: 'Notes', maxLines: 3),
            ],
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        onCancel: () => Navigator.of(context).maybePop(),
        primaryLabel: _isCreate ? 'Create supplier' : 'Save changes',
        onPrimary: _submit,
      ),
    );
  }
}
