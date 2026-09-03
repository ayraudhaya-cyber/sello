import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/orders/presentation/order_editor_dialog.dart';
import 'package:sello/services/orders/order_stock_policy.dart';
import 'package:sello/shared/models/order_upsert_input.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/features/orders/presentation/widgets/product_quantity_control.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Lightweight basket review. Returns `true` when the rep continues to checkout.
Future<bool?> showVisitBasketSheet({
  required BuildContext context,
  required GlobalKey<OrderEditorDialogState> orderKey,
  required String currencySymbol,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.bottomSheet),
      ),
    ),
    builder: (context) => _VisitBasketSheet(
      orderKey: orderKey,
      currencySymbol: currencySymbol,
    ),
  );
}

class _VisitBasketSheet extends StatefulWidget {
  const _VisitBasketSheet({
    required this.orderKey,
    required this.currencySymbol,
  });

  final GlobalKey<OrderEditorDialogState> orderKey;
  final String currencySymbol;

  @override
  State<_VisitBasketSheet> createState() => _VisitBasketSheetState();
}

class _VisitBasketSheetState extends State<_VisitBasketSheet> {
  OrderEditorDialogState? get _editor => widget.orderKey.currentState;

  void _refresh() {
    final lines = _editor?.lines ?? const <OrderLineDraft>[];
    if (lines.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    final lines = editor?.lines ?? const <OrderLineDraft>[];
    final total = editor?.runningTotal ?? 0;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlinePanel,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Basket',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    return _BasketLine(
                      line: line,
                      currencySymbol: widget.currencySymbol,
                      maxQuantity: editor?.maxQuantityForProduct(line.productId),
                      onStockLimitReached: () {
                        final max =
                            editor?.maxQuantityForProduct(line.productId);
                        if (max != null && context.mounted) {
                          SelloSnackbars.warning(
                            context,
                            OrderStockPolicy.onlyAvailableMessage(max),
                          );
                        }
                      },
                      onQuantity: (qty) {
                        editor?.setLineQuantity(line.productId, qty);
                        _refresh();
                      },
                      onRemove: () {
                        editor?.removeLine(line.productId);
                        _refresh();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    SelloFormatters.currency(
                      total,
                      symbol: widget.currencySymbol,
                    ),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelloButton(
                label: 'Continue',
                size: SelloButtonSize.large,
                expanded: true,
                onPressed: lines.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasketLine extends StatelessWidget {
  const _BasketLine({
    required this.line,
    required this.currencySymbol,
    required this.onQuantity,
    required this.onRemove,
    this.maxQuantity,
    this.onStockLimitReached,
  });

  final OrderLineDraft line;
  final String currencySymbol;
  final ValueChanged<num> onQuantity;
  final VoidCallback onRemove;
  final num? maxQuantity;
  final VoidCallback? onStockLimitReached;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  SelloFormatters.currency(
                    line.lineTotal,
                    symbol: currencySymbol,
                  ),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ProductQuantityControl(
            value: line.quantity,
            allowZero: true,
            showRemove: true,
            maxQuantity: maxQuantity,
            onIncreaseBlocked: onStockLimitReached,
            onChanged: (qty) {
              if (qty < 1) {
                onRemove();
              } else {
                onQuantity(qty);
              }
            },
            onRemove: onRemove,
            compact: true,
          ),
        ],
      ),
    );
  }
}
