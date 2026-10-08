import 'package:flutter/material.dart';
import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/orders/presentation/widgets/order_catalog_stock_chip.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Shared catalog card typography.
const double kOrderCatalogNameLineHeight = 1.25;
const double kOrderCatalogNameFontSize = 13.0;

/// Same 4:5 frame in grid, large card, and list so the product looks like
/// itself when the layout density changes.
class OrderCatalogMediaFrame extends StatelessWidget {
  const OrderCatalogMediaFrame({
    super.key,
    required this.name,
    this.imageUrl,
    this.cacheKey,
    this.onTap,
    this.badge,
    this.onRemove,
    this.width,
    this.fillHeight = false,
    this.topRadius = true,
  });

  final String name;
  final String? imageUrl;
  final String? cacheKey;
  final VoidCallback? onTap;
  final Widget? badge;

  /// Shown at the top-right of the image when the product is in the basket.
  final VoidCallback? onRemove;

  /// Fixed width for list thumbnails. Null fills the parent at 4:5.
  final double? width;

  /// When set with [width], the frame uses the parent's height so a list
  /// row can keep equal space above and below the image.
  final bool fillHeight;
  final bool topRadius;

  @override
  Widget build(BuildContext context) {
    if (width != null && fillHeight) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : width! / MediaConstants.aspectRatio;
          return _frame(width!, height);
        },
      );
    }

    if (width != null) {
      final height = width! / MediaConstants.aspectRatio;
      return _frame(width!, height);
    }

    return AspectRatio(
      aspectRatio: MediaConstants.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _frame(constraints.maxWidth, constraints.maxHeight);
        },
      ),
    );
  }

  Widget _frame(double w, double h) {
    final radius = topRadius
        ? const BorderRadius.vertical(
            top: Radius.circular(AppRadius.control - 1),
          )
        : BorderRadius.circular(12);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: onTap,
              child: SelloEntityThumb(
                name: name,
                imageUrl: imageUrl,
                cacheKey: cacheKey,
                width: w,
                height: h,
              ),
            ),
            if (badge != null) Positioned(left: 6, top: 6, child: badge!),
            if (onRemove != null)
              Positioned(
                right: 6,
                top: 6,
                child: OrderCatalogRemoveButton(onPressed: onRemove!),
              ),
          ],
        ),
      ),
    );
  }
}

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
            OrderCatalogMediaFrame(
              name: product.name,
              imageUrl: product.imageUrl,
              cacheKey: product.imageCacheKey,
              onTap: onOpenPhotos,
              badge: OrderCatalogStockChip(
                available: available,
                reorderLevel: reorderLevel ?? product.reorderLevel,
                offlineHint: offlineStockHint,
              ),
              onRemove: selected ? () => onQuantityChanged(0) : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
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
                      fontSize: kOrderCatalogNameFontSize,
                      height: kOrderCatalogNameLineHeight,
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: OrderCatalogActionSlot(
                selected: selected,
                quantity: quantity,
                maxQuantity: maxQuantity,
                canAdd: _canAdd,
                large: large,
                onAdd: _canAdd ? onAdd : onStockLimitReached,
                onQuantityChanged: onQuantityChanged,
                onStockLimitReached: onStockLimitReached,
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
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 88,
                child: OrderCatalogMediaFrame(
                  name: product.name,
                  imageUrl: product.imageUrl,
                  cacheKey: product.imageCacheKey,
                  width: 88,
                  fillHeight: true,
                  topRadius: false,
                  onTap: onOpenPhotos,
                  badge: OrderCatalogStockChip(
                    available: product.availableStockQuantity,
                    reorderLevel: reorderLevel ?? product.reorderLevel,
                    offlineHint: offlineStockHint,
                  ),
                  onRemove: selected ? () => onQuantityChanged(0) : null,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    if (product.brand != null &&
                        product.brand!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        product.brand!.trim(),
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          height: 1.3,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      SelloFormatters.currency(
                        product.sellingPrice,
                        symbol: currencySymbol,
                      ),
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OrderCatalogActionSlot(
                        selected: selected,
                        quantity: quantity,
                        maxQuantity: maxQuantity,
                        canAdd: _canAdd,
                        onAdd: _canAdd ? onAdd : onStockLimitReached,
                        onQuantityChanged: onQuantityChanged,
                        onStockLimitReached: onStockLimitReached,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right-aligned add or quantity group so the action stays in one place.
class OrderCatalogActionSlot extends StatelessWidget {
  const OrderCatalogActionSlot({
    super.key,
    required this.selected,
    required this.quantity,
    required this.canAdd,
    required this.onAdd,
    required this.onQuantityChanged,
    this.maxQuantity,
    this.onStockLimitReached,
    this.large = false,
  });

  final bool selected;
  final num quantity;
  final bool canAdd;
  final VoidCallback? onAdd;
  final ValueChanged<num> onQuantityChanged;
  final num? maxQuantity;
  final VoidCallback? onStockLimitReached;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: selected
          ? ProductQuantityControl(
              value: quantity,
              allowZero: true,
              maxQuantity: maxQuantity,
              onIncreaseBlocked: onStockLimitReached,
              onChanged: onQuantityChanged,
            )
          : OrderCatalogAddButton(
              large: large,
              enabled: canAdd,
              onPressed: onAdd,
            ),
    );
  }
}

/// Compact image overlay that removes the product without changing card height.
class OrderCatalogRemoveButton extends StatelessWidget {
  const OrderCatalogRemoveButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Remove from order',
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: AppColors.attention,
            ),
          ),
        ),
      ),
    );
  }
}

class OrderCatalogAddButton extends StatelessWidget {
  const OrderCatalogAddButton({
    super.key,
    required this.enabled,
    required this.onPressed,
    this.large = false,
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
            width: ProductQuantityControl.buttonSize,
            height: ProductQuantityControl.buttonSize,
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
