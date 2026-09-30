import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/features/hub/products/application/hub_products_provider.dart';
import 'package:sello/features/hub/products/presentation/product_details_dialog.dart';
import 'package:sello/features/hub/products/presentation/product_editor_widgets.dart';
import 'package:sello/features/hub/products/presentation/product_options_section.dart';
import 'package:sello/features/hub/products/presentation/product_variant_rules.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/models/inventory_product_group.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/item_code_generator.dart';
import 'package:sello/shared/utils/product_detail_suggestions.dart';
import 'package:sello/shared/utils/quick_new_query.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubProductsPage extends ConsumerStatefulWidget {
  const HubProductsPage({super.key});

  @override
  ConsumerState<HubProductsPage> createState() => _HubProductsPageState();
}

class _HubProductsPageState extends ConsumerState<HubProductsPage>
    with QuickNewQueryMixin {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    consumeQuickNewQuery(
      cleanPath: RoutePaths.hubProducts,
      open: () => _openEditor(),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor({ProductSummary? product}) async {
    final state = ref.read(hubProductsProvider);
    final settingsState = ref.read(hubSettingsProvider);
    if (!settingsState.initialized) {
      await ref.read(hubSettingsProvider.notifier).load();
    }
    if (!mounted) return;
    final settings = ref.read(companySettingsProvider);
    final result = await showDialog<_EditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProductEditorDialog(
        product: product,
        categories: state.categories,
        repository: ref.read(productRepositoryProvider),
        defaultReorderLevel: settings.defaultReorderLevel,
        defaultIsActive: settings.defaultProductStatus.isActive,
      ),
    );

    if (result == null || !mounted) return;
    SelloSnackbars.success(
      context,
      result.created ? 'Product created.' : 'Product updated.',
    );
  }

  Future<void> _openDetails(ProductSummary product) async {
    final currency = ref.read(companySettingsProvider).currency;
    final currencySymbol = switch (currency) {
      'LKR' => 'Rs ',
      'EUR' => '€',
      'GBP' => '£',
      'INR' => '₹',
      'JPY' => '¥',
      _ => '\$',
    };
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ProductDetailsDialog(
        product: product,
        currencySymbol: currencySymbol,
        onEdit: () {
          Navigator.of(context).pop();
          _openEditor(product: product);
        },
        onToggleArchive: () async {
          Navigator.of(context).pop();
          await _toggleArchive(product);
        },
        onDeletePermanently: product.isActive
            ? null
            : () async {
                Navigator.of(context).pop();
                await _deletePermanently(product);
              },
      ),
    );
  }

  Future<void> _toggleArchive(ProductSummary product) async {
    final archived = product.isActive;
    final confirmed = await showSelloDialog(
      context: context,
      title: archived ? 'Deactivate product?' : 'Reactivate product?',
      message: archived
          ? '"${product.name}" will be hidden from new sales. '
                'Past orders keep its name, price, and options. '
                'You can reactivate it from the Inactive filter.'
          : '"${product.name}" will be available for new sales again.',
      confirmLabel: archived ? 'Deactivate' : 'Reactivate',
      cancelLabel: 'Cancel',
      destructive: archived,
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(hubProductsProvider.notifier)
        .setArchived(product, archived: archived);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(
        context,
        archived ? 'Product deactivated.' : 'Product reactivated.',
      );
    }
  }

  Future<void> _deletePermanently(ProductSummary product) async {
    if (product.isActive) {
      SelloSnackbars.warning(
        context,
        'Deactivate the product before permanently deleting it.',
      );
      return;
    }

    final confirmed = await showSelloDialog(
      context: context,
      title: 'Delete permanently?',
      message:
          '"${product.name}" will be removed permanently. '
          'This is only for a product that was never sold and has no stock history. '
          'This cannot be undone.',
      confirmLabel: 'Delete permanently',
      cancelLabel: 'Keep inactive',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(hubProductsProvider.notifier)
        .permanentlyDelete(product);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Product permanently deleted.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubProductsProvider);
    // Warm company settings so Add Product can apply inventory defaults.
    ref.watch(hubSettingsProvider);
    final session = ref.watch(currentSessionProvider);
    final currencySymbol = session?.company.companyCode == 'UNITECH'
        ? '\$'
        : '\$';

    ref.listen<String?>(hubProductsProvider.select((s) => s.errorMessage), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      if (!next.startsWith('Product saved, but photos')) return;
      if (!context.mounted) return;
      SelloSnackbars.warning(context, next);
    });

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Products',
      subtitle:
          'Your catalog is the single source of truth for every sellable item.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProductsToolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubProductsProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubProductsProvider.notifier).setStatusFilter(value);
              }
            },
            onCategoryChanged: (value) {
              ref.read(hubProductsProvider.notifier).setCategoryFilter(value);
            },
            onRefresh: () => ref.read(hubProductsProvider.notifier).refresh(),
            isRefreshing: state.isLoading,
            onAdd: state.isSaving ? null : () => _openEditor(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.statusFilter == ProductStatusFilter.inactive) ...[
            const _ArchivedProductsBanner(),
            const SizedBox(height: AppSpacing.md),
          ],
          SelloInlineRefreshBar(
            active: state.isLoading && state.items.isNotEmpty,
          ),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 7),
          ] else ...[
            _CatalogSummaryRow(
              visibleCount: state.items.length,
              activeCount: state.items.where((item) => item.isActive).length,
              archivedCount: state.items.where((item) => !item.isActive).length,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load products',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubProductsProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: state.statusFilter == ProductStatusFilter.inactive
                      ? 'No inactive products'
                      : 'Start building your catalog',
                  message: state.statusFilter == ProductStatusFilter.inactive
                      ? 'Inactive products stay out of new sales. Past orders keep '
                            'the product name, price, and options. Reactivate one '
                            'here when you need it again.'
                      : 'Add your first sellable product with pricing, stock, and an image. '
                            'Orders, inventory, and reporting will build on this catalog.',
                  icon: state.statusFilter == ProductStatusFilter.inactive
                      ? Icons.inventory_2_outlined
                      : Icons.inventory_2_rounded,
                  actionLabel:
                      state.statusFilter == ProductStatusFilter.inactive
                      ? null
                      : 'Add Product',
                  onAction: state.statusFilter == ProductStatusFilter.inactive
                      ? null
                      : () => _openEditor(),
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final product in state.items) ...[
                      _ProductListCard(
                        product: product,
                        currencySymbol: currencySymbol,
                        onTap: () => _openDetails(product),
                        onEdit: () => _openEditor(product: product),
                        onToggleArchive: () => _toggleArchive(product),
                        onDeletePermanently: product.isActive
                            ? null
                            : () => _deletePermanently(product),
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
                                  .read(hubProductsProvider.notifier)
                                  .goToPage(state.page - 1),
                        onNext: !state.hasMore
                            ? null
                            : () => ref
                                  .read(hubProductsProvider.notifier)
                                  .goToPage(state.page + 1),
                      ),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  columns: [
                    selloDataColumn('Product'),
                    selloDataColumn('Category'),
                    selloDataColumn('Unit'),
                    selloDataColumn('Sell price', numeric: true),
                    selloDataColumn('Cost price', numeric: true),
                    selloDataColumn('Stock', numeric: true),
                    selloDataColumn('Status'),
                    selloDataColumn('Updated'),
                    selloDataColumn('Actions'),
                  ],
                  rows: [
                    for (final product in state.items)
                      DataRow(
                        onSelectChanged: (_) => _openDetails(product),
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                SelloEntityThumb(
                                  imageUrl: product.imageUrl,
                                  width: 44,
                                  name: product.name,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SelloTableText(
                                        product.name,
                                        tone: SelloTableTone.strong,
                                      ),
                                      const SizedBox(height: 2),
                                      SelloTableText(
                                        _productListSubtitle(product),
                                        tone: SelloTableTone.muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            SelloTableText(
                              product.categoryName ?? 'Uncategorized',
                            ),
                          ),
                          DataCell(
                            SelloTableText(
                              product.unitLabel ?? '-',
                              tone: SelloTableTone.muted,
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.centerRight,
                              child: SelloTableText(
                                product.isMultiOptionProduct
                                    ? '—'
                                    : SelloFormatters.currency(
                                        product.sellingPrice,
                                        symbol: currencySymbol,
                                      ),
                                tone: product.isMultiOptionProduct
                                    ? SelloTableTone.muted
                                    : SelloTableTone.strong,
                                numeric: true,
                              ),
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.centerRight,
                              child: SelloTableText(
                                product.isMultiOptionProduct
                                    ? '—'
                                    : SelloFormatters.currency(
                                        product.costPrice,
                                        symbol: currencySymbol,
                                      ),
                                tone: product.isMultiOptionProduct
                                    ? SelloTableTone.muted
                                    : SelloTableTone.normal,
                                numeric: true,
                              ),
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.centerRight,
                              child: product.isMultiOptionProduct
                                  ? _MultiOptionStockCell(product: product)
                                  : SelloTableText(
                                      SelloFormatters.quantity(
                                        product.currentStockQuantity,
                                      ),
                                      numeric: true,
                                    ),
                            ),
                          ),
                          DataCell(
                            _ProductStatusBadge(active: product.isActive),
                          ),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.date(product.updatedAt),
                              tone: SelloTableTone.muted,
                            ),
                          ),
                          DataCell(
                            _RowActionGroup(
                              onView: () => _openDetails(product),
                              onEdit: () => _openEditor(product: product),
                              onToggleArchive: () => _toggleArchive(product),
                              onDeletePermanently: product.isActive
                                  ? null
                                  : () => _deletePermanently(product),
                              isActive: product.isActive,
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
                              .read(hubProductsProvider.notifier)
                              .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                              .read(hubProductsProvider.notifier)
                              .goToPage(state.page + 1),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _productListSubtitle(ProductSummary product) {
    final fieldConfig = ref.watch(productFieldConfigProvider).valueOrNull;
    final listFields = fieldConfig?.forList ?? const <CompanyProductField>[];
    // Prefer attribute/spec fields for the subtitle so we don't duplicate
    // brand/unit columns already visible in the table.
    final specFields = listFields
        .where((f) => f.definition.storage == ProductFieldStorage.attribute)
        .take(2)
        .toList(growable: false);
    final specs = productSpecLine(
      fields: specFields,
      readValue: (key) => productFieldRawValue(product, key),
      maxParts: 2,
    );
    final parts = <String>[product.sku];
    if (specs.isNotEmpty) parts.add(specs);
    if (product.isMultiOptionProduct && product.activeOptionCount > 1) {
      parts.add('${product.activeOptionCount} options');
    }
    return parts.join(' · ');
  }
}

class _ProductsToolbar extends StatelessWidget {
  const _ProductsToolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onRefresh,
    required this.isRefreshing,
    required this.onAdd,
  });

  final TextEditingController searchController;
  final HubProductsState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ProductStatusFilter?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 148,
      child: SelloDropdown<ProductStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(value: ProductStatusFilter.all, child: Text('All')),
          DropdownMenuItem(
            value: ProductStatusFilter.active,
            child: Text('Active'),
          ),
          DropdownMenuItem(
            value: ProductStatusFilter.inactive,
            child: Text('Inactive'),
          ),
        ],
      ),
    );

    final category = SizedBox(
      width: context.isMobile ? double.infinity : 180,
      child: SelloDropdown<String?>(
        value: state.categoryId,
        compact: true,
        hint: 'Category',
        onChanged: onCategoryChanged,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All categories'),
          ),
          for (final category in state.categories)
            DropdownMenuItem<String?>(
              value: category.id,
              child: Text(category.name),
            ),
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

    final add = SelloButton(
      label: 'Add Product',
      icon: Icons.add_rounded,
      variant: SelloButtonVariant.primary,
      onPressed: onAdd,
    );

    final search = SelloSearchBar(
      controller: searchController,
      hint: 'Search by product, SKU, barcode or brand...',
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
        actions: [refresh, add],
      ),
    );
  }
}

class _CatalogSummaryRow extends StatelessWidget {
  const _CatalogSummaryRow({
    required this.visibleCount,
    required this.activeCount,
    required this.archivedCount,
  });

  final int visibleCount;
  final int activeCount;
  final int archivedCount;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Results',
          value: '$visibleCount',
          hint: 'Visible on this page',
          icon: Icons.grid_view_rounded,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Active',
          value: '$activeCount',
          hint: 'Ready to sell',
          icon: Icons.check_circle_outline_rounded,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Inactive',
          value: '$archivedCount',
          hint: 'Hidden from sales',
          icon: Icons.archive_outlined,
          tone: AppColors.textTertiary,
        ),
      ],
    );
  }
}

class _ArchivedProductsBanner extends StatelessWidget {
  const _ArchivedProductsBanner();

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
              'Inactive products are hidden from new sales. Past orders '
              'keep the product name, price, and options.',
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
            tooltip: 'Edit product',
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
        ? 'No products'
        : hasMore
        ? 'Showing $start–$end products'
        : 'Showing $start–$end products';

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

class _ProductListCard extends StatelessWidget {
  const _ProductListCard({
    required this.product,
    required this.currencySymbol,
    required this.onTap,
    required this.onEdit,
    required this.onToggleArchive,
    this.onDeletePermanently,
  });

  final ProductSummary product;
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
              SelloEntityThumb(
                imageUrl: product.imageUrl,
                width: 52,
                name: product.name,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _productCardSubtitle(product),
                      style: context.texts.bodySmall?.copyWith(
                        color: context.selloColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _ProductStatusBadge(active: product.isActive),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              SelloMetaPill(
                label: 'Sell',
                value: product.isMultiOptionProduct
                    ? '—'
                    : SelloFormatters.currency(
                        product.sellingPrice,
                        symbol: currencySymbol,
                      ),
              ),
              SelloMetaPill(
                label: 'Stock',
                value: product.isMultiOptionProduct
                    ? '${SelloFormatters.quantity(product.currentStockQuantity)}'
                          '${product.unitLabel?.trim().isNotEmpty == true ? ' ${product.unitLabel!.trim()}' : ''}'
                          ' · ${product.activeOptionCount} options'
                    : SelloFormatters.quantity(product.currentStockQuantity),
              ),
              SelloMetaPill(
                label: 'Reorder',
                value: SelloFormatters.quantity(product.reorderLevel ?? 0),
              ),
            ],
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
                  product.isActive
                      ? Icons.archive_outlined
                      : Icons.unarchive_outlined,
                ),
                label: Text(product.isActive ? 'Deactivate' : 'Reactivate'),
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

  String _productCardSubtitle(ProductSummary product) {
    final parts = <String>[
      product.sku,
      product.categoryName ?? 'Uncategorized',
    ];
    if (product.isMultiOptionProduct && product.activeOptionCount > 1) {
      parts.add('${product.activeOptionCount} options');
    }
    return parts.join(' · ');
  }
}

/// Compact stock cell with a business-data popover (active options only).
class _MultiOptionStockCell extends StatelessWidget {
  const _MultiOptionStockCell({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final unit = product.unitLabel?.trim().isNotEmpty == true
        ? product.unitLabel!.trim()
        : 'units';
    final total = SelloFormatters.quantity(product.currentStockQuantity);
    final options = product.activeVariants;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(
          AppColors.textPrimary.withValues(alpha: 0.12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: const BorderSide(color: AppColors.outlinePanel),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      builder: (context, controller, child) {
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$total $unit',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${product.activeOptionCount} options',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Stock by option',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                for (final option in options) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.optionDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${SelloFormatters.quantity(option.stockQuantity ?? 0)} $unit',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: AppColors.outlinePanel),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '$total $unit',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductStatusBadge extends StatelessWidget {
  const _ProductStatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return SelloStatusBadge(
      label: active ? 'Active' : 'Inactive',
      tone: active ? SelloStatusTone.success : SelloStatusTone.neutral,
    );
  }
}

class _EditorResult {
  const _EditorResult({required this.created});

  /// True when a new catalog row was inserted (not an edit).
  final bool created;
}

class ProductEditorDialog extends ConsumerStatefulWidget {
  const ProductEditorDialog({
    super.key,
    this.product,
    required this.categories,
    required this.repository,
    this.defaultReorderLevel = 10,
    this.defaultIsActive = true,
    this.skuLookup,
    this.optionNameLookup,
    this.photoPanelBuilder,
  });

  final ProductSummary? product;
  final List<ProductCategory> categories;
  final ProductRepository repository;
  final int defaultReorderLevel;
  final bool defaultIsActive;

  /// Finds live item codes starting with a prefix. Defaults to the repository
  /// lookup for the signed-in company.
  final Future<Set<String>> Function(String prefix)? skuLookup;

  /// Saved option names for the current company. Defaults to the repository.
  final Future<List<String>> Function()? optionNameLookup;

  /// Replaces the photo gallery (which needs live storage services) in tests.
  final WidgetBuilder? photoPanelBuilder;

  @override
  ConsumerState<ProductEditorDialog> createState() =>
      _ProductEditorDialogState();
}

class _ProductEditorDialogState extends ConsumerState<ProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _brand;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _stockQty;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _description;
  String? _selectedCategory;
  String? _selectedUnit;
  final _customCategory = TextEditingController();
  bool _isActive = true;
  List<MediaGalleryDraft> _gallery = [];
  bool _galleryLoading = false;
  bool _galleryProcessing = false;
  bool _submitted = false;
  bool _saving = false;
  String? _skuFieldError;
  String? _barcodeFieldError;
  late Map<String, String> _attributes;
  String? _preferredSupplierId;
  List<({String id, String name})> _suppliers = const [];
  bool _suppliersLoading = false;
  bool _showOptions = false;
  String? _optionsError;
  final List<ProductOptionEditorRow> _optionRows = [];
  int _tab = 0;
  final _variantsSectionKey = GlobalKey();
  bool _skuManuallyEdited = false;
  Timer? _parentCodeTimer;
  Timer? _variantCodeTimer;
  final Map<String, Set<String>> _skuCache = {};
  List<String> _optionNameSuggestions = const [];

  static const _unitOptions = <String>[
    'piece',
    'pack',
    'box',
    'carton',
    'bottle',
    'bag',
    'set',
    'pair',
    'dozen',
    'kg',
    'g',
    'litre',
    'ml',
    'metre',
    'roll',
  ];

  bool get _isCreate => widget.product == null;

  bool get _canViewCost {
    final role = ref.read(currentSessionProvider)?.appRole;
    return role?.canViewProductCost ?? true;
  }

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _sku = TextEditingController(text: product?.sku ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
    _brand = TextEditingController(text: product?.brand ?? '');
    _sellingPrice = TextEditingController(
      text: product == null ? '' : product.sellingPrice.toString(),
    );
    _costPrice = TextEditingController(
      text: product == null ? '' : product.costPrice.toString(),
    );
    _stockQty = TextEditingController(
      text: product == null ? '' : product.currentStockQuantity.toString(),
    );
    _reorderLevel = TextEditingController(
      text:
          product?.reorderLevel?.toString() ??
          widget.defaultReorderLevel.toString(),
    );
    _description = TextEditingController(text: product?.description ?? '');
    _attributes = Map<String, String>.from(product?.attributes ?? const {});
    _selectedCategory =
        widget.categories
            .map((category) => category.name)
            .contains(product?.categoryName)
        ? product?.categoryName
        : null;
    _customCategory.text = _selectedCategory == null
        ? (product?.categoryName ?? '')
        : '';
    final existingUnit = product?.unitLabel?.trim();
    _selectedUnit = (existingUnit != null && existingUnit.isNotEmpty)
        ? existingUnit
        : 'piece';
    _isActive = product?.isActive ?? widget.defaultIsActive;
    _skuManuallyEdited = product != null;
    _preferredSupplierId = product?.preferredSupplierId;
    _suppliersLoading = true;
    Future.microtask(_loadSuppliers);
    Future.microtask(_loadOptionNameSuggestions);
    if (product != null) {
      _galleryLoading = true;
      _loadGallery(product.id);
      if (product.variants.length > 1 || product.hasMultipleActiveVariants) {
        _showOptions = true;
        Future.microtask(_loadOptionRows);
      }
    }
  }

  Future<void> _loadOptionRows() async {
    final product = widget.product;
    if (product == null) return;
    try {
      final variants = await widget.repository.fetchVariantsForProduct(
        product.id,
      );
      if (!mounted) return;
      for (final row in _optionRows) {
        row.dispose();
      }
      _optionRows
        ..clear()
        ..addAll([
          for (final variant in variants)
            ProductOptionEditorRow.fromVariant(variant),
        ]);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      for (final row in _optionRows) {
        row.dispose();
      }
      _optionRows
        ..clear()
        ..addAll([
          for (final variant in product.variants)
            ProductOptionEditorRow.fromVariant(
              variant,
              unitCost: product.costPrice,
            ),
        ]);
      setState(() {});
    }
  }

  void _beginManagingOptions() {
    setState(() {
      _optionsError = null;
      if (!_showOptions || _optionRows.isEmpty) {
        for (final row in _optionRows) {
          row.dispose();
        }
        _optionRows
          ..clear()
          ..addAll(
            ProductOptionEditorRow.evolveFromSimple(
              existingVariantId: widget.product?.defaultVariantId,
              sku: _isCreate ? '' : _sku.text.trim(),
              barcode: _barcode.text.trim(),
              sellingPrice: _sellingPrice.text.trim(),
              costPrice: _costPrice.text.trim(),
              isActive: _isActive,
              openingStock: _isCreate ? _stockQty.text.trim() : '',
            ),
          );
        _showOptions = true;
      } else {
        _optionRows.add(
          ProductOptionEditorRow(
            sellingPrice: _optionRows.first.sellingPrice.text,
            costPrice: _optionRows.first.costPrice.text,
          ),
        );
      }
    });
  }

  Future<void> _setHasVariants(bool enabled) async {
    if (enabled == _showOptions) return;
    if (enabled) {
      _beginManagingOptions();
      _scheduleVariantCodeRefresh();
      return;
    }
    await _switchToSingleProduct();
    if (mounted && !_showOptions) setState(() => _tab = 0);
  }

  Future<Set<String>> _takenSkus(String prefix) async {
    final key = ItemCodeGenerator.normalize(prefix);
    if (key.isEmpty) return <String>{};
    final cached = _skuCache[key];
    if (cached != null) return cached;
    final companyId = ref.read(currentSessionProvider)?.company.id;
    if (companyId == null && widget.skuLookup == null) return <String>{};
    try {
      final lookup = widget.skuLookup;
      final found = lookup != null
          ? {for (final sku in await lookup(key)) sku.trim().toUpperCase()}
          : await widget.repository.fetchExistingSkusWithPrefix(
              companyId: companyId!,
              prefix: key,
            );
      _skuCache[key] = found;
      return found;
    } catch (_) {
      // The database still enforces uniqueness; a failed lookup only means
      // the first suggestion may need a manual tweak.
      return <String>{};
    }
  }

  void _onNameChanged(String _) {
    if (!_isCreate || _skuManuallyEdited) return;
    _parentCodeTimer?.cancel();
    _parentCodeTimer = Timer(
      const Duration(milliseconds: 350),
      _applyParentCode,
    );
  }

  void _onParentCodeEdited(String value) {
    _skuFieldError = null;
    _skuManuallyEdited = value.trim().isNotEmpty;
    if (!_skuManuallyEdited) {
      _onNameChanged(_name.text);
    }
    _scheduleVariantCodeRefresh();
  }

  Future<void> _applyParentCode({bool refreshVariants = true}) async {
    if (!_isCreate || _skuManuallyEdited) return;
    final base = ItemCodeGenerator.parentFromName(_name.text);
    if (base.isEmpty) {
      if (_sku.text.isNotEmpty && mounted) {
        setState(() => _sku.text = '');
      }
      return;
    }
    final taken = await _takenSkus(base);
    if (!mounted || _skuManuallyEdited) return;
    if (ItemCodeGenerator.parentFromName(_name.text) != base) return;
    final code = ItemCodeGenerator.makeUnique(base, taken);
    if (_sku.text != code || _skuFieldError != null) {
      setState(() {
        _sku.text = code;
        _skuFieldError = null;
      });
    }
    if (refreshVariants) _scheduleVariantCodeRefresh();
  }

  void _onOptionNameChanged(ProductOptionEditorRow row) {
    if (row.skuManuallyEdited) return;
    _applyVariantCode(row);
  }

  void _onOptionCodeEdited(ProductOptionEditorRow row) {
    if (!row.skuManuallyEdited) _applyVariantCode(row);
  }

  void _scheduleVariantCodeRefresh() {
    _variantCodeTimer?.cancel();
    _variantCodeTimer = Timer(
      const Duration(milliseconds: 350),
      _refreshVariantCodes,
    );
  }

  Future<void> _refreshVariantCodes() async {
    if (!_showOptions) return;
    final rows = _optionRows.where((r) => !r.skuManuallyEdited).toList();
    for (final row in rows) {
      row.sku.text = '';
    }
    for (final row in rows) {
      if (!mounted || !_optionRows.contains(row)) continue;
      await _applyVariantCode(row);
    }
  }

  Future<void> _applyVariantCode(ProductOptionEditorRow row) async {
    if (row.skuManuallyEdited) return;
    final parent = _sku.text.trim();
    final label = row.label.text;
    final base = ItemCodeGenerator.variantFromOption(
      parentCode: parent,
      optionLabel: label,
    );
    if (base.isEmpty) {
      if (row.sku.text.isNotEmpty && mounted) {
        setState(() => row.sku.text = '');
      }
      return;
    }
    final stored = await _takenSkus(parent);
    if (!mounted || row.skuManuallyEdited || !_optionRows.contains(row)) return;
    if (ItemCodeGenerator.variantFromOption(
          parentCode: _sku.text.trim(),
          optionLabel: row.label.text,
        ) !=
        base) {
      return;
    }
    final taken = {
      ...stored,
      for (final other in _optionRows)
        if (!identical(other, row) && other.sku.text.trim().isNotEmpty)
          other.sku.text.trim(),
    };
    final code = ItemCodeGenerator.makeUnique(base, taken, letterSuffix: true);
    if (row.sku.text != code) {
      setState(() => row.sku.text = code);
    }
  }

  Future<void> _flushAutoCodes() async {
    _parentCodeTimer?.cancel();
    _variantCodeTimer?.cancel();
    if (_isCreate && !_skuManuallyEdited) {
      await _applyParentCode(refreshVariants: false);
    }
    if (_showOptions) {
      for (final row in List.of(_optionRows)) {
        if (!row.skuManuallyEdited) await _applyVariantCode(row);
      }
    }
  }

  bool get _parentBasicsInvalid =>
      _name.text.trim().isEmpty || _sku.text.trim().isEmpty;

  bool get _variantsInvalid =>
      _showOptions && _optionRows.any(optionRowHasErrors);

  int get _readyVariantCount => readyVariantCount(_optionRows);

  bool get _needsMoreVariants => _showOptions && _readyVariantCount < 2;

  bool get _hasSavedMultiOptions {
    final product = widget.product;
    if (product == null) return false;
    return product.variants.length > 1 || product.hasMultipleActiveVariants;
  }

  Future<void> _switchToSingleProduct() async {
    if (_hasSavedMultiOptions) {
      setState(() {
        _optionsError =
            'This product already has saved options. Deactivate unused '
            'options instead of converting back to a single product.';
      });
      return;
    }

    final hasDetails = optionDraftsHaveDetails(_optionRows);
    if (hasDetails) {
      final confirmed = await showSelloDialog(
        context: context,
        title: 'Switch to single product?',
        message:
            'Your option details will be removed and the product will return '
            'to a single-product setup.',
        confirmLabel: 'Switch to single product',
        cancelLabel: 'Cancel',
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _optionsError = null;
      if (_optionRows.isNotEmpty) {
        final first = _optionRows.first;
        if (_sku.text.trim().isEmpty) _sku.text = first.sku.text;
        if (_barcode.text.trim().isEmpty) _barcode.text = first.barcode.text;
        if (_sellingPrice.text.trim().isEmpty) {
          _sellingPrice.text = first.sellingPrice.text;
        }
        if (_costPrice.text.trim().isEmpty) {
          _costPrice.text = first.costPrice.text;
        }
        if (_isCreate &&
            _stockQty.text.trim().isEmpty &&
            first.openingStock.text.trim().isNotEmpty) {
          _stockQty.text = first.openingStock.text;
        }
      }
      for (final row in _optionRows) {
        row.dispose();
      }
      _optionRows.clear();
      _showOptions = false;
    });
  }

  Future<void> _toggleOptionActive(int index, bool active) async {
    final error = optionDeactivateError(
      rows: _optionRows,
      index: index,
      nextActive: active,
    );
    if (error != null) {
      setState(() => _optionsError = error);
      return;
    }

    // Saved options deactivate with confirmation; reactivation is immediate.
    if (!active && !_optionRows[index].isNew) {
      final confirmed = await showSelloDialog(
        context: context,
        title: 'Deactivate this option?',
        message:
            'This option will no longer be available for new sales. Existing '
            'orders and inventory history will be preserved.',
        confirmLabel: 'Deactivate',
        cancelLabel: 'Cancel',
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _optionsError = null;
      _optionRows[index].isActive = active;
    });
  }

  Future<void> _removeOption(int index) async {
    if (!canRemoveDraftOption(rows: _optionRows, index: index)) {
      setState(() {
        _optionsError = 'Keep at least one option while managing options.';
      });
      return;
    }

    final row = _optionRows[index];
    if (draftOptionRemoveNeedsConfirmation(row)) {
      final confirmed = await showSelloDialog(
        context: context,
        title: 'Remove this option?',
        message: 'The information entered for this option will be discarded.',
        confirmLabel: 'Remove option',
        cancelLabel: 'Cancel',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
    }

    ProductOptionEditorRow? removed;
    setState(() {
      _optionsError = null;
      removed = removeDraftOptionAt(rows: _optionRows, index: index);
    });
    if (removed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => removed!.dispose());
    }
  }

  Future<void> _loadSuppliers() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      if (mounted) setState(() => _suppliersLoading = false);
      return;
    }
    try {
      final items = await ref
          .read(supplierRepositoryProvider)
          .fetchActiveSuppliers(companyId: session.company.id, limit: 100);
      if (!mounted) return;
      final options = [for (final s in items) (id: s.id, name: s.name)];
      // Keep current preferred visible even if archived.
      final currentId = _preferredSupplierId;
      final currentName = widget.product?.preferredSupplierName;
      if (currentId != null &&
          currentName != null &&
          !options.any((s) => s.id == currentId)) {
        options.insert(0, (id: currentId, name: '$currentName (inactive)'));
      }
      setState(() {
        _suppliers = options;
        _suppliersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _suppliersLoading = false);
    }
  }

  Future<void> _loadOptionNameSuggestions() async {
    final lookup = widget.optionNameLookup;
    final companyId = ref.read(currentSessionProvider)?.company.id;
    if (lookup == null && companyId == null) return;
    try {
      final names = lookup != null
          ? await lookup()
          : await widget.repository.fetchVariantOptionLabels(
              companyId: companyId!,
            );
      if (!mounted) return;
      setState(() => _optionNameSuggestions = names);
    } catch (_) {}
  }

  Future<void> _loadGallery(String productId) async {
    try {
      final images = await widget.repository.media.fetchForProduct(productId);
      if (!mounted) return;
      setState(() {
        _gallery = [
          for (final image in images) MediaGalleryDraft.fromProductImage(image),
        ];
        if (_gallery.isEmpty &&
            widget.product?.imageStoragePath != null &&
            widget.product!.imageStoragePath!.isNotEmpty) {
          _gallery = [
            MediaGalleryDraft(
              clientId: 'summary_primary',
              storagePath: widget.product!.imageStoragePath,
              networkUrl: widget.product!.imageUrl,
              isPrimary: true,
              sortOrder: 0,
            ),
          ];
        }
        _galleryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (widget.product?.imageUrl != null) {
          _gallery = [
            MediaGalleryDraft(
              clientId: 'summary_primary',
              storagePath: widget.product?.imageStoragePath,
              networkUrl: widget.product?.imageUrl,
              isPrimary: true,
              sortOrder: 0,
            ),
          ];
        }
        _galleryLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _parentCodeTimer?.cancel();
    _variantCodeTimer?.cancel();
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _brand.dispose();
    _sellingPrice.dispose();
    _costPrice.dispose();
    _stockQty.dispose();
    _reorderLevel.dispose();
    _description.dispose();
    _customCategory.dispose();
    for (final row in _optionRows) {
      row.dispose();
    }
    super.dispose();
  }

  String? _requiredMessage(CompanyProductField? field, String? value) {
    if (field == null || !field.enabled || !field.required) return null;
    if (!parentFieldRequirementApplies(
      fieldKey: field.fieldKey,
      hasVariants: _showOptions,
      definitionKey: field.definition.key,
    )) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return '${field.label} is required.';
    }
    return null;
  }

  Future<void> _submit(ProductFieldConfig fieldConfig) async {
    if (_saving || _galleryProcessing) return;
    await _flushAutoCodes();
    if (!mounted) return;
    setState(() {
      _submitted = true;
      _skuFieldError = null;
      _barcodeFieldError = null;
      _optionsError = null;
    });
    if (!_formKey.currentState!.validate()) {
      _revealTabWithErrors();
      return;
    }

    final selectedCategory = _selectedCategory == '__new__'
        ? _customCategory.text.trim()
        : (_selectedCategory ?? _customCategory.text.trim());
    if (selectedCategory.isEmpty) {
      setState(() => _tab = 0);
      SelloSnackbars.warning(context, 'Choose or create a category.');
      return;
    }

    for (final field in fieldConfig.enabled) {
      if (!parentFieldRequirementApplies(
        fieldKey: field.fieldKey,
        hasVariants: _showOptions,
        definitionKey: field.definition.key,
      )) {
        continue;
      }
      final value = switch (field.fieldKey) {
        'barcode' => _barcode.text,
        'brand' => _brand.text,
        'unit_label' => _selectedUnit,
        'description' => _description.text,
        'reorder_level' => _reorderLevel.text,
        _ => _attributes[field.fieldKey],
      };
      final message = _requiredMessage(field, value);
      if (message != null) {
        setState(() => _tab = 0);
        SelloSnackbars.warning(context, message);
        return;
      }
    }

    List<ProductVariantDraft>? variantDrafts;
    late final num sellingPrice;
    late final num costPrice;
    if (_showOptions) {
      final structureError =
          tooFewVariantsError(_optionRows) ??
          duplicateOptionCodeError(_optionRows);
      if (structureError != null) {
        setState(() {
          _optionsError = structureError;
          _tab = 1;
        });
        return;
      }
      final activeCount = _optionRows.where((row) => row.isActive).length;
      final lastActiveError = validateLastActiveOption(
        activeCountAfterChange: activeCount,
      );
      if (lastActiveError != null) {
        setState(() {
          _optionsError = lastActiveError;
          _tab = 1;
        });
        return;
      }
      variantDrafts = [
        for (var i = 0; i < _optionRows.length; i++)
          _optionRows[i].toDraft(sortOrder: i, includeCost: _canViewCost),
      ];
      final primary = _optionRows.firstWhere(
        (row) => row.isActive,
        orElse: () => _optionRows.first,
      );
      sellingPrice = num.tryParse(primary.sellingPrice.text.trim()) ?? 0;
      costPrice = num.tryParse(primary.costPrice.text.trim()) ?? 0;
    } else {
      sellingPrice = num.parse(_sellingPrice.text.trim());
      costPrice = num.parse(
        _costPrice.text.trim().isEmpty ? '0' : _costPrice.text.trim(),
      );
    }

    final input = ProductUpsertInput(
      productId: widget.product?.id,
      name: _name.text.trim(),
      sku: _sku.text.trim(),
      categoryName: selectedCategory,
      barcode: fieldConfig.isEnabled('barcode') && !_showOptions
          ? _barcode.text.trim()
          : (widget.product?.barcode ?? ''),
      brand: fieldConfig.isEnabled('brand')
          ? _brand.text.trim()
          : (widget.product?.brand ?? ''),
      unitLabel: fieldConfig.isEnabled('unit_label')
          ? (_selectedUnit ?? '').trim()
          : (widget.product?.unitLabel ?? 'piece'),
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      currentStockQuantity: _showOptions
          ? 0
          : num.parse(
              _stockQty.text.trim().isEmpty ? '0' : _stockQty.text.trim(),
            ),
      reorderLevel: fieldConfig.isEnabled('reorder_level')
          ? (num.tryParse(_reorderLevel.text.trim()) ?? 0)
          : (widget.product?.reorderLevel ?? widget.defaultReorderLevel),
      description: _description.text.trim(),
      isActive: _isActive,
      preferredSupplierId: _preferredSupplierId,
      attributes: {
        for (final entry in _attributes.entries)
          if (!(_showOptions && isVariantLevelFieldKey(entry.key)))
            entry.key: entry.value,
      },
      variants: variantDrafts,
    );

    setState(() => _saving = true);
    final error = await ref
        .read(hubProductsProvider.notifier)
        .saveProduct(input: input, gallery: _gallery);
    if (!mounted) return;

    if (error != null) {
      final lower = error.toLowerCase();
      setState(() {
        _saving = false;
        if (lower.contains('sku') ||
            lower.contains('item code') ||
            lower.contains('unique code') ||
            lower.contains('sellable option')) {
          _skuFieldError = error;
          if (_showOptions) _optionsError = error;
        }
        if (lower.contains('barcode')) {
          _barcodeFieldError = error;
          if (_showOptions) _optionsError = error;
        }
        if (lower.contains('active sellable option')) {
          _optionsError = error;
        }
      });
      _formKey.currentState?.validate();
      SelloSnackbars.error(context, error);
      return;
    }

    Navigator.of(context).pop(_EditorResult(created: _isCreate));
  }

  void _revealTabWithErrors() {
    if (!_showOptions) return;
    final target = _parentBasicsInvalid ? 0 : (_variantsInvalid ? 1 : _tab);
    if (target != _tab) setState(() => _tab = target);
  }

  void _guideToVariantsTab() {
    setState(() {
      _tab = 1;
      if (_optionRows.length < 2) {
        _optionRows.add(
          ProductOptionEditorRow(
            sellingPrice: _optionRows.isEmpty
                ? _sellingPrice.text.trim()
                : _optionRows.first.sellingPrice.text,
            costPrice: _optionRows.isEmpty
                ? _costPrice.text.trim()
                : _optionRows.first.costPrice.text,
          ),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _variantsSectionKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 180),
        alignment: 0.08,
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onPrimary(ProductFieldConfig fieldConfig) {
    if (_needsMoreVariants) {
      _guideToVariantsTab();
      return;
    }
    _submit(fieldConfig);
  }

  @override
  Widget build(BuildContext context) {
    final fieldConfigAsync = ref.watch(productFieldConfigProvider);
    final fieldConfig =
        fieldConfigAsync.valueOrNull ?? ProductFieldConfig(fields: []);
    // While config loads, keep default column fields visible (matches seed defaults).
    final configReady = fieldConfigAsync.hasValue;
    final showBarcode = !configReady || fieldConfig.isEnabled('barcode');
    final showBrand = !configReady || fieldConfig.isEnabled('brand');
    final showUnit = !configReady || fieldConfig.isEnabled('unit_label');
    final showReorder = !configReady || fieldConfig.isEnabled('reorder_level');

    final categoryItems = <DropdownMenuItem<String?>>[
      for (final category in widget.categories)
        DropdownMenuItem<String?>(
          value: category.name,
          child: Text(category.name),
        ),
      const DropdownMenuItem<String?>(
        value: '__new__',
        child: Text('Create new category'),
      ),
    ];

    final imagePanel = _galleryLoading
        ? Container(
            height: 320,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.brandAccent.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.outlineSubtle),
            ),
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.photoPanelBuilder?.call(context) ??
              SelloProductMediaGallery(
                items: _gallery,
                onChanged: (items) {
                  // Keep submit payload in sync without rebuilding the whole form
                  // (rebuilding freezes typing while images optimize on web).
                  _gallery = items;
                },
                onProcessingChanged: (busy) {
                  if (_galleryProcessing == busy) return;
                  setState(() => _galleryProcessing = busy);
                },
              );

    return SelloFormDialog(
      formKey: _formKey,
      autovalidateMode: _submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      title: _isCreate ? 'Add Product' : 'Edit Product',
      subtitle: _isCreate
          ? 'Create a new catalog product. This product becomes available for inventory, pricing and customer orders.'
          : 'Update this catalog product. Changes apply to inventory, pricing and customer orders.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductVariantsToggleCard(
            value: _showOptions,
            onChanged: _hasSavedMultiOptions ? null : _setHasVariants,
            lockedNote: _hasSavedMultiOptions
                ? 'This product already has saved variants. Deactivate unused '
                      'variants instead of turning variants off.'
                : null,
          ),
          const SizedBox(height: 20),
          if (_showOptions) ...[
            ProductEditorTabs(
              index: _tab,
              onChanged: (value) => setState(() => _tab = value),
              tabs: [
                ProductEditorTab(
                  label: 'Parent Details',
                  hasError:
                      _submitted &&
                      (_parentBasicsInvalid || _skuFieldError != null),
                ),
                ProductEditorTab(
                  label: 'Variants (${_optionRows.length})',
                  hasError:
                      _submitted && (_variantsInvalid || _optionsError != null),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Visibility(
            visible: !_showOptions || _tab == 0,
            maintainState: true,
            child: _buildParentDetails(
              imagePanel: imagePanel,
              categoryItems: categoryItems,
              showBarcode: showBarcode,
              showBrand: showBrand,
              showUnit: showUnit,
              showReorder: showReorder,
            ),
          ),
          if (_showOptions)
            Visibility(
              key: _variantsSectionKey,
              visible: _tab == 1,
              maintainState: true,
              child: ProductOptionsEditorSection(
                rows: _optionRows,
                showCost: _canViewCost,
                errorText: _optionsError,
                onChanged: () => setState(() {}),
                onAddOption: _beginManagingOptions,
                onToggleActive: _toggleOptionActive,
                onRemoveOption: _removeOption,
                onOptionNameChanged: _onOptionNameChanged,
                onItemCodeEdited: _onOptionCodeEdited,
                optionNameSuggestions: [
                  ..._optionNameSuggestions,
                  for (final row in _optionRows)
                    if (row.label.text.trim().isNotEmpty) row.label.text.trim(),
                ],
              ),
            ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: variantAwarePrimaryLabel(
          isCreate: _isCreate,
          hasVariants: _showOptions,
          readyCount: _readyVariantCount,
        ),
        primaryEnabled: !_galleryProcessing && !_saving,
        primaryLoading: _saving && !_needsMoreVariants,
        onPrimary: (_galleryProcessing || _saving)
            ? null
            : () => _onPrimary(fieldConfig),
      ),
    );
  }

  Widget _buildParentDetails({
    required Widget imagePanel,
    required List<DropdownMenuItem<String?>> categoryItems,
    required bool showBarcode,
    required bool showBrand,
    required bool showUnit,
    required bool showReorder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = ResponsiveLayout.canFitRow(
              width: constraints.maxWidth,
              itemCount: 2,
              minItemWidth: 280,
              gap: 28,
            );
            final imageWidth = constraints.maxWidth >= 760 ? 320.0 : 280.0;
            final details = _buildDetailsColumn(
              categoryItems: categoryItems,
              showBarcode: showBarcode,
              showBrand: showBrand,
              showUnit: showUnit,
              showReorder: showReorder,
            );
            if (!sideBySide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  imagePanel,
                  const SizedBox(height: 28),
                  details,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: imageWidth, child: imagePanel),
                SizedBox(width: constraints.maxWidth >= 760 ? 32 : 28),
                Expanded(child: details),
              ],
            );
          },
        ),
        SelloDialogSection(
          title: 'Additional Information',
          bottomSpacing: 8,
          children: [
            SelloTextField(
              controller: _description,
              label: 'Description',
              hint: 'Notes for staff or customers…',
              maxLines: 5,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsColumn({
    required List<DropdownMenuItem<String?>> categoryItems,
    required bool showBarcode,
    required bool showBrand,
    required bool showUnit,
    required bool showReorder,
  }) {
    final needsCustomCategory =
        _selectedCategory == '__new__' || widget.categories.isEmpty;
    final fieldConfig =
        ref.watch(productFieldConfigProvider).valueOrNull ??
        ProductFieldConfig(fields: []);
    final attributeFields = fieldConfig.enabled
        .where((f) => f.definition.storage == ProductFieldStorage.attribute)
        .toList(growable: false);
    final parentAttributeFields = [
      for (final field in attributeFields)
        if (!(_showOptions && isVariantLevelProductField(field))) field,
    ];
    final disabledParentFields = [
      for (final field in attributeFields)
        if (_showOptions &&
            isVariantLevelFieldKey(field.fieldKey) &&
            field.fieldKey == 'size')
          field,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelloDialogSection(
          title: 'Identity',
          children: [
            SelloTextField(
              controller: _name,
              label: 'Product name',
              required: true,
              onChanged: _onNameChanged,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a product name.'
                  : null,
            ),
            if (showBarcode && !_showOptions)
              SelloFormRow(
                left: SelloTextField(
                  controller: _sku,
                  label: 'Item code',
                  required: true,
                  onChanged: _onParentCodeEdited,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter an item code.';
                    }
                    return _skuFieldError;
                  },
                ),
                right: SelloTextField(
                  controller: _barcode,
                  label: 'Barcode',
                  required: fieldConfig.byKey('barcode')?.required == true,
                  validator: (value) {
                    final requiredError = _requiredMessage(
                      fieldConfig.byKey('barcode'),
                      value,
                    );
                    if (requiredError != null) return requiredError;
                    return _barcodeFieldError;
                  },
                ),
              )
            else
              SelloTextField(
                controller: _sku,
                label: _showOptions ? 'Parent item code' : 'Item code',
                required: true,
                onChanged: _onParentCodeEdited,
                helperText: _showOptions
                    ? 'Groups all variants. Each variant has its own code.'
                    : null,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter an item code.';
                  }
                  return _skuFieldError;
                },
              ),
          ],
        ),
        if (parentAttributeFields.isNotEmpty)
          SelloDialogSection(
            title: 'Product Details',
            children: [
              ProductDynamicFields(
                fields: parentAttributeFields,
                values: _attributes,
                includeColumnBacked: false,
                includeInventory: false,
                includeAttributes: true,
                onChanged: (next) => setState(() => _attributes = next),
              ),
            ],
          ),
        if (_showOptions)
          SelloDialogSection(
            title: 'Pricing & Size',
            children: [
              const HandledInVariantsNote(),
              if (disabledParentFields.isNotEmpty)
                ProductDynamicFields(
                  fields: disabledParentFields,
                  values: _attributes,
                  includeColumnBacked: false,
                  includeInventory: false,
                  includeAttributes: true,
                  disabledFieldKeys: const {'size'},
                  onChanged: (next) => setState(() => _attributes = next),
                ),
              if (disabledParentFields.isNotEmpty) const SizedBox(height: 12),
              if (_canViewCost)
                SelloFormRow(
                  left: SelloTextField(
                    controller: _costPrice,
                    label: 'Cost price',
                    enabled: false,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  right: SelloTextField(
                    controller: _sellingPrice,
                    label: 'Selling price',
                    enabled: false,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                )
              else
                SelloTextField(
                  controller: _sellingPrice,
                  label: 'Selling price',
                  enabled: false,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
            ],
          ),
        SelloDialogSection(
          title: 'Classification',
          children: [
            if (showBrand || showUnit)
              SelloFormWeightedRow(
                flexes: showBrand && showUnit
                    ? const [48, 26, 26]
                    : showBrand
                    ? const [60, 40]
                    : const [60, 40],
                children: [
                  SelloDropdown<String?>(
                    value: _selectedCategory,
                    label: 'Category',
                    hint: widget.categories.isEmpty
                        ? 'Create new category'
                        : 'Select category',
                    items: categoryItems,
                    onChanged: (value) =>
                        setState(() => _selectedCategory = value),
                  ),
                  if (showBrand)
                    SelloAutocompleteField(
                      value: _brand.text,
                      label: 'Brand',
                      required: fieldConfig.byKey('brand')?.required == true,
                      suggestions: ProductDetailSuggestions.forKey('brand'),
                      validator: (value) =>
                          _requiredMessage(fieldConfig.byKey('brand'), value),
                      onChanged: (value) => _brand.text = value,
                    ),
                  if (showUnit)
                    SelloDropdown<String?>(
                      value: _selectedUnit,
                      label: 'Unit',
                      required:
                          fieldConfig.byKey('unit_label')?.required == true,
                      hint: 'Select unit',
                      items: [
                        for (final unit in {
                          ..._unitOptions,
                          if (_selectedUnit != null &&
                              !_unitOptions.contains(_selectedUnit))
                            _selectedUnit!,
                        })
                          DropdownMenuItem<String?>(
                            value: unit,
                            child: Text(unit),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedUnit = value),
                    ),
                ],
              )
            else
              SelloDropdown<String?>(
                value: _selectedCategory,
                label: 'Category',
                hint: widget.categories.isEmpty
                    ? 'Create new category'
                    : 'Select category',
                items: categoryItems,
                onChanged: (value) => setState(() => _selectedCategory = value),
              ),
            if (needsCustomCategory)
              SelloTextField(
                controller: _customCategory,
                label: 'New category name',
                required: true,
                validator: (value) {
                  if (!needsCustomCategory) return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a category name.';
                  }
                  return null;
                },
              ),
          ],
        ),
        SelloDialogSection(
          title: 'Sourcing',
          children: [
            SelloDropdown<String?>(
              value: _preferredSupplierId,
              label: 'Preferred supplier',
              hint: _suppliersLoading
                  ? 'Loading suppliers…'
                  : 'Primary purchasing partner',
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final supplier in _suppliers)
                  DropdownMenuItem<String?>(
                    value: supplier.id,
                    child: Text(supplier.name),
                  ),
              ],
              onChanged: (value) {
                if (_suppliersLoading) return;
                setState(() => _preferredSupplierId = value);
              },
              enabled: !_suppliersLoading,
            ),
            const Text(
              'A product may have one preferred supplier today. Additional '
              'suppliers per product will be available with Purchase Orders.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        if (!_showOptions)
          SelloDialogSection(
            title: 'Pricing',
            children: [
              if (_canViewCost)
                SelloFormRow(
                  left: SelloTextField(
                    controller: _costPrice,
                    label: 'Cost price',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _validateNumber,
                  ),
                  right: SelloTextField(
                    controller: _sellingPrice,
                    label: 'Selling price',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _validateNumber,
                  ),
                )
              else
                SelloTextField(
                  controller: _sellingPrice,
                  label: 'Selling price',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validateNumber,
                ),
            ],
          ),
        if (!_showOptions || showReorder)
          SelloDialogSection(
            title: 'Inventory',
            children: [
              if (_showOptions)
                SelloTextField(
                  controller: _reorderLevel,
                  label: 'Reorder level',
                  required:
                      fieldConfig.byKey('reorder_level')?.required == true,
                  tooltip: 'Alert when stock falls to this amount.',
                  helperText: 'Opening stock is set on each variant.',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final required = _requiredMessage(
                      fieldConfig.byKey('reorder_level'),
                      value,
                    );
                    if (required != null) return required;
                    return _validateOptionalNumber(value);
                  },
                )
              else if (showReorder)
                SelloFormRow(
                  left: SelloTextField(
                    controller: _stockQty,
                    label: 'Opening stock',
                    enabled: _isCreate,
                    helperText: _isCreate
                        ? null
                        : 'Adjust stock from Inventory to keep the ledger accurate.',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _isCreate ? _validateNumber : null,
                  ),
                  right: SelloTextField(
                    controller: _reorderLevel,
                    label: 'Reorder level',
                    required:
                        fieldConfig.byKey('reorder_level')?.required == true,
                    tooltip: 'Alert when stock falls to this amount.',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final required = _requiredMessage(
                        fieldConfig.byKey('reorder_level'),
                        value,
                      );
                      if (required != null) return required;
                      return _validateOptionalNumber(value);
                    },
                  ),
                )
              else
                SelloTextField(
                  controller: _stockQty,
                  label: 'Opening stock',
                  enabled: _isCreate,
                  helperText: _isCreate
                      ? null
                      : 'Adjust stock from Inventory to keep the ledger accurate.',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _isCreate ? _validateNumber : null,
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
                  'Inactive products remain available in reports and history but cannot be sold.',
            ),
          ],
        ),
      ],
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
