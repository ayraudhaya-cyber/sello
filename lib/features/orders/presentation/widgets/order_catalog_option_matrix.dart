import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_product_views.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_stock_chip.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Compact multi-option catalog card — parent identity + expandable option rows.
class OrderCatalogMultiOptionCard extends StatelessWidget {
  const OrderCatalogMultiOptionCard({
    super.key,
    required this.product,
    required this.currencySymbol,
    required this.expanded,
    required this.onToggleExpanded,
    required this.quantityForVariant,
    required this.maxQuantityForVariant,
    required this.onAddVariant,
    required this.onVariantQuantityChanged,
    required this.onOpenPhotos,
    this.onStockLimitReached,
    this.offlineStockHint = false,
    this.reorderLevel,
    this.large = false,
    this.listLayout = false,
  });

  final ProductSummary product;
  final String currencySymbol;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final num Function(ProductVariant variant) quantityForVariant;
  final num? Function(ProductVariant variant) maxQuantityForVariant;
  final void Function(ProductVariant variant) onAddVariant;
  final void Function(ProductVariant variant, num quantity)
      onVariantQuantityChanged;
  final VoidCallback onOpenPhotos;
  final void Function(ProductVariant variant)? onStockLimitReached;
  final bool offlineStockHint;
  final num? reorderLevel;
  final bool large;
  final bool listLayout;

  List<ProductVariant> get _options => product.activeVariants;

  num get _totalQty =>
      _options.fold<num>(0, (sum, v) => sum + quantityForVariant(v));

  @override
  Widget build(BuildContext context) {
    final selected = _totalQty > 0;
    if (listLayout) return _buildList(context, selected);
    return _buildGrid(context, selected);
  }

  Widget _buildGrid(BuildContext context, bool selected) {
    return Material(
      color: selected
          ? AppColors.surfaceSelected.withValues(alpha: 0.55)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected
                ? context.brandAccent.withValues(alpha: 0.28)
                : AppColors.outlineSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OrderCatalogMediaFrame(
              name: product.name,
              imageUrl: product.imageUrl,
              onTap: onOpenPhotos,
              badge: OrderCatalogStockChip(
                available: product.availableStockQuantity,
                reorderLevel: reorderLevel ?? product.reorderLevel,
                offlineHint: offlineStockHint,
              ),
              onRemove: selected
                  ? () {
                      for (final option in _options) {
                        if (quantityForVariant(option) > 0) {
                          onVariantQuantityChanged(option, 0);
                        }
                      }
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: large ? 16 : 13,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selected
                        ? '${_options.length} options · ${SelloFormatters.quantity(_totalQty)} units'
                        : '${_options.length} options',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ExpandControl(
                    expanded: expanded,
                    onTap: onToggleExpanded,
                    label: expanded ? 'Hide options' : 'Choose options',
                  ),
                ],
              ),
            ),
            if (expanded)
              for (final option in _options)
                _OptionRow(
                  option: option,
                  currencySymbol: currencySymbol,
                  quantity: quantityForVariant(option),
                  maxQuantity: maxQuantityForVariant(option),
                  reorderLevel: reorderLevel ?? product.reorderLevel,
                  offlineStockHint: offlineStockHint,
                  onAdd: () => onAddVariant(option),
                  onQuantityChanged: (qty) =>
                      onVariantQuantityChanged(option, qty),
                  onStockLimitReached: () =>
                      onStockLimitReached?.call(option),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, bool selected) {
    return Material(
      color: selected
          ? AppColors.surfaceSelected.withValues(alpha: 0.45)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected
                ? context.brandAccent.withValues(alpha: 0.22)
                : AppColors.outlineSubtle,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: OrderCatalogMediaFrame(
                      name: product.name,
                      imageUrl: product.imageUrl,
                      width: 88,
                      fillHeight: true,
                      topRadius: false,
                      onTap: onOpenPhotos,
                    badge: OrderCatalogStockChip(
                      available: product.availableStockQuantity,
                      reorderLevel: reorderLevel ?? product.reorderLevel,
                      offlineHint: offlineStockHint,
                    ),
                    onRemove: selected
                        ? () {
                            for (final option in _options) {
                              if (quantityForVariant(option) > 0) {
                                onVariantQuantityChanged(option, 0);
                              }
                            }
                          }
                        : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                          ),
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selected
                              ? '${_options.length} options · ${SelloFormatters.quantity(_totalQty)} units'
                              : '${_options.length} options',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12,
                            height: 1.3,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _ExpandControl(
                  expanded: expanded,
                  onTap: onToggleExpanded,
                  label: expanded ? 'Hide options' : 'Choose options',
                  compact: true,
                ),
              ),
              if (expanded)
                for (final option in _options)
                  _OptionRow(
                    option: option,
                    currencySymbol: currencySymbol,
                    quantity: quantityForVariant(option),
                    maxQuantity: maxQuantityForVariant(option),
                    reorderLevel: reorderLevel ?? product.reorderLevel,
                    offlineStockHint: offlineStockHint,
                    onAdd: () => onAddVariant(option),
                    onQuantityChanged: (qty) =>
                        onVariantQuantityChanged(option, qty),
                    onStockLimitReached: () =>
                        onStockLimitReached?.call(option),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandControl extends StatelessWidget {
  const _ExpandControl({
    required this.expanded,
    required this.onTap,
    required this.label,
    this.compact = false,
  });

  final bool expanded;
  final VoidCallback onTap;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? 4 : 6,
          horizontal: compact ? 4 : 0,
        ),
        child: Row(
          children: [
            Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
              color: context.brandAccent,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12.5 : 13,
                  color: context.brandAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.currencySymbol,
    required this.quantity,
    required this.onAdd,
    required this.onQuantityChanged,
    this.maxQuantity,
    this.onStockLimitReached,
    this.reorderLevel,
    this.offlineStockHint = false,
  });

  final ProductVariant option;
  final String currencySymbol;
  final num quantity;
  final VoidCallback onAdd;
  final ValueChanged<num> onQuantityChanged;
  final num? maxQuantity;
  final VoidCallback? onStockLimitReached;
  final num? reorderLevel;
  final bool offlineStockHint;

  bool get _canAdd => maxQuantity == null || maxQuantity! > 0;

  String get _label {
    final label = option.label?.trim();
    if (label != null && label.isNotEmpty) return label;
    return option.sku;
  }

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;
    final sku = option.sku.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: OrderCatalogStockChip(
                  available: option.availableStockQuantity,
                  reorderLevel: reorderLevel,
                  offlineHint: offlineStockHint,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _label,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sku.isEmpty
                    ? SelloFormatters.currency(
                        option.sellingPrice,
                        symbol: currencySymbol,
                      )
                    : '${SelloFormatters.currency(option.sellingPrice, symbol: currencySymbol)} · $sku',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              OrderCatalogActionSlot(
                selected: selected,
                quantity: quantity,
                maxQuantity: maxQuantity,
                canAdd: _canAdd,
                onAdd: _canAdd ? onAdd : onStockLimitReached,
                onQuantityChanged: onQuantityChanged,
                onStockLimitReached: onStockLimitReached,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
