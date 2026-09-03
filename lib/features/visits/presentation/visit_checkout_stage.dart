import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/visits/presentation/signature_pad.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Step 2 — settle and confirm. Line detail lives in the optional basket sheet.
class VisitCheckoutStage extends StatelessWidget {
  const VisitCheckoutStage({
    super.key,
    required this.shopName,
    required this.itemQuantity,
    required this.total,
    required this.currencySymbol,
    required this.arrangement,
    required this.onArrangementChanged,
    required this.onPickChequeDate,
    required this.onViewDetails,
    required this.notes,
    required this.signatureKey,
    required this.signed,
    required this.onSignedChanged,
    required this.saving,
    required this.onConfirm,
    this.chequeDate,
  });

  final String shopName;
  final num itemQuantity;
  final num total;
  final String currencySymbol;
  final VisitPaymentArrangement arrangement;
  final ValueChanged<VisitPaymentArrangement> onArrangementChanged;
  final VoidCallback onPickChequeDate;
  final VoidCallback onViewDetails;
  final DateTime? chequeDate;
  final TextEditingController notes;
  final GlobalKey<SelloSignaturePadState> signatureKey;
  final bool signed;
  final ValueChanged<bool> onSignedChanged;
  final bool saving;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final qty = itemQuantity.round();
    final itemsLabel = qty == 1 ? '1 item' : '$qty items';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              4,
              AppSpacing.md,
              16 + keyboard,
            ),
            children: [
              Text(
                shopName,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: onViewDetails,
                borderRadius: BorderRadius.circular(AppRadius.button),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$itemsLabel · ${SelloFormatters.currency(total, symbol: currencySymbol)}',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        'View order details',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: context.brandAccent,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: context.brandAccent,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const _SectionLabel('Collection'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in VisitPaymentArrangement.values)
                    _ArrangementChoice(
                      label: option.label,
                      selected: arrangement == option,
                      onTap: () => onArrangementChanged(option),
                    ),
                ],
              ),
              if (arrangement.schedulesFollowUp) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelloButton(
                    label: chequeDate == null
                        ? 'Collection date'
                        : DateFormat('d MMM').format(chequeDate!),
                    variant: SelloButtonVariant.outline,
                    onPressed: onPickChequeDate,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SelloTextField(
                controller: notes,
                hint: 'Note',
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: _SectionLabel('Signature')),
                  if (signed)
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.success,
                    ),
                  TextButton(
                    onPressed: () {
                      signatureKey.currentState?.clear();
                      onSignedChanged(false);
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              SizedBox(
                height: 140,
                child: SelloSignaturePad(
                  key: signatureKey,
                  onSigned: () => onSignedChanged(true),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SelloButton(
            label: saving ? 'Saving…' : 'Submit order',
            size: SelloButtonSize.large,
            expanded: true,
            loading: saving,
            onPressed: saving ? null : onConfirm,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _ArrangementChoice extends StatelessWidget {
  const _ArrangementChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.brandAccentContainer.withValues(alpha: 0.7)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 14,
                color: selected ? context.brandAccent : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
