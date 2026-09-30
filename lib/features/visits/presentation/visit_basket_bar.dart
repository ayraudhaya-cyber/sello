import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Catalog footer: optional basket review + primary Continue.
class VisitCatalogFooter extends StatelessWidget {
  const VisitCatalogFooter({
    super.key,
    required this.itemQuantity,
    required this.total,
    required this.currencySymbol,
    required this.onReviewBasket,
    required this.onContinue,
  });

  final num itemQuantity;
  final num total;
  final String currencySymbol;
  final VoidCallback onReviewBasket;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final qty = itemQuantity.round();
    final itemsLabel = qty == 1 ? '1 item' : '$qty items';
    final canContinue = qty > 0;

    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: AppColors.textPrimary.withValues(alpha: 0.08),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outlinePanel)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: canContinue ? onReviewBasket : null,
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$itemsLabel · ${SelloFormatters.currency(total, symbol: currencySymbol)}',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelloButton(
                      label: 'Continue',
                      size: SelloButtonSize.large,
                      expanded: true,
                      onPressed: canContinue ? onContinue : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
