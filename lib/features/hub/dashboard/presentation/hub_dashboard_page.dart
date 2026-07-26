import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubDashboardPage extends ConsumerWidget {
  const HubDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final columns = context.responsiveValue(mobile: 1, tablet: 2, desktop: 4);

    return AppPageScaffold(
      title: 'Dashboard',
      subtitle:
          'Welcome back, ${session?.displayName ?? 'Leader'} — foundation preview',
      actions: [
        SelloButton(
          label: 'Export',
          icon: Icons.download_rounded,
          variant: SelloButtonVariant.outline,
          size: SelloButtonSize.small,
          onPressed: () {},
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: context.isMobile ? 1.6 : 1.4,
            children: const [
              SelloStatCard(
                label: 'Revenue (MTD)',
                value: '—',
                icon: Icons.payments_rounded,
                trendLabel: 'Connect data in Phase 4',
              ),
              SelloStatCard(
                label: 'Orders',
                value: '—',
                icon: Icons.shopping_bag_rounded,
              ),
              SelloStatCard(
                label: 'Active customers',
                value: '—',
                icon: Icons.groups_rounded,
              ),
              SelloStatCard(
                label: 'Low stock SKUs',
                value: '—',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          ResponsiveBuilder(
            mobile: (_) => const Column(
              children: [
                _ActivityCard(),
                SizedBox(height: AppSpacing.md),
                _PipelineCard(),
              ],
            ),
            tablet: (_) => const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _ActivityCard()),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: _PipelineCard()),
              ],
            ),
            desktop: (_) => const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _ActivityCard()),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: _PipelineCard()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    return SelloDashboardCard(
      title: 'Recent activity',
      subtitle: 'Placeholder table — no live data yet',
      child: SelloDataTable(
        columns: const [
          DataColumn(label: Text('Order')),
          DataColumn(label: Text('Customer')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Total')),
        ],
        rows: [
          for (final i in [1, 2, 3, 4])
            DataRow(
              cells: [
                DataCell(Text('SO-100$i')),
                const DataCell(Text('—')),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      'Draft',
                      style: context.texts.labelSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const DataCell(Text('—')),
              ],
            ),
        ],
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard();

  @override
  Widget build(BuildContext context) {
    return SelloDashboardCard(
      title: 'Sales pulse',
      subtitle: 'Charts arrive with analytics phase',
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppGradients.primarySoft,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppColors.outline),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.area_chart_rounded,
                color: AppColors.primary,
                size: 36,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Analytics surface', style: context.texts.titleSmall),
              Text(
                'Reserved for Phase 5',
                style: context.texts.bodySmall?.copyWith(
                  color: context.selloColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
