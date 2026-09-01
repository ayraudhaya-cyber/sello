import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/stock_movement_type.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/badges/sello_badge.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';
import 'package:sello/shared/widgets/feedback/sello_intelligence_banner.dart';
import 'package:sello/shared/widgets/media/sello_entity_thumb.dart';

/// Inventory item workspace — stock profile + movement timeline.
class InventoryDetailsDialog extends StatelessWidget {
  const InventoryDetailsDialog({
    super.key,
    required this.item,
    required this.movements,
    this.onAdjust,
    this.loadingMovements = false,
  });

  final InventoryItem item;
  final List<StockMovement> movements;
  final VoidCallback? onAdjust;
  final bool loadingMovements;

  static const double _gap = 32;

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    final dash = '—';

    return SelloFormDialog(
      header: _Hero(item: item),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 36,
        isMobile ? 16 : 20,
        isMobile ? 20 : 36,
        16,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SelloIntelligenceBanner(
            message:
                'Reorder suggestions, velocity alerts, and supplier hints '
                'will appear here.',
          ),
          const SizedBox(height: _gap),
          _Section(
            label: 'Stock',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Current stock',
                    value: SelloFormatters.quantity(item.quantity),
                  ),
                  right: _Field(
                    label: 'Available',
                    value: SelloFormatters.quantity(item.availableQuantity),
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Reserved',
                    value: SelloFormatters.quantity(item.reservedQuantity),
                    mutedEmpty: item.reservedQuantity <= 0,
                  ),
                  right: _Field(
                    label: 'Reorder level',
                    value: item.reorderLevel == null
                        ? dash
                        : SelloFormatters.quantity(item.reorderLevel!),
                    mutedEmpty: item.reorderLevel == null,
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Last movement',
                    value: item.lastMovementAt == null
                        ? dash
                        : SelloFormatters.dateTime(item.lastMovementAt),
                    mutedEmpty: item.lastMovementAt == null,
                  ),
                  right: _Field(
                    label: 'Last updated',
                    value: item.updatedAt == null
                        ? dash
                        : SelloFormatters.dateTime(item.updatedAt),
                    mutedEmpty: item.updatedAt == null,
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'SKU',
                    value: item.sku.isEmpty ? dash : item.sku,
                    mutedEmpty: item.sku.isEmpty,
                  ),
                  right: _Field(
                    label: 'Category',
                    value: item.categoryName ?? dash,
                    mutedEmpty: item.categoryName == null,
                  ),
                ),
                const SizedBox(height: 16),
                SelloFormRow(
                  left: _Field(
                    label: 'Preferred supplier',
                    value: item.preferredSupplierName ?? dash,
                    mutedEmpty: item.preferredSupplierName == null,
                  ),
                  right: _Field(
                    label: 'Unit',
                    value: item.unitLabel ?? dash,
                    mutedEmpty: item.unitLabel == null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          _Section(
            label: 'Movement history',
            child: loadingMovements
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : movements.isEmpty
                    ? Text(
                        'No movements yet. Completing sales and stock '
                        'adjustments will appear here.',
                        style: _Type.label.copyWith(color: AppColors.textFaint),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < movements.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            _MovementRow(movement: movements[i]),
                          ],
                        ],
                      ),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Close',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: () => Navigator.of(context).maybePop(),
        primaryLabel: 'Adjust stock',
        onPrimary: onAdjust,
        primaryEnabled: onAdjust != null,
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelloEntityThumb(
          name: item.name,
          imageUrl: item.imageUrl,
          width: 64,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: _Type.title),
              const SizedBox(height: 8),
              Text(
                [
                  if (item.sku.isNotEmpty) item.sku,
                  if (item.categoryName != null) item.categoryName!,
                ].join(' · '),
                style: _Type.subtitle,
              ),
              const SizedBox(height: 12),
              SelloStatusBadge(
                label: item.stockStatus.label,
                tone: switch (item.stockStatus) {
                  StockStatus.healthy => SelloStatusTone.success,
                  StockStatus.low => SelloStatusTone.warning,
                  StockStatus.out => SelloStatusTone.danger,
                  StockStatus.archived => SelloStatusTone.neutral,
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final positive = movement.quantityDelta > 0;
    final sign = positive ? '+' : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            '$sign${SelloFormatters.quantity(movement.quantityDelta)}',
            style: _Type.value.copyWith(
              color: positive ? AppColors.success : AppColors.error,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movement.displayTitle,
                style: _Type.value.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  SelloFormatters.dateTime(movement.createdAt),
                  if (movement.createdByName != null) movement.createdByName!,
                  if (movement.referenceLabel != null) movement.referenceLabel!,
                  'Bal ${SelloFormatters.quantity(movement.quantityAfter)}',
                ].join(' · '),
                style: _Type.label.copyWith(color: AppColors.textFaint),
              ),
              if (movement.notes != null) ...[
                const SizedBox(height: 4),
                Text(
                  movement.notes!,
                  style: _Type.label.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        const SizedBox(height: 14),
        Text(label.toUpperCase(), style: _Type.section),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.mutedEmpty = false,
  });

  final String label;
  final String value;
  final bool mutedEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _Type.label),
        const SizedBox(height: 6),
        Text(
          value,
          style: mutedEmpty
              ? _Type.value.copyWith(
                  color: AppColors.textFaint.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                )
              : _Type.value,
        ),
      ],
    );
  }
}

abstract final class _Type {
  static const title = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const section = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.08 * 11,
    height: 1.2,
    color: AppColors.textFaint,
  );

  static const label = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  static const value = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: AppColors.textPrimary,
  );
}
