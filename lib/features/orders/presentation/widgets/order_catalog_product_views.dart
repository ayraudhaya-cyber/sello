import 'package:flutter/material.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_stock_chip.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Shared catalog card typography — two-line name slot height.
const double kOrderCatalogNameLineHeight = 1.25;
const double kOrderCatalogNameFontSize = 13.0;
const double kOrderCatalogNameAreaHeight =
    kOrderCatalogNameFontSize * kOrderCatalogNameLineHeight * 2;

/// Grid card for two-column and single-column catalog layouts.
class OrderCatalogGridCard extends StatelessWidget {
  const OrderCatalogGridCard({
    super.key,
    required this.product,
    required this.currencySymbol,
    required this.quantity,
    required this.onAdd,
    required this.onQuantityChanged,
    required this.onOpenPhotos,
    this.large = false,
    this.maxQuantity,
    this.onStockLimitReached,
    this.offlineStockHint = false,
    this.reorderLevel,
  });

  final ProductSummary product;
  final String currencySymbol;
  final num quantity;
  final VoidCallback onAdd;
  final ValueChanged<num> onQuantityChanged;
  final VoidCallback onOpenPhotos;
  final bool large;
  final num? maxQuantity;
  final VoidCallback? onStockLimitReached;
  final bool offlineStockHint;
  final num? reorderLevel;

  bool get _canAdd => maxQuantity == null || maxQuantity! > 0;

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;
    final imageHeight = large ? 220.0 : 168.0;
    final available = product.availableStockQuantity;

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
                          available: available,
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: kOrderCatalogNameAreaHeight,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: kOrderCatalogNameFontSize,
                          height: kOrderCatalogNameLineHeight,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SelloFormatters.currency(
                      product.sellingPrice,
                      symbol: currencySymbol,
                    ),
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: large ? 15 : 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: selected
                  ? ProductQuantityControl(
                      value: quantity,
                      allowZero: true,
                      showRemove: true,
                      maxQuantity: maxQuantity,
                      onIncreaseBlocked: onStockLimitReached,
                      onChanged: onQuantityChanged,
                      compact: !large,
                    )
                  : Align(
                      alignment: Alignment.centerRight,
                      child: _CatalogAddButton(
                        large: large,
                        enabled: _canAdd,
                        onPressed: _canAdd ? onAdd : onStockLimitReached,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact horizontal row for list layout mode.
class OrderCatalogListTile extends StatelessWidget {
  const OrderCatalogListTile({
    super.key,
    required this.product,
    required this.currencySymbol,
    required this.quantity,
    required this.onAdd,
    required this.onQuantityChanged,
    required this.onOpenPhotos,
    this.maxQuantity,
    this.onStockLimitReached,
    this.offlineStockHint = false,
    this.reorderLevel,
  });

  final ProductSummary product;
  final String currencySymbol;
  final num quantity;
  final VoidCallback onAdd;
  final ValueChanged<num> onQuantityChanged;
  final VoidCallback onOpenPhotos;
  final num? maxQuantity;
  final VoidCallback? onStockLimitReached;
  final bool offlineStockHint;
  final num? reorderLevel;

  bool get _canAdd => maxQuantity == null || maxQuantity! > 0;

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onOpenPhotos,
                child: SizedBox(
                  width: thumbWidth,
                  height: thumbHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SelloEntityThumb(
                        name: product.name,
                        imageUrl: product.imageUrl,
                        width: thumbWidth,
                        height: thumbHeight,
                      ),
                      Positioned(
                        left: 4,
                        top: 4,
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
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      SelloFormatters.currency(
                        product.sellingPrice,
                        symbol: currencySymbol,
                      ),
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
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
                _CatalogAddButton(
                  large: true,
                  enabled: _canAdd,
                  onPressed: _canAdd ? onAdd : onStockLimitReached,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogAddButton extends StatelessWidget {
  const _CatalogAddButton({
    required this.large,
    required this.enabled,
    required this.onPressed,
  });

  final bool large;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconSize = large ? 34.0 : 30.0;

    return Tooltip(
      message: 'Add to order',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: SizedBox(
            width: AppSpacing.touchTarget,
            height: AppSpacing.touchTarget,
            child: Center(
              child: Icon(
                Icons.add_circle_rounded,
                size: iconSize,
                color: enabled ? context.brandAccent : AppColors.textFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
