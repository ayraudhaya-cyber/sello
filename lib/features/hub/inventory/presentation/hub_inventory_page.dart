import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/inventory/presentation/inventory_details_dialog.dart';
import 'package:sello/features/inventory/presentation/stock_adjust_dialog.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/models/stock_movement_type.dart';
import 'package:sello/shared/utils/browser_file_download.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubInventoryPage extends ConsumerStatefulWidget {
  const HubInventoryPage({super.key});

  @override
  ConsumerState<HubInventoryPage> createState() => _HubInventoryPageState();
}

class _HubInventoryPageState extends ConsumerState<HubInventoryPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  final Set<String> _expandedProductIds = {};
  var _exporting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _currencySymbol() {
    final currency = ref.read(companySettingsProvider).currency;
    return SelloFormatters.currencySymbol(currency);
  }

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await ref
          .read(hubInventoryProvider.notifier)
          .exportStockWorkbook();
      if (!mounted) return;
      final saved = await downloadBrowserFile(
        bytes: file.bytes,
        filename: file.filename,
        mimeType: 'application/vnd.ms-excel',
      );
      if (!mounted) return;
      SelloSnackbars.success(
        context,
        saved
            ? 'Export saved to your Downloads folder.'
            : 'Inventory export downloaded.',
      );
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.error(context, failure.message);
    } on UnsupportedError catch (error) {
      if (!mounted) return;
      SelloSnackbars.warning(
        context,
        error.message ?? 'Unable to save this export.',
      );
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to export inventory right now.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toggleExpanded(String productId) {
    setState(() {
      if (_expandedProductIds.contains(productId)) {
        _expandedProductIds.remove(productId);
      } else {
        _expandedProductIds.add(productId);
      }
    });
  }

  Future<void> _openDetails(InventoryItem item) async {
    final movements = await ref
        .read(hubInventoryProvider.notifier)
        .loadMovements(item);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => InventoryDetailsDialog(
        item: item,
        movements: movements,
        onAdjust: () async {
          Navigator.of(context).pop();
          await _openAdjust(item);
        },
      ),
    );
  }

  Future<void> _openAdjust(InventoryItem item) async {
    final result = await showDialog<StockAdjustResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StockAdjustDialog(item: item),
    );
    if (result == null) return;

    final error = await ref
        .read(hubInventoryProvider.notifier)
        .adjustStock(result.input);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Stock updated.');
    }
  }

  List<DataRow> _buildGroupedRows(List<InventoryProductGroup> groups) {
    final rows = <DataRow>[];
    for (final group in groups) {
      if (!group.isMultiOption) {
        final item = group.primary;
        rows.add(_flatRow(item));
        continue;
      }

      final expanded = _expandedProductIds.contains(group.productId);
      rows.add(_parentRow(group, expanded: expanded));
      if (expanded) {
        for (final item in group.items) {
          rows.add(_childRow(item));
        }
      }
    }
    return rows;
  }

  bool get _showShortageColumns =>
      ref.read(hubInventoryProvider).statusFilter ==
      StockStatusFilter.shortage;

  String _stockSummary({
    required num onHand,
    required num reserved,
    required num shortage,
  }) {
    final stock =
        'On hand ${SelloFormatters.quantity(onHand)}'
        ' · Reserved ${SelloFormatters.quantity(reserved)}';
    if (!_showShortageColumns) return stock;
    final short = shortage > 0
        ? ' · Shortage ${SelloFormatters.quantity(shortage)}'
        : '';
    return '$stock$short';
  }

  List<DataCell> _quantityCells({
    required num onHand,
    required num reserved,
    required num available,
    required num shortage,
  }) {
    return [
      DataCell(
        SelloTableText(
          SelloFormatters.quantity(onHand),
          numeric: true,
        ),
      ),
      DataCell(
        SelloTableText(
          SelloFormatters.quantity(reserved),
          numeric: true,
        ),
      ),
      if (_showShortageColumns) ...[
        DataCell(
          shortage > 0
              ? SelloTableText(
                  SelloFormatters.quantity(shortage),
                  tone: SelloTableTone.strong,
                  numeric: true,
                  color: AppColors.warning,
                )
              : const SelloTableText(
                  '—',
                  tone: SelloTableTone.muted,
                  numeric: true,
                ),
        ),
      ],
      DataCell(
        SelloTableText(
          SelloFormatters.quantity(available),
          tone: SelloTableTone.strong,
          numeric: true,
        ),
      ),
    ];
  }

  DataRow _flatRow(InventoryItem item) {
    return DataRow(
      onSelectChanged: (_) => _openDetails(item),
      cells: [
        DataCell(
          Row(
            children: [
              SelloEntityThumb(
                name: item.name,
                imageUrl: item.imageUrl,
                cacheKey: item.imageCacheKey,
                width: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelloTableText(item.name, tone: SelloTableTone.strong),
                    if (item.categoryName != null) ...[
                      const SizedBox(height: 2),
                      SelloTableText(
                        item.categoryName!,
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
          SelloTableText(item.sku, tone: SelloTableTone.muted),
        ),
        ..._quantityCells(
          onHand: item.quantity,
          reserved: item.reservedQuantity,
          available: item.availableQuantity,
          shortage: item.shortageQuantity,
        ),
        DataCell(
          SelloTableText(
            item.reorderLevel == null
                ? '—'
                : SelloFormatters.quantity(item.reorderLevel!),
            tone: item.reorderLevel == null
                ? SelloTableTone.muted
                : SelloTableTone.normal,
            numeric: true,
          ),
        ),
        DataCell(_statusBadge(item)),
        DataCell(
          SelloTableText(
            item.lastMovementAt != null
                ? SelloFormatters.date(item.lastMovementAt)
                : '—',
            tone: SelloTableTone.muted,
          ),
        ),
        DataCell(
          SelloRowIconGroup(
            children: [
              SelloRowIconButton(
                tooltip: 'View stock',
                icon: Icons.visibility_outlined,
                onPressed: () => _openDetails(item),
              ),
              SelloRowIconButton(
                tooltip: 'Adjust stock',
                icon: Icons.tune_rounded,
                onPressed: () => _openAdjust(item),
              ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _parentRow(InventoryProductGroup group, {required bool expanded}) {
    final item = group.primary;
    return DataRow(
      onSelectChanged: (_) => _toggleExpanded(group.productId),
      cells: [
        DataCell(
          Row(
            children: [
              SelloEntityThumb(
                name: item.name,
                imageUrl: item.imageUrl,
                cacheKey: item.imageCacheKey,
                width: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelloTableText(item.name, tone: SelloTableTone.strong),
                    const SizedBox(height: 2),
                    _OptionCountButton(
                      count: group.items.length,
                      expanded: expanded,
                      onPressed: () => _toggleExpanded(group.productId),
                    ),
                    if (item.categoryName != null)
                      SelloTableText(
                        item.categoryName!,
                        tone: SelloTableTone.muted,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DataCell(
          SelloTableText(item.sku, tone: SelloTableTone.muted),
        ),
        ..._quantityCells(
          onHand: group.totalQuantity,
          reserved: group.totalReservedQuantity,
          available: group.totalAvailableQuantity,
          shortage: group.shortageQuantity,
        ),
        DataCell(
          SelloTableText(
            group.reorderLevel == null
                ? '—'
                : SelloFormatters.quantity(group.reorderLevel!),
            tone: group.reorderLevel == null
                ? SelloTableTone.muted
                : SelloTableTone.normal,
            numeric: true,
          ),
        ),
        DataCell(_statusBadgeForStatus(group.stockStatus)),
        DataCell(
          SelloTableText(
            group.lastMovementAt != null
                ? SelloFormatters.date(group.lastMovementAt)
                : '—',
            tone: SelloTableTone.muted,
          ),
        ),
        DataCell(
          SelloRowIconGroup(
            children: [
              SelloRowIconButton(
                tooltip: expanded ? 'Hide options' : 'Show options',
                icon: expanded
                    ? Icons.unfold_less_rounded
                    : Icons.account_tree_outlined,
                onPressed: () => _toggleExpanded(group.productId),
              ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _childRow(InventoryItem item) {
    final label = item.variantLabel?.trim();
    final sku = item.variantSku?.trim().isNotEmpty == true
        ? item.variantSku!.trim()
        : item.sku;
    return DataRow(
      onSelectChanged: (_) => _openDetails(item),
      cells: [
        DataCell(
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SelloTableText(
                  label != null && label.isNotEmpty ? label : sku,
                  tone: SelloTableTone.strong,
                ),
                const SizedBox(height: 2),
                SelloTableText('Option', tone: SelloTableTone.muted),
              ],
            ),
          ),
        ),
        DataCell(SelloTableText(sku, tone: SelloTableTone.muted)),
        ..._quantityCells(
          onHand: item.quantity,
          reserved: item.reservedQuantity,
          available: item.availableQuantity,
          shortage: item.shortageQuantity,
        ),
        DataCell(
          SelloTableText(
            item.reorderLevel == null
                ? '—'
                : SelloFormatters.quantity(item.reorderLevel!),
            tone: item.reorderLevel == null
                ? SelloTableTone.muted
                : SelloTableTone.normal,
            numeric: true,
          ),
        ),
        DataCell(_statusBadge(item)),
        DataCell(
          SelloTableText(
            item.lastMovementAt != null
                ? SelloFormatters.date(item.lastMovementAt)
                : '—',
            tone: SelloTableTone.muted,
          ),
        ),
        DataCell(
          SelloRowIconGroup(
            children: [
              SelloRowIconButton(
                tooltip: 'View stock',
                icon: Icons.visibility_outlined,
                onPressed: () => _openDetails(item),
              ),
              SelloRowIconButton(
                tooltip: 'Adjust stock',
                icon: Icons.tune_rounded,
                onPressed: () => _openAdjust(item),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubInventoryProvider);
    ref.watch(hubSettingsProvider);
    final groups = groupInventoryItems(state.items);

    if (!_searchFocus.hasFocus && _searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Inventory',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            searchController: _searchController,
            searchFocus: _searchFocus,
            state: state,
            onSearchChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubInventoryProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubInventoryProvider.notifier).setStatusFilter(value);
              }
            },
            onCategoryChanged: (value) {
              ref
                  .read(hubInventoryProvider.notifier)
                  .setCategoryFilter(value == _allCategories ? null : value);
            },
            onRefresh: () => ref.read(hubInventoryProvider.notifier).refresh(),
            isRefreshing: state.isLoading,
            onExport: _exportData,
            isExporting: _exporting,
            onClearFilters: state.hasActiveFilters
                ? () {
                    _searchController.clear();
                    ref.read(hubInventoryProvider.notifier).clearFilters();
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          SelloInlineRefreshBar(
            active: state.isLoading && state.items.isNotEmpty,
          ),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              SelloTableSkeleton(
                columns: state.statusFilter == StockStatusFilter.shortage
                    ? 10
                    : 8,
              ),
          ] else ...[
            _SummaryRow(
              stats: state.stats,
              currencySymbol: _currencySymbol(),
              amountDisplay: ref.watch(companySettingsProvider).amountDisplay,
              showValuation:
                  ref.watch(currentRoleProvider)?.canViewInventoryValuation ??
                  false,
              onFilter: (filter) => ref
                  .read(hubInventoryProvider.notifier)
                  .setStatusFilter(filter),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isNotEmpty)
              SelloInlineErrorBar(
                message: state.errorMessage,
                onRetry: () =>
                    ref.read(hubInventoryProvider.notifier).refresh(),
              ),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load inventory',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubInventoryProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              const SelloCard(
                child: SelloEmptyState(
                  title: 'No inventory rows yet',
                  message:
                      'Create products to seed branch stock. Completing sales '
                      'and stock adjustments will build movement history here.',
                  icon: Icons.warehouse_rounded,
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final group in groups) ...[
                      if (!group.isMultiOption)
                        SelloCard(
                          onTap: () => _openDetails(group.primary),
                          child: Row(
                            children: [
                              SelloEntityThumb(
                                name: group.primary.name,
                                imageUrl: group.primary.imageUrl,
                                cacheKey: group.primary.imageCacheKey,
                                width: 48,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.primary.name,
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _stockSummary(
                                        onHand: group.primary.quantity,
                                        reserved: group.primary.reservedQuantity,
                                        shortage: group.primary.shortageQuantity,
                                      ),
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _statusBadge(group.primary),
                            ],
                          ),
                        )
                      else ...[
                        SelloCard(
                          onTap: () => _toggleExpanded(group.productId),
                          child: Row(
                            children: [
                              SelloEntityThumb(
                                name: group.primary.name,
                                imageUrl: group.primary.imageUrl,
                                cacheKey: group.primary.imageCacheKey,
                                width: 48,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.primary.name,
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${group.items.length} options · ${_stockSummary(onHand: group.totalQuantity, reserved: group.totalReservedQuantity, shortage: group.shortageQuantity)}',
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _statusBadgeForStatus(group.stockStatus),
                              const SizedBox(width: 4),
                              Icon(
                                _expandedProductIds.contains(group.productId)
                                    ? Icons.expand_more_rounded
                                    : Icons.chevron_right_rounded,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                        if (_expandedProductIds.contains(group.productId))
                          for (final item in group.items) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: SelloCard(
                                onTap: () => _openDetails(item),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.variantLabel
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? item.variantLabel!.trim()
                                                : (item.variantSku ?? item.sku),
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTypography.fontFamily,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'SKU ${item.variantSku ?? item.sku} · ${_stockSummary(onHand: item.quantity, reserved: item.reservedQuantity, shortage: item.shortageQuantity)}',
                                            style: const TextStyle(
                                              fontFamily:
                                                  AppTypography.fontFamily,
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SelloButton(
                                      label: 'Adjust',
                                      size: SelloButtonSize.small,
                                      variant: SelloButtonVariant.outline,
                                      onPressed: () => _openAdjust(item),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                      ],
                      const SizedBox(height: 10),
                    ],
                    _Pager(
                      page: state.page,
                      pageSize: state.pageSize,
                      matchedCount: state.matchedCount,
                      hasMore: state.hasMore,
                      onPageSize: (size) => ref
                          .read(hubInventoryProvider.notifier)
                          .setPageSize(size),
                      onPrev: state.page <= 0
                          ? null
                          : () => ref
                                .read(hubInventoryProvider.notifier)
                                .goToPage(state.page - 1),
                      onNext: !state.hasMore
                          ? null
                          : () => ref
                                .read(hubInventoryProvider.notifier)
                                .goToPage(state.page + 1),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  dataRowMinHeight: 64,
                  columns: [
                    selloDataColumn('Product'),
                    selloDataColumn('SKU'),
                    selloDataColumn('On hand', numeric: true),
                    selloDataColumn('Reserved', numeric: true),
                    if (state.statusFilter == StockStatusFilter.shortage)
                      selloDataColumn('Shortage', numeric: true),
                    selloDataColumn('Available', numeric: true),
                    selloDataColumn('Reorder', numeric: true),
                    selloDataColumn('Status'),
                    selloDataColumn('Last movement'),
                    selloDataColumn('Actions'),
                  ],
                  rows: _buildGroupedRows(groups),
                  footer: _Pager(
                    page: state.page,
                    pageSize: state.pageSize,
                    matchedCount: state.matchedCount,
                    hasMore: state.hasMore,
                    onPageSize: (size) => ref
                        .read(hubInventoryProvider.notifier)
                        .setPageSize(size),
                    onPrev: state.page <= 0
                        ? null
                        : () => ref
                              .read(hubInventoryProvider.notifier)
                              .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                              .read(hubInventoryProvider.notifier)
                              .goToPage(state.page + 1),
                  ),
                ),
              ),
            if (state.recentMovements.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _RecentMovementsStrip(movements: state.recentMovements),
            ],
          ],
        ],
      ),
    );
  }
}

const _allCategories = '__all__';

Widget _statusBadge(InventoryItem item) {
  return _statusBadgeForStatus(item.stockStatus);
}

Widget _statusBadgeForStatus(StockStatus status) {
  return SelloStatusBadge(
    label: status.label,
    tone: switch (status) {
      StockStatus.healthy => SelloStatusTone.success,
      StockStatus.low => SelloStatusTone.warning,
      StockStatus.out => SelloStatusTone.danger,
      StockStatus.archived => SelloStatusTone.neutral,
    },
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.searchFocus,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onRefresh,
    required this.isRefreshing,
    required this.onExport,
    required this.isExporting,
    this.onClearFilters,
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final HubInventoryState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<StockStatusFilter?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final VoidCallback onExport;
  final bool isExporting;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final inStock = (state.stats.totalItems -
            state.stats.outOfStock -
            state.stats.lowStock)
        .clamp(0, 1 << 31);
    final statusActive = state.statusFilter != StockStatusFilter.all;
    final categoryActive = state.categoryId != null;
    final status = _ActiveFilter(
      active: statusActive,
      child: SizedBox(
        width: context.isMobile ? double.infinity : 220,
        child: SelloDropdown<StockStatusFilter>(
          value: state.statusFilter,
          compact: true,
          hint: 'Stock',
          onChanged: onStatusChanged,
          items: [
            const DropdownMenuItem(
              value: StockStatusFilter.all,
              child: Text('All stock'),
            ),
            DropdownMenuItem(
              value: StockStatusFilter.inStock,
              child: Text('In stock · $inStock'),
            ),
            const DropdownMenuItem(
              value: StockStatusFilter.lowStock,
              child: Text('Low stock'),
            ),
            DropdownMenuItem(
              value: StockStatusFilter.outOfStock,
              child: Text('Out of stock · ${state.stats.outOfStock}'),
            ),
            const DropdownMenuItem(
              value: StockStatusFilter.negativeStock,
              child: Text('Negative stock'),
            ),
            const DropdownMenuItem(
              value: StockStatusFilter.shortage,
              child: Text('Shortage only'),
            ),
            const DropdownMenuItem(
              value: StockStatusFilter.recentlyUpdated,
              child: Text('Recently updated'),
            ),
            const DropdownMenuItem(
              value: StockStatusFilter.archived,
              child: Text('Inactive'),
            ),
          ],
        ),
      ),
    );

    final category = _ActiveFilter(
      active: categoryActive,
      child: SizedBox(
        width: context.isMobile ? double.infinity : 180,
        child: SelloDropdown<String>(
          value: state.categoryId ?? _allCategories,
          compact: true,
          hint: 'Category',
          onChanged: onCategoryChanged,
          items: [
            const DropdownMenuItem(
              value: _allCategories,
              child: Text('All categories'),
            ),
            for (final cat in state.categories)
              DropdownMenuItem(value: cat.id, child: Text(cat.name)),
          ],
        ),
      ),
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      loading: isRefreshing,
      onPressed: isRefreshing || isExporting ? null : onRefresh,
    );

    final export = SelloButton(
      label: 'Export data',
      icon: Icons.download_rounded,
      variant: SelloButtonVariant.outline,
      loading: isExporting,
      onPressed: isRefreshing || isExporting ? null : onExport,
    );

    final search = SelloSearchBar(
      controller: searchController,
      focusNode: searchFocus,
      hint: 'Search products or SKU...',
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
        filters: [status, category],
        actions: [export, refresh],
        stackBelow: 1600,
        onClearFilters: onClearFilters,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.stats,
    required this.currencySymbol,
    required this.amountDisplay,
    required this.onFilter,
    this.showValuation = false,
  });

  final InventoryDashboardStats stats;
  final String currencySymbol;
  final AmountDisplayStyle amountDisplay;
  final ValueChanged<StockStatusFilter> onFilter;

  /// Worth at cost / selling — Owner only.
  final bool showValuation;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Total products',
          value: '${stats.totalItems}',
          hint: 'Active catalog',
          icon: Icons.inventory_2_outlined,
          tone: context.brandAccent,
          compact: true,
          onTap: () => onFilter(StockStatusFilter.all),
        ),
        if (showValuation) ...[
          SelloStatCard(
            label: 'Worth at cost',
            value: SelloFormatters.summaryAmount(
              stats.stockValue,
              symbol: currencySymbol,
              style: amountDisplay,
            ),
            hint: 'Quantity × cost price',
            icon: Icons.payments_outlined,
            tone: AppColors.finance,
            compact: true,
          ),
          SelloStatCard(
            label: 'Worth at selling',
            value: SelloFormatters.summaryAmount(
              stats.stockSellingValue,
              symbol: currencySymbol,
              style: amountDisplay,
            ),
            hint: 'Quantity × selling price',
            icon: Icons.storefront_outlined,
            tone: AppColors.success,
            compact: true,
          ),
        ],
        SelloStatCard(
          label: 'Out of stock',
          value: '${stats.outOfStock}',
          hint: 'Zero on hand',
          icon: Icons.error_outline_rounded,
          tone: AppColors.error,
          compact: true,
          onTap: () => onFilter(StockStatusFilter.outOfStock),
        ),
        SelloStatCard(
          label: 'Movements',
          value: '${stats.recentMovements}',
          hint: 'Last 7 days',
          icon: Icons.swap_vert_rounded,
          tone: AppColors.inventory,
          compact: true,
          onTap: () => onFilter(StockStatusFilter.recentlyUpdated),
        ),
      ],
    );
  }
}

class _RecentMovementsStrip extends StatelessWidget {
  const _RecentMovementsStrip({required this.movements});

  final List<StockMovement> movements;

  @override
  Widget build(BuildContext context) {
    final shown = movements.take(6).toList(growable: false);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('RECENTLY ADJUSTED', style: AppTypography.eyebrow),
          const SizedBox(height: 12),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      shown[i].productName ?? 'Product',
                      shown[i].displayTitle,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                Text(
                  '${shown[i].quantityDelta > 0 ? '+' : ''}'
                  '${SelloFormatters.quantity(shown[i].quantityDelta)}',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    color: shown[i].quantityDelta > 0
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  SelloFormatters.date(shown[i].createdAt),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageSize,
    required this.matchedCount,
    required this.hasMore,
    required this.onPageSize,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final int pageSize;
  final int matchedCount;
  final bool hasMore;
  final ValueChanged<int> onPageSize;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final productLabel = matchedCount == 1 ? 'product' : 'products';
    final summary = matchedCount <= 0
        ? 'Page ${page + 1}'
        : 'Page ${page + 1} · $matchedCount $productLabel';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            summary,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(
            width: 108,
            child: SelloDropdown<int>(
              value: pageSize,
              compact: true,
              hint: 'Rows',
              onChanged: (value) {
                if (value != null) onPageSize(value);
              },
              items: const [
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 25, child: Text('25')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
              ],
            ),
          ),
          SelloButton(
            label: 'Previous',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.outline,
            onPressed: onPrev,
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

class _ActiveFilter extends StatelessWidget {
  const _ActiveFilter({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.controlAll,
        border: Border.all(
          color: context.brandAccent.withValues(alpha: 0.45),
        ),
      ),
      child: child,
    );
  }
}

class _OptionCountButton extends StatelessWidget {
  const _OptionCountButton({
    required this.count,
    required this.expanded,
    required this.onPressed,
  });

  final int count;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 option' : '$count options';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: context.brandAccent,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          expanded ? '$label · hide' : label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.brandAccent,
          ),
        ),
      ),
    );
  }
}
