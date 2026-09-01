import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/stock_movement_type.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class StockAdjustResult {
  const StockAdjustResult({required this.input});

  final StockAdjustInput input;
}

/// Manual stock adjustment — every change writes a ledger movement.
class StockAdjustDialog extends ConsumerStatefulWidget {
  const StockAdjustDialog({
    super.key,
    required this.item,
  });

  final InventoryItem item;

  @override
  ConsumerState<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends ConsumerState<StockAdjustDialog> {
  bool _increase = true;
  StockMovementType _reason = StockMovementType.purchase;
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = num.tryParse(_qty.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter a quantity greater than zero.');
      return;
    }

    final delta = _increase ? amount : -amount;
    Navigator.of(context).pop(
      StockAdjustResult(
        input: StockAdjustInput(
          branchId: widget.item.branchId,
          productId: widget.item.productId,
          quantityDelta: delta,
          movementType: _reason,
          reason: _reason.label,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isMobile = context.isMobile;

    return SelloFormDialog(
      title: 'Adjust stock',
      subtitle: '${item.name} · SKU ${item.sku}',
      maxWidth: 640,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 32,
        20,
        isMobile ? 20 : 32,
        8,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Current stock: ${SelloFormatters.quantity(item.quantity)}'
            '${item.unitLabel != null ? ' ${item.unitLabel}' : ''}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          SelloDialogSection(
            title: 'Direction',
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Increase'),
                    selected: _increase,
                    onSelected: (_) => setState(() {
                      _increase = true;
                      if (_reason == StockMovementType.damage) {
                        _reason = StockMovementType.purchase;
                      }
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Decrease'),
                    selected: !_increase,
                    onSelected: (_) => setState(() {
                      _increase = false;
                      if (_reason == StockMovementType.purchase ||
                          _reason == StockMovementType.returned) {
                        _reason = StockMovementType.damage;
                      }
                    }),
                  ),
                ],
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Quantity',
            children: [
              SelloTextField(
                controller: _qty,
                label: 'Quantity',
                required: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Reason',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in StockMovementType.adjustReasons)
                    ChoiceChip(
                      label: Text(reason.label),
                      selected: _reason == reason,
                      onSelected: (_) => setState(() => _reason = reason),
                    ),
                ],
              ),
            ],
          ),
          SelloDialogSection(
            title: 'Notes',
            bottomSpacing: 8,
            children: [
              SelloTextField(
                controller: _notes,
                label: 'Adjustment notes',
                hint: 'Context for this movement…',
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        primaryLabel: 'Save adjustment',
        onPrimary: _submit,
      ),
    );
  }
}
