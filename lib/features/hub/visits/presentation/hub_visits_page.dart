import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/visits/application/hub_visits_provider.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Manager operational visits feed — separate from Schedule planning.
class HubVisitsPage extends ConsumerWidget {
  const HubVisitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hubVisitsProvider);
    final day = state.day ?? DateTime.now();

    return AppPageScaffold(
      title: 'Visits',
      subtitle: 'What happened in the field today',
      maxWidth: AppSpacing.contentMax,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => ref.read(hubVisitsProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                SelloFormatters.date(day),
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    await ref
                        .read(hubVisitsProvider.notifier)
                        .refresh(day: picked);
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: const Text('Change day'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StatsRow(stats: state.stats),
          const SizedBox(height: 18),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (state.error != null)
            SelloStateView.error(
              title: 'Unable to load visits',
              message: state.error!,
              actionLabel: 'Try again',
              onAction: () => ref.read(hubVisitsProvider.notifier).refresh(),
            )
          else if (state.visits.isEmpty)
            const SelloEmptyState(
              title: 'No field visits yet',
              message:
                  'Completed and in-progress visits appear here as reps work their day.',
              icon: Icons.place_outlined,
            )
          else
            for (final visit in state.visits) ...[
              _VisitCard(visit: visit),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final CustomerVisitDayStats stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Completed', '${stats.completed}', SelloStatusTone.success),
      ('In progress', '${stats.inProgress}', SelloStatusTone.brand),
      ('Pending plan', '${stats.scheduledPending}', SelloStatusTone.info),
      ('Missed', '${stats.missed}', SelloStatusTone.warning),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final children = [
          for (final card in cards)
            Expanded(
              child: _StatTile(
                label: card.$1,
                value: card.$2,
                tone: card.$3,
              ),
            ),
        ];
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                children[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(children: [children[0], const SizedBox(width: 10), children[1]]),
            const SizedBox(height: 10),
            Row(children: [children[2], const SizedBox(width: 10), children[3]]),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final SelloStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: tone.accentFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final CustomerVisit visit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  visit.customerName ?? 'Customer',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              SelloStatusBadge(
                label: visit.status.label,
                tone: switch (visit.status) {
                  CustomerVisitStatus.completed => SelloStatusTone.success,
                  CustomerVisitStatus.inProgress => SelloStatusTone.brand,
                  CustomerVisitStatus.cancelled => SelloStatusTone.neutral,
                },
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              visit.employeeName ?? 'Rep',
              SelloFormatters.dateTime(visit.startedAt),
              if (visit.isCompleted) visit.durationLabel,
              if (visit.outcome != null) visit.outcome!.label,
            ].join(' · '),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (visit.notes != null && visit.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              visit.notes!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (visit.orderCount > 0 || visit.paymentCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (visit.orderCount > 0) '${visit.orderCount} orders',
                if (visit.paymentCount > 0) '${visit.paymentCount} payments',
              ].join(' · '),
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (visit.hasStartGps || visit.hasEndGps) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (visit.hasStartGps) 'Start GPS captured',
                if (visit.hasEndGps) 'End GPS captured',
              ].join(' · '),
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11.5,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on SelloStatusTone {
  Color accentFor(BuildContext context) => switch (this) {
        SelloStatusTone.success => AppColors.success,
        SelloStatusTone.warning => AppColors.warning,
        SelloStatusTone.danger => AppColors.error,
        SelloStatusTone.brand => context.brandAccent,
        SelloStatusTone.info => AppColors.info,
        SelloStatusTone.neutral => AppColors.textTertiary,
      };
}
