import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Compact customer / shop details for field sales visits.
Future<void> showVisitCustomerDetailsSheet(
  BuildContext context, {
  required String shopName,
  CustomerSummary? customer,
  CustomerVisit? activeVisit,
  required String currencySymbol,
  required bool showOutstanding,
  VoidCallback? onDiscardOrder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: AppRadius.bottomSheetAll,
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shopName,
                    style: sheetContext.texts.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (customer == null)
              Text(
                'Walk-in — register the buyer when they decide to purchase.',
                style: sheetContext.texts.bodyMedium?.copyWith(
                  color: sheetContext.selloColors.textSecondary,
                  height: 1.4,
                ),
              )
            else ...[
              _DetailRow(
                label: 'Phone',
                value: customer.phone ?? '—',
              ),
              if (customer.lastPurchaseAt != null)
                _DetailRow(
                  label: 'Last order',
                  value: DateFormat('d MMM yyyy').format(
                    customer.lastPurchaseAt!.toLocal(),
                  ),
                ),
              if (showOutstanding)
                _DetailRow(
                  label: 'Outstanding',
                  value: SelloFormatters.currency(
                    customer.outstandingBalance,
                    symbol: currencySymbol,
                  ),
                ),
              if (customer.addressLine1 != null || customer.city != null)
                _DetailRow(
                  label: 'Address',
                  value: [
                    if (customer.addressLine1 != null) customer.addressLine1!,
                    if (customer.city != null) customer.city!,
                  ].join(', '),
                ),
              if (customer.creditAllowed)
                _DetailRow(
                  label: 'Credit limit',
                  value: SelloFormatters.currency(
                    customer.creditLimit,
                    symbol: currencySymbol,
                  ),
                ),
            ],
            if (activeVisit != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _DetailRow(
                label: 'Visit duration',
                value: activeVisit.durationLabel,
                hint:
                    'Elapsed time since this visit started (${DateFormat('d MMM, h:mm a').format(activeVisit.startedAt.toLocal())}).',
              ),
              if (activeVisit.pendingSync)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Visit start is saved on this device and will sync when online.',
                    style: sheetContext.texts.bodySmall?.copyWith(
                      color: AppColors.warning,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
            if (onDiscardOrder != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SelloButton(
                label: 'Discard order',
                variant: SelloButtonVariant.outline,
                expanded: true,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  onDiscardOrder();
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(
              color: AppColors.textFaint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: context.texts.bodySmall?.copyWith(
                color: context.selloColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
