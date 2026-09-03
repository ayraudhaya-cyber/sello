import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/utils/formatters.dart';

enum OrderCatalogStockChipState {
  normal,
  low,
  out,
  unknown,
}

OrderCatalogStockChipState orderCatalogStockChipState({
  required num? available,
  required num? reorderLevel,
}) {
  if (available == null) return OrderCatalogStockChipState.unknown;
  if (available <= 0) return OrderCatalogStockChipState.out;
  if (reorderLevel != null && available <= reorderLevel) {
    return OrderCatalogStockChipState.low;
  }
  return OrderCatalogStockChipState.normal;
}

/// Compact stock overlay for catalog product thumbnails.
class OrderCatalogStockChip extends StatelessWidget {
  const OrderCatalogStockChip({
    super.key,
    required this.available,
    this.reorderLevel,
    this.offlineHint = false,
  });

  final num? available;
  final num? reorderLevel;
  final bool offlineHint;

  @override
  Widget build(BuildContext context) {
    final state = orderCatalogStockChipState(
      available: available,
      reorderLevel: reorderLevel,
    );
    if (state == OrderCatalogStockChipState.unknown) {
      return const SizedBox.shrink();
    }

    final label = switch (state) {
      OrderCatalogStockChipState.out => 'Out of stock',
      OrderCatalogStockChipState.low ||
      OrderCatalogStockChipState.normal =>
        '${SelloFormatters.quantity(available!)} available',
      OrderCatalogStockChipState.unknown => '',
    };

    if (label.isEmpty) return const SizedBox.shrink();

    final (Color bg, Color fg) = switch (state) {
      OrderCatalogStockChipState.out => (
          AppColors.attentionSoft.withValues(alpha: 0.92),
          AppColors.attention,
        ),
      OrderCatalogStockChipState.low => (
          AppColors.warningContainer.withValues(alpha: 0.92),
          AppColors.warning,
        ),
      OrderCatalogStockChipState.normal => (
          AppColors.surface.withValues(alpha: 0.88),
          AppColors.textSecondary,
        ),
      OrderCatalogStockChipState.unknown => (
          AppColors.surface,
          AppColors.textSecondary,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: fg.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          offlineHint && state != OrderCatalogStockChipState.out
              ? '$label · last known'
              : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: fg,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
