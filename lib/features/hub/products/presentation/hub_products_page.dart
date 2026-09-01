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
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:sello/shared/utils/formatters.dart';
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
      builder: (context) => _ProductEditorDialog(
        product: product,
        categories: state.categories,
        repository: ref.read(productRepositoryProvider),
        defaultReorderLevel: settings.defaultReorderLevel,
        defaultIsActive: settings.defaultProductStatus.isActive,
      ),
    );

    if (result == null) return;

    final error = await ref.read(hubProductsProvider.notifier).saveProduct(
          input: result.input,
          gallery: result.gallery,
        );

    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(
        context,
        product == null ? 'Product created.' : 'Product updated.',
      );
    }
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
    final error = await ref.read(hubProductsProvider.notifier).setArchived(
          product,
          archived: archived,
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(
        context,
        archived
            ? 'Product archived.'
            : 'Product restored to the active catalog.',
      );
    }
  }

  Future<void> _deletePermanently(ProductSummary product) async {
    if (product.isActive) {
      SelloSnackbars.warning(
        context,
        'Archive the product before permanently deleting it.',
      );
      return;
    }

    final confirmed = await showSelloDialog(
      context: context,
      title: 'Delete permanently?',
      message:
          '"${product.name}" will be removed from your catalog forever. '
          'Product photos will be deleted. Historical orders and reports that '
          'reference this product are preserved, but this action cannot be undone.',
      confirmLabel: 'Delete permanently',
      cancelLabel: 'Keep archived',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error =
        await ref.read(hubProductsProvider.notifier).permanentlyDelete(product);
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
    final currencySymbol = session?.company.companyCode == 'UNITECH' ? '\$' : '\$';

    ref.listen<String?>(
      hubProductsProvider.select((s) => s.errorMessage),
      (previous, next) {
        if (next == null || next == previous) return;
        if (!next.startsWith('Product saved, but photos')) return;
        if (!context.mounted) return;
        SelloSnackbars.warning(context, next);
      },
    );

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
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubProductsProvider.notifier).refresh(),
            onAdd: state.isSaving ? null : () => _openEditor(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.statusFilter == ProductStatusFilter.archived) ...[
            const _ArchivedProductsBanner(),
            const SizedBox(height: AppSpacing.md),
          ],
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
                onAction: () => ref.read(hubProductsProvider.notifier).refresh(),
              ),
            )
          else if (state.isEmpty)
            SelloCard(
              child: SelloEmptyState(
                title: state.statusFilter == ProductStatusFilter.archived
                    ? 'No archived products'
                    : 'Start building your catalog',
                message: state.statusFilter == ProductStatusFilter.archived
                    ? 'Archived products will appear here. You can restore them '
                        'to sales or permanently delete them when you are sure.'
                    : 'Add your first sellable product with pricing, stock, and an image. '
                        'Orders, inventory, and reporting will build on this catalog.',
                icon: state.statusFilter == ProductStatusFilter.archived
                    ? Icons.inventory_2_outlined
                    : Icons.inventory_2_rounded,
                actionLabel: state.statusFilter == ProductStatusFilter.archived
                    ? null
                    : 'Add Product',
                onAction: state.statusFilter == ProductStatusFilter.archived
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                            SelloFormatters.currency(
                              product.sellingPrice,
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
                              product.costPrice,
                              symbol: currencySymbol,
                            ),
                            numeric: true,
                          ),
                        ),
                      ),
                      DataCell(
                        Align(
                          alignment: Alignment.centerRight,
                          child: SelloTableText(
                            SelloFormatters.quantity(
                              product.currentStockQuantity,
                            ),
                            numeric: true,
                          ),
                        ),
                      ),
                      DataCell(_ProductStatusBadge(active: product.isActive)),
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
    final fieldConfig =
        ref.watch(productFieldConfigProvider).valueOrNull;
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
    if (specs.isEmpty) return product.sku;
    return '${product.sku} · $specs';
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
    required this.onAdd,
  });

  final TextEditingController searchController;
  final HubProductsState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ProductStatusFilter?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback? onRefresh;
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
          DropdownMenuItem(
            value: ProductStatusFilter.all,
            child: Text('All'),
          ),
          DropdownMenuItem(
            value: ProductStatusFilter.active,
            child: Text('Active'),
          ),
          DropdownMenuItem(
            value: ProductStatusFilter.archived,
            child: Text('Archived'),
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
      onPressed: onRefresh,
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
      child: context.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpacing.sm),
                status,
                const SizedBox(height: AppSpacing.sm),
                category,
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: refresh),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: add),
                  ],
                ),
              ],
            )
          : context.isTablet
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: AppSpacing.sm),
                        status,
                        const SizedBox(width: AppSpacing.sm),
                        category,
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        refresh,
                        const SizedBox(width: AppSpacing.xs),
                        add,
                      ],
                    ),
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final searchWidth = (constraints.maxWidth * 0.48)
                        .clamp(280.0, constraints.maxWidth * 0.55);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(width: searchWidth, child: search),
                        const SizedBox(width: AppSpacing.sm),
                        status,
                        const SizedBox(width: AppSpacing.sm),
                        category,
                        const Spacer(),
                        refresh,
                        const SizedBox(width: AppSpacing.xs),
                        add,
                      ],
                    );
                  },
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
    final cards = [
      _SummaryMetricCard(
        label: 'Results',
        value: '$visibleCount',
        hint: 'Visible on this page',
        icon: Icons.grid_view_rounded,
        accent: context.brandAccent,
        soft: context.brandAccentContainer,
      ),
      _SummaryMetricCard(
        label: 'Active',
        value: '$activeCount',
        hint: 'Ready to sell',
        icon: Icons.check_circle_outline_rounded,
        accent: AppColors.success,
        soft: AppColors.successContainer,
      ),
      _SummaryMetricCard(
        label: 'Archived',
        value: '$archivedCount',
        hint: 'Hidden from sales',
        icon: Icons.archive_outlined,
        accent: AppColors.textTertiary,
        soft: AppColors.surfaceMuted,
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

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.soft,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color accent;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTypography.eyebrow,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  value,
                  style: AppTypography.numeric(
                    const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.03 * 28,
                      height: 1.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    color: AppColors.textFaint,
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
              'Archived products are hidden from sales but remain available '
              'for reports and history.',
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
            tooltip: isActive ? 'Archive' : 'Restore',
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
              ? (widget.danger
                  ? AppColors.errorContainer
                  : AppColors.veil)
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
  const _PageChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

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
                      '${product.sku} · ${product.categoryName ?? 'Uncategorized'}',
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
                value: SelloFormatters.currency(
                  product.sellingPrice,
                  symbol: currencySymbol,
                ),
              ),
              SelloMetaPill(
                label: 'Stock',
                value: SelloFormatters.quantity(product.currentStockQuantity),
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
                label: Text(product.isActive ? 'Archive' : 'Restore'),
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

class _ProductStatusBadge extends StatelessWidget {
  const _ProductStatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return SelloStatusBadge(
      label: active ? 'Active' : 'Archived',
      tone: active ? SelloStatusTone.success : SelloStatusTone.neutral,
    );
  }
}

class _EditorResult {
  const _EditorResult({
    required this.input,
    this.gallery = const [],
  });

  final ProductUpsertInput input;
  final List<MediaGalleryDraft> gallery;
}

class _ProductEditorDialog extends ConsumerStatefulWidget {
  const _ProductEditorDialog({
    this.product,
    required this.categories,
    required this.repository,
    this.defaultReorderLevel = 10,
    this.defaultIsActive = true,
  });

  final ProductSummary? product;
  final List<ProductCategory> categories;
  final ProductRepository repository;
  final int defaultReorderLevel;
  final bool defaultIsActive;

  @override
  ConsumerState<_ProductEditorDialog> createState() =>
      _ProductEditorDialogState();
}

class _ProductEditorDialogState extends ConsumerState<_ProductEditorDialog> {
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
  late Map<String, String> _attributes;
  String? _preferredSupplierId;
  List<({String id, String name})> _suppliers = const [];
  bool _suppliersLoading = false;

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
      text: product?.reorderLevel?.toString() ??
          widget.defaultReorderLevel.toString(),
    );
    _description = TextEditingController(text: product?.description ?? '');
    _attributes = Map<String, String>.from(product?.attributes ?? const {});
    _selectedCategory = widget.categories
            .map((category) => category.name)
            .contains(product?.categoryName)
        ? product?.categoryName
        : null;
    _customCategory.text =
        _selectedCategory == null ? (product?.categoryName ?? '') : '';
    final existingUnit = product?.unitLabel?.trim();
    _selectedUnit =
        (existingUnit != null && existingUnit.isNotEmpty) ? existingUnit : 'piece';
    _isActive = product?.isActive ?? widget.defaultIsActive;
    _preferredSupplierId = product?.preferredSupplierId;
    _suppliersLoading = true;
    Future.microtask(_loadSuppliers);
    if (product != null) {
      _galleryLoading = true;
      _loadGallery(product.id);
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
      final options = [
        for (final s in items) (id: s.id, name: s.name),
      ];
      // Keep current preferred visible even if archived.
      final currentId = _preferredSupplierId;
      final currentName = widget.product?.preferredSupplierName;
      if (currentId != null &&
          currentName != null &&
          !options.any((s) => s.id == currentId)) {
        options.insert(0, (id: currentId, name: '$currentName (archived)'));
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

  Future<void> _loadGallery(String productId) async {
    try {
      final images =
          await widget.repository.media.fetchForProduct(productId);
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
    super.dispose();
  }

  String? _requiredMessage(CompanyProductField? field, String? value) {
    if (field == null || !field.enabled || !field.required) return null;
    if (value == null || value.trim().isEmpty) {
      return '${field.label} is required.';
    }
    return null;
  }

  void _submit(ProductFieldConfig fieldConfig) {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;

    final selectedCategory = _selectedCategory == '__new__'
        ? _customCategory.text.trim()
        : (_selectedCategory ?? _customCategory.text.trim());
    if (selectedCategory.isEmpty) {
      SelloSnackbars.warning(context, 'Choose or create a category.');
      return;
    }

    for (final field in fieldConfig.enabled) {
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
        SelloSnackbars.warning(context, message);
        return;
      }
    }

    Navigator.of(context).pop(
      _EditorResult(
        input: ProductUpsertInput(
          productId: widget.product?.id,
          name: _name.text.trim(),
          sku: _sku.text.trim(),
          categoryName: selectedCategory,
          barcode: fieldConfig.isEnabled('barcode')
              ? _barcode.text.trim()
              : (widget.product?.barcode ?? ''),
          brand: fieldConfig.isEnabled('brand')
              ? _brand.text.trim()
              : (widget.product?.brand ?? ''),
          unitLabel: fieldConfig.isEnabled('unit_label')
              ? (_selectedUnit ?? '').trim()
              : (widget.product?.unitLabel ?? 'piece'),
          sellingPrice: num.parse(_sellingPrice.text.trim()),
          costPrice: num.parse(_costPrice.text.trim()),
          currentStockQuantity: num.parse(_stockQty.text.trim()),
          reorderLevel: fieldConfig.isEnabled('reorder_level')
              ? (num.tryParse(_reorderLevel.text.trim()) ?? 0)
              : (widget.product?.reorderLevel ?? widget.defaultReorderLevel),
          description: _description.text.trim(),
          isActive: _isActive,
          preferredSupplierId: _preferredSupplierId,
          attributes: Map<String, String>.from(_attributes),
        ),
        gallery: _gallery,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fieldConfigAsync = ref.watch(productFieldConfigProvider);
    final fieldConfig = fieldConfigAsync.valueOrNull ??
        ProductFieldConfig(fields: []);
    // While config loads, keep default column fields visible (matches seed defaults).
    final configReady = fieldConfigAsync.hasValue;
    final showBarcode = !configReady || fieldConfig.isEnabled('barcode');
    final showBrand = !configReady || fieldConfig.isEnabled('brand');
    final showUnit = !configReady || fieldConfig.isEnabled('unit_label');
    final showReorder =
        !configReady || fieldConfig.isEnabled('reorder_level');

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
        : SelloProductMediaGallery(
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
          ResponsiveBuilder(
            mobile: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                imagePanel,
                const SizedBox(height: 28),
                _buildDetailsColumn(
                  categoryItems: categoryItems,
                  showBarcode: showBarcode,
                  showBrand: showBrand,
                  showUnit: showUnit,
                  showReorder: showReorder,
                ),
              ],
            ),
            tablet: (_) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 300, child: imagePanel),
                const SizedBox(width: 28),
                Expanded(
                  child: _buildDetailsColumn(
                    categoryItems: categoryItems,
                    showBarcode: showBarcode,
                    showBrand: showBrand,
                    showUnit: showUnit,
                    showReorder: showReorder,
                  ),
                ),
              ],
            ),
            desktop: (_) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: imagePanel),
                const SizedBox(width: 32),
                Expanded(
                  child: _buildDetailsColumn(
                    categoryItems: categoryItems,
                    showBarcode: showBarcode,
                    showBrand: showBrand,
                    showUnit: showUnit,
                    showReorder: showReorder,
                  ),
                ),
              ],
            ),
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
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: _isCreate ? 'Create Product' : 'Save Changes',
        primaryEnabled: !_galleryProcessing,
        onPrimary: _galleryProcessing ? null : () => _submit(fieldConfig),
      ),
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
    final fieldConfig = ref.watch(productFieldConfigProvider).valueOrNull ??
        ProductFieldConfig(fields: []);
    final attributeFields = fieldConfig.enabled
        .where((f) => f.definition.storage == ProductFieldStorage.attribute)
        .toList(growable: false);

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
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a product name.'
                  : null,
            ),
            if (showBarcode)
              SelloFormRow(
                left: SelloTextField(
                  controller: _sku,
                  label: 'Item code',
                  required: true,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter an item code.'
                      : null,
                ),
                right: SelloTextField(
                  controller: _barcode,
                  label: 'Barcode',
                  required: fieldConfig.byKey('barcode')?.required == true,
                  validator: (value) =>
                      _requiredMessage(fieldConfig.byKey('barcode'), value),
                ),
              )
            else
              SelloTextField(
                controller: _sku,
                label: 'Item code',
                required: true,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an item code.'
                    : null,
              ),
          ],
        ),
        if (attributeFields.isNotEmpty)
          SelloDialogSection(
            title: 'Product Details',
            children: [
              ProductDynamicFields(
                fields: attributeFields,
                values: _attributes,
                includeColumnBacked: false,
                includeInventory: false,
                includeAttributes: true,
                onChanged: (next) => setState(() => _attributes = next),
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
                onChanged: (value) =>
                    setState(() => _selectedCategory = value),
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
        SelloDialogSection(
          title: 'Pricing',
          children: [
            SelloFormRow(
              left: SelloTextField(
                controller: _sellingPrice,
                label: 'Selling price',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validateNumber,
              ),
              right: SelloTextField(
                controller: _costPrice,
                label: 'Cost price',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validateNumber,
              ),
            ),
          ],
        ),
        SelloDialogSection(
          title: 'Inventory',
          children: [
            if (showReorder)
              SelloFormRow(
                left: SelloTextField(
                  controller: _stockQty,
                  label: 'Current stock',
                  enabled: _isCreate,
                  helperText: _isCreate
                      ? null
                      : 'Adjust stock from Inventory to keep the ledger accurate.',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _isCreate ? _validateNumber : null,
                ),
                right: SelloTextField(
                  controller: _reorderLevel,
                  label: 'Reorder level',
                  required:
                      fieldConfig.byKey('reorder_level')?.required == true,
                  tooltip: 'Alert when stock falls to this amount.',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                label: 'Current stock',
                enabled: _isCreate,
                helperText: _isCreate
                    ? null
                    : 'Adjust stock from Inventory to keep the ledger accurate.',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
