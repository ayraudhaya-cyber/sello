import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

class SelloDashboardPage extends ConsumerWidget {
  const SelloDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    return AppPageScaffold(
      title: 'Hello, ${session?.displayName ?? 'there'}',
      subtitle: 'Ready for today’s visits',
      showBreadcrumbs: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: const Text('New order'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: context.responsiveValue(
              mobile: 2,
              tablet: 3,
              desktop: 4,
            ),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.35,
            children: const [
              SelloStatCard(
                label: 'Open orders',
                value: '—',
                icon: Icons.receipt_long_rounded,
              ),
              SelloStatCard(
                label: 'Customers',
                value: '—',
                icon: Icons.people_rounded,
              ),
              SelloStatCard(
                label: 'Products',
                value: '—',
                icon: Icons.inventory_2_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SelloDashboardCard(
            title: 'Quick actions',
            subtitle: 'Modules will connect here in later phases',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SelloButton(
                  label: 'Customers',
                  icon: Icons.people_rounded,
                  variant: SelloButtonVariant.outline,
                  onPressed: () {},
                ),
                SelloButton(
                  label: 'Catalog',
                  icon: Icons.storefront_rounded,
                  variant: SelloButtonVariant.outline,
                  onPressed: () {},
                ),
                SelloButton(
                  label: 'Inventory',
                  icon: Icons.warehouse_rounded,
                  variant: SelloButtonVariant.outline,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
