import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/product_variant.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Read-only sellable options — Hub details and Sales presentation.
class ProductOptionsReadonlyList extends StatelessWidget {
  const ProductOptionsReadonlyList({
    super.key,
    required this.options,
    required this.currencySymbol,
    required this.unitLabel,
  });

  final List<ProductVariant> options;
  final String currencySymbol;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Options',
          style: context.texts.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ProductOptionReadonlyRow(
            option: options[i],
            currencySymbol: currencySymbol,
            unitLabel: unitLabel,
          ),
        ],
      ],
    );
  }
}

class _ProductOptionReadonlyRow extends StatelessWidget {
  const _ProductOptionReadonlyRow({
    required this.option,
    required this.currencySymbol,
    required this.unitLabel,
  });

  final ProductVariant option;
  final String currencySymbol;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final stock = SelloFormatters.quantity(
      option.availableStockQuantity ?? option.stockQuantity ?? 0,
    );
    final price = SelloFormatters.currency(
      option.sellingPrice,
      symbol: currencySymbol,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.optionDisplayName,
                  style: context.texts.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.sku,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.selloColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              price,
              textAlign: TextAlign.right,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$stock $unitLabel',
              textAlign: TextAlign.right,
              style: context.texts.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
