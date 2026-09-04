import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/mobile/profile/presentation/sello_pwa_install_card.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/updates/update_check_messages.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/widgets/widgets.dart';

class SelloProfilePage extends ConsumerWidget {
  const SelloProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    return AppPageScaffold(
      title: 'Profile',
      subtitle: null,
      showBreadcrumbs: false,
      body: Column(
        children: [
          SelloCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: context.brandAccentContainer,
                foregroundColor: context.brandAccent,
                child: Text(session?.initials ?? '?'),
              ),
              title: Text(
                session?.displayName ?? 'User',
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                session?.email ?? '',
                style: context.texts.bodySmall?.copyWith(
                  color: context.selloColors.textTertiary,
                ),
              ),
              trailing: Text(
                session?.appRole.shortLabel ?? '',
                style: context.texts.labelMedium?.copyWith(
                  color: context.brandAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.gap),
          const SelloPwaInstallCard(),
          SelloCard(
            enableHoverLift: false,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Role'),
                  trailing: Text(
                    session?.role.name ?? '—',
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.outlineSubtle),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Branch'),
                  trailing: Text(
                    session?.branchName ?? '—',
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.outlineSubtle),
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('Company'),
                  trailing: Text(
                    session?.companyName ?? '—',
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap),
          const _SelloVersionCard(),
          const SizedBox(height: AppSpacing.lg),
          SelloButton(
            label: 'Sign out',
            icon: Icons.logout_rounded,
            variant: SelloButtonVariant.outline,
            expanded: true,
            onPressed: () =>
                ref.read(authSessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _SelloVersionCard extends ConsumerWidget {
  const _SelloVersionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(installedAppVersionProvider);
    final checking = ref.watch(updateCheckControllerProvider).isLoading;
    final label = installed.when(
      data: (version) => 'Sello ${version.versionName} (${version.build})',
      loading: () => 'Sello',
      error: (_, _) => 'Sello',
    );

    return SelloCard(
      enableHoverLift: false,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.texts.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SelloButton(
            label: checking ? 'Checking…' : 'Check for updates',
            variant: SelloButtonVariant.ghost,
            size: SelloButtonSize.small,
            onPressed: checking
                ? null
                : () async {
                    final result = await ref
                        .read(updateCheckControllerProvider.notifier)
                        .checkNow();
                    if (!context.mounted) return;
                    if (result.status == UpdateCheckStatus.upToDate) {
                      SelloSnackbars.success(
                        context,
                        UpdateCheckMessages.manualResult(result),
                      );
                    } else if (result.status == UpdateCheckStatus.checkFailed) {
                      SelloSnackbars.info(
                        context,
                        UpdateCheckMessages.manualResult(result),
                      );
                    }
                  },
          ),
        ],
      ),
    );
  }
}
