import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/inventory/presentation/inventory_details_dialog.dart';
import 'package:sello/features/inventory/presentation/stock_adjust_dialog.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/models/stock_movement_type.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubInventoryPage extends ConsumerStatefulWidget {
  const HubInventoryPage({super.key});

  @override
  ConsumerState<HubInventoryPage> createState() => _HubInventoryPageState();
}

class _HubInventoryPageState extends ConsumerState<HubInventoryPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  final Set<String> _expandedProductIds = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _currencySymbol() {
    final currency = ref.read(companySettingsProvider).currency;
    return SelloFormatters.currencySymbol(currency);
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
    final movements =
        await ref.read(hubInventoryProvider.notifier).loadMovements(item);
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
                width: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelloTableText(
                      item.name,
                      tone: SelloTableTone.strong,
                    ),
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
        DataCell(SelloTableText(item.sku)),
        DataCell(
          SelloTableText(
            SelloFormatters.quantity(item.quantity),
            tone: SelloTableTone.strong,
            numeric: true,
          ),
        ),
        DataCell(
          SelloTableText(
            SelloFormatters.quantity(item.availableQuantity),
            tone: SelloTableTone.normal,
            numeric: true,
          ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelloButton(
                label: 'View',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.ghost,
                onPressed: () => _openDetails(item),
              ),
              const SizedBox(width: 4),
              SelloButton(
                label: 'Adjust',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.outline,
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
      cells: [
        DataCell(
          Row(
            children: [
              IconButton(
                tooltip: expanded ? 'Hide options' : 'Show options',
                onPressed: () => _toggleExpanded(group.productId),
                icon: Icon(
                  expanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
              SelloEntityThumb(
                name: item.name,
                imageUrl: item.imageUrl,
                width: 44,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelloTableText(
                      item.name,
                      tone: SelloTableTone.strong,
                    ),
                    const SizedBox(height: 2),
                    SelloTableText(
                      '${group.items.length} options'
                      '${item.categoryName != null ? ' · ${item.categoryName}' : ''}',
                      tone: SelloTableTone.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DataCell(SelloTableText(item.sku)),
        DataCell(
          SelloTableText(
            SelloFormatters.quantity(group.totalQuantity),
            tone: SelloTableTone.strong,
            numeric: true,
          ),
        ),
        DataCell(
          SelloTableText(
            SelloFormatters.quantity(group.totalAvailableQuantity),
            tone: SelloTableTone.normal,
            numeric: true,
          ),
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
          SelloButton(
            label: expanded ? 'Hide' : 'Options',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.ghost,
            onPressed: () => _toggleExpanded(group.productId),
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
            padding: const EdgeInsets.only(left: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SelloTableText(
                  label != null && label.isNotEmpty ? label : sku,
                  tone: SelloTableTone.strong,
                ),
                const SizedBox(height: 2),
                SelloTableText(
                  'Option',
                  tone: SelloTableTone.muted,
                ),
              ],
            ),
          ),
        ),
        DataCell(SelloTableText(sku)),
        DataCell(
          SelloTableText(
            SelloFormatters.quantity(item.quantity),
            tone: SelloTableTone.strong,
            numeric: true,
          ),
        ),
        DataCell(
          SelloTableText(
            SelloFormatters.quantity(item.availableQuantity),
            tone: SelloTableTone.normal,
            numeric: true,
          ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelloButton(
                label: 'View',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.ghost,
                onPressed: () => _openDetails(item),
              ),
              const SizedBox(width: 4),
              SelloButton(
                label: 'Adjust',
                size: SelloButtonSize.small,
                variant: SelloButtonVariant.outline,
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

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Inventory',
      subtitle:
          'Stock control center — on-hand quantities, adjustments, and movement history.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
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
                () =>
                    ref.read(hubInventoryProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubInventoryProvider.notifier).setStatusFilter(value);
              }
            },
            onCategoryChanged: (value) {
              ref.read(hubInventoryProvider.notifier).setCategoryFilter(
                    value == _allCategories ? null : value,
                  );
            },
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubInventoryProvider.notifier).refresh(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 8),
          ] else ...[
            _SummaryRow(
              stats: state.stats,
              currencySymbol: _currencySymbol(),
              onFilter: (filter) => ref
                  .read(hubInventoryProvider.notifier)
                  .setStatusFilter(filter),
            ),
            if (state.recentMovements.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _RecentMovementsStrip(movements: state.recentMovements),
            ],
            const SizedBox(height: AppSpacing.lg),
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
                                      'Stock ${SelloFormatters.quantity(group.primary.quantity)}',
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
                              Icon(
                                _expandedProductIds.contains(group.productId)
                                    ? Icons.expand_more_rounded
                                    : Icons.chevron_right_rounded,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              SelloEntityThumb(
                                name: group.primary.name,
                                imageUrl: group.primary.imageUrl,
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
                                      '${group.items.length} options · Stock ${SelloFormatters.quantity(group.totalQuantity)}',
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
                                            item.variantLabel?.trim().isNotEmpty ==
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
                                            'SKU ${item.variantSku ?? item.sku} · Stock ${SelloFormatters.quantity(item.quantity)}',
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
                      hasMore: state.hasMore,
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
                  columns: [
                    selloDataColumn('Product'),
                    selloDataColumn('SKU'),
                    selloDataColumn('On hand', numeric: true),
                    selloDataColumn('Available', numeric: true),
                    selloDataColumn('Reorder', numeric: true),
                    selloDataColumn('Status'),
                    selloDataColumn('Last movement'),
                    selloDataColumn('Actions'),
                  ],
                  rows: _buildGroupedRows(groups),
                  footer: _Pager(
                    page: state.page,
                    hasMore: state.hasMore,
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
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final HubInventoryState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<StockStatusFilter?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 160,
      child: SelloDropdown<StockStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Stock status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(
            value: StockStatusFilter.all,
            child: Text('All'),
          ),
          DropdownMenuItem(
            value: StockStatusFilter.inStock,
            child: Text('In stock'),
          ),
          DropdownMenuItem(
            value: StockStatusFilter.lowStock,
            child: Text('Low stock'),
          ),
          DropdownMenuItem(
            value: StockStatusFilter.outOfStock,
            child: Text('Out of stock'),
          ),
          DropdownMenuItem(
            value: StockStatusFilter.negativeStock,
            child: Text('Negative stock'),
          ),
          DropdownMenuItem(
            value: StockStatusFilter.recentlyUpdated,
            child: Text('Recently updated'),
          ),
          DropdownMenuItem(
            value: StockStatusFilter.archived,
            child: Text('Archived'),
          ),
        ],
      ),
    );

    final category = SizedBox(
      width: context.isMobile ? double.infinity : 168,
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
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onRefresh,
    );

    final search = SelloSearchBar(
      controller: searchController,
      hint: 'Search products or SKU…',
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
        actions: [refresh],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.stats,
    required this.currencySymbol,
    required this.onFilter,
  });

  final InventoryDashboardStats stats;
  final String currencySymbol;
  final ValueChanged<StockStatusFilter> onFilter;

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
          onTap: () => onFilter(StockStatusFilter.all),
        ),
        SelloStatCard(
          label: 'Stock value',
          value: SelloFormatters.currency(
            stats.stockValue,
            symbol: currencySymbol,
          ),
          hint: 'At cost',
          icon: Icons.payments_outlined,
          tone: AppColors.finance,
        ),
        SelloStatCard(
          label: 'Low stock',
          value: '${stats.lowStock}',
          hint: 'At or below reorder',
          icon: Icons.warning_amber_rounded,
          tone: AppColors.warning,
          onTap: () => onFilter(StockStatusFilter.lowStock),
        ),
        SelloStatCard(
          label: 'Out of stock',
          value: '${stats.outOfStock}',
          hint: 'Zero on hand',
          icon: Icons.error_outline_rounded,
          tone: AppColors.error,
          onTap: () => onFilter(StockStatusFilter.outOfStock),
        ),
        SelloStatCard(
          label: 'Movements',
          value: '${stats.recentMovements}',
          hint: 'Last 7 days',
          icon: Icons.swap_vert_rounded,
          tone: AppColors.inventory,
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
          Text(
            'RECENTLY ADJUSTED',
            style: AppTypography.eyebrow,
          ),
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
