import 'package:flutter/material.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_stock_chip.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

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
    final imageHeight = large ? 180.0 : 140.0;
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
            GestureDetector(
              onTap: onOpenPhotos,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.control - 1),
                ),
                child: SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return SelloEntityThumb(
                            name: product.name,
                            imageUrl: product.imageUrl,
                            width: constraints.maxWidth,
                            height: imageHeight,
                          );
                        },
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: OrderCatalogStockChip(
                          available: product.availableStockQuantity,
                          reorderLevel: reorderLevel ?? product.reorderLevel,
                          offlineHint: offlineStockHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
                  if (expanded) ...[
                    const SizedBox(height: 8),
                    for (final option in _options) ...[
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
                      const SizedBox(height: 6),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, bool selected) {
    const thumbWidth = 56.0;
    final thumbHeight = thumbWidth / MediaConstants.aspectRatio;
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
                children: [
                  GestureDetector(
                    onTap: onOpenPhotos,
                    child: SizedBox(
                      width: thumbWidth,
                      height: thumbHeight,
                      child: SelloEntityThumb(
                        name: product.name,
                        imageUrl: product.imageUrl,
                        width: thumbWidth,
                        height: thumbHeight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
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
                      ],
                    ),
                  ),
                  _ExpandControl(
                    expanded: expanded,
                    onTap: onToggleExpanded,
                    label: expanded ? 'Hide' : 'Options',
                    compact: true,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                for (final option in _options) ...[
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
                  const SizedBox(height: 6),
                ],
              ],
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
              color: context.brandAccent,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 12.5 : 13,
                color: context.brandAccent,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${SelloFormatters.currency(option.sellingPrice, symbol: currencySymbol)}'
                  '${option.sku.trim().isNotEmpty ? ' · ${option.sku}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                OrderCatalogStockChip(
                  available: option.availableStockQuantity,
                  reorderLevel: reorderLevel,
                  offlineHint: offlineStockHint,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (selected)
            ProductQuantityControl(
              value: quantity,
              allowZero: true,
              showRemove: true,
              maxQuantity: maxQuantity,
              onIncreaseBlocked: onStockLimitReached,
              onChanged: onQuantityChanged,
              compact: true,
            )
          else
            SelloButton(
              label: 'Add',
              size: SelloButtonSize.small,
              variant: SelloButtonVariant.outline,
              onPressed: _canAdd ? onAdd : onStockLimitReached,
            ),
        ],
      ),
    );
  }
}
