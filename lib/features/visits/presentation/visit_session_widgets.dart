import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';
import 'package:sello/shared/widgets/inputs/sello_text_field.dart';

/// Fast complete-visit sheet — outcome + optional notes.
Future<bool> showCompleteVisitSheet(
  BuildContext context, {
  required String customerName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _CompleteVisitSheet(customerName: customerName),
  );
  return result == true;
}

class _CompleteVisitSheet extends ConsumerStatefulWidget {
  const _CompleteVisitSheet({required this.customerName});

  final String customerName;

  @override
  ConsumerState<_CompleteVisitSheet> createState() =>
      _CompleteVisitSheetState();
}

class _CompleteVisitSheetState extends ConsumerState<_CompleteVisitSheet> {
  VisitOutcome? _outcome;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final outcome = _outcome;
    if (outcome == null) {
      SelloSnackbars.error(context, 'Choose a visit outcome.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(activeCustomerVisitProvider.notifier).completeVisit(
            outcome: outcome,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      SelloSnackbars.error(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      SelloSnackbars.error(context, 'Unable to complete visit.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
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
          Text(
            'Complete visit',
            style: context.texts.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.customerName,
            style: context.texts.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Outcome',
            style: context.texts.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final outcome in VisitOutcome.values)
                ChoiceChip(
                  label: Text(outcome.label),
                  selected: _outcome == outcome,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _outcome = outcome),
                  selectedColor: context.brandAccent.withValues(alpha: 0.14),
                  labelStyle: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _outcome == outcome
                        ? context.brandAccent
                        : AppColors.textSecondary,
                  ),
                  side: BorderSide(
                    color: _outcome == outcome
                        ? context.brandAccent.withValues(alpha: 0.35)
                        : AppColors.outlinePanel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SelloTextField(
            controller: _notes,
            label: 'Notes',
            hint: 'Anything the team should know…',
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          SelloButton(
            label: _saving ? 'Saving…' : 'Complete visit',
            onPressed: _saving ? null : _submit,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Keep visiting'),
          ),
        ],
      ),
    );
  }
}

/// Status chip on the active-visit hero — colour carries meaning.
class ActiveVisitChip {
  const ActiveVisitChip({
    required this.label,
    this.icon,
    this.tone = ActiveVisitChipTone.neutral,
  });

  final String label;
  final IconData? icon;
  final ActiveVisitChipTone tone;
}

enum ActiveVisitChipTone { neutral, warning, danger, info, success }

/// Hero for the sales rep's active visit — one clear next action.
class ActiveVisitBanner extends ConsumerWidget {
  const ActiveVisitBanner({
    super.key,
    required this.onContinue,
    this.chips = const [],
  });

  final VoidCallback onContinue;
  final List<ActiveVisitChip> chips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCustomerVisitProvider).valueOrNull;
    if (active == null) return const SizedBox.shrink();

    final statusChips = <ActiveVisitChip>[
      ...chips,
      if (active.pendingSync)
        const ActiveVisitChip(
          label: 'Offline',
          icon: Icons.cloud_off_outlined,
          tone: ActiveVisitChipTone.warning,
        ),
      ActiveVisitChip(
        label: active.durationLabel,
        icon: Icons.schedule_rounded,
      ),
    ];

    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onContinue,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Now',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                active.customerName ?? 'Customer',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  height: 1.15,
                  color: AppColors.textPrimary,
                ),
              ),
              if (statusChips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final chip in statusChips) _MeaningChip(chip: chip),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SelloButton(
                label: 'Open visit',
                icon: Icons.arrow_forward_rounded,
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeaningChip extends StatelessWidget {
  const _MeaningChip({required this.chip});

  final ActiveVisitChip chip;

  @override
  Widget build(BuildContext context) {
    final color = switch (chip.tone) {
      ActiveVisitChipTone.warning => AppColors.warning,
      ActiveVisitChipTone.danger => AppColors.error,
      ActiveVisitChipTone.info => AppColors.info,
      ActiveVisitChipTone.success => AppColors.success,
      ActiveVisitChipTone.neutral => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chip.icon != null) ...[
            Icon(chip.icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            chip.label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

