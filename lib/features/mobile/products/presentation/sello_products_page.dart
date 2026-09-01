import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/products/application/sello_catalog_provider.dart';
import 'package:sello/features/mobile/products/presentation/sello_product_present_sheet.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Sales-rep catalog — browse and present product photos to buyers.
class SelloProductsPage extends ConsumerStatefulWidget {
  const SelloProductsPage({super.key});

  @override
  ConsumerState<SelloProductsPage> createState() => _SelloProductsPageState();
}

class _SelloProductsPageState extends ConsumerState<SelloProductsPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _appliedQuery;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final q = GoRouterState.of(context).uri.queryParameters['q'];
    if (q == null || q.isEmpty || q == _appliedQuery) return;
    _appliedQuery = q;
    _searchController.text = q;
    Future.microtask(() {
      if (mounted) {
        ref.read(selloCatalogProvider.notifier).setSearch(q);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openPresent(ProductSummary product) {
    return showSelloProductPresentSheet(
      context,
      product: product,
      repository: ref.read(productRepositoryProvider),
    );
  }

  Future<void> _openPhotos(ProductSummary product) {
    return openSelloProductPhotoViewer(
      context,
      product: product,
      repository: ref.read(productRepositoryProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(selloCatalogProvider);

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    final cols = context.responsiveValue(mobile: 2, tablet: 3, desktop: 4);

    return AppPageScaffold(
      title: 'Products',
      showBreadcrumbs: false,
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.sm,
      actions: [
        SelloButton(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          size: SelloButtonSize.small,
          variant: SelloButtonVariant.outline,
          onPressed: state.isLoading
              ? null
              : () => ref.read(selloCatalogProvider.notifier).refresh(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloTextField(
            controller: _searchController,
            hint: 'Search products, SKU, or brand',
            prefixIcon: Icons.search_rounded,
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(selloCatalogProvider.notifier).setSearch(value),
              );
            },
          ),
          if (state.categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: state.categoryId == null,
                    onTap: () => ref
                        .read(selloCatalogProvider.notifier)
                        .setCategoryFilter(null),
                  ),
                  for (final category in state.categories) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: category.name,
                      selected: state.categoryId == category.id,
                      onTap: () => ref
                          .read(selloCatalogProvider.notifier)
                          .setCategoryFilter(category.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (state.isLoading && state.items.isEmpty)
            const SelloListSkeleton()
          else if (state.errorMessage != null && state.items.isEmpty)
            SizedBox(
              height: 280,
              child: SelloStateView.error(
                title: 'Unable to load catalog',
                message: state.errorMessage,
                actionLabel: 'Try again',
                onAction: () =>
                    ref.read(selloCatalogProvider.notifier).refresh(),
              ),
            )
          else if (state.isEmpty)
            const SelloCard(
              child: SelloEmptyState(
                title: 'No products to present',
                message:
                    'When your manager adds active products with photos, they will appear here for buyer meetings.',
                icon: Icons.inventory_2_outlined,
              ),
            )
          else
            SelloFadeIn(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gap = AppSpacing.sm;
                  final width =
                      (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final product in state.items)
                        SizedBox(
                          width: width,
                          child: _CatalogProductCard(
                            product: product,
                            onOpenPresent: () => _openPresent(product),
                            onOpenPhotos: product.imageUrl == null
                                ? null
                                : () => _openPhotos(product),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.brandAccent : AppColors.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? context.brandAccent : AppColors.outlinePanel,
            ),
          ),
          child: Text(
            label,
            style: context.texts.labelLarge?.copyWith(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogProductCard extends ConsumerWidget {
  const _CatalogProductCard({
    required this.product,
    required this.onOpenPresent,
    required this.onOpenPhotos,
  });

  final ProductSummary product;
  final VoidCallback onOpenPresent;
  final VoidCallback? onOpenPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(productFieldConfigProvider).valueOrNull;
    final specLine = config == null
        ? product.sku
        : () {
            final parts = <String>[product.sku];
            for (final field in config.forCatalog) {
              if (field.fieldKey == 'description' ||
                  field.fieldKey == 'reorder_level') {
                continue;
              }
              final raw = switch (field.fieldKey) {
                'barcode' => product.barcode,
                'brand' => product.brand,
                'unit_label' => product.unitLabel,
                _ => product.displayAttribute(field.fieldKey),
              };
              if (raw == null || raw.trim().isEmpty) continue;
              parts.add(raw.trim());
              if (parts.length >= 3) break;
            }
            return parts.join(' · ');
          }();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: MediaConstants.aspectRatio,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpenPhotos ?? onOpenPresent,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (product.imageUrl != null &&
                        product.imageUrl!.isNotEmpty)
                      Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, _, _) =>
                            _Monogram(name: product.name),
                      )
                    else
                      _Monogram(name: product.name),
                    if (onOpenPhotos != null)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onOpenPresent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SelloFormatters.currency(product.sellingPrice),
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.brandAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    specLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.selloColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.primarySoft),
      child: Center(
        child: Text(
          initial,
          style: context.texts.headlineMedium?.copyWith(
            color: context.brandAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
