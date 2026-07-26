import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

class SelloProfilePage extends ConsumerWidget {
  const SelloProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    return AppPageScaffold(
      title: 'Profile',
      subtitle: 'Your account and preferences',
      showBreadcrumbs: false,
      body: Column(
        children: [
          SelloCard(
            elevation: SelloCardElevation.soft,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.primary,
                child: Text(session?.initials ?? '?'),
              ),
              title: Text(session?.displayName ?? 'User'),
              subtitle: Text(session?.email ?? ''),
              trailing: Text(
                session?.role.shortLabel ?? '',
                style: context.texts.labelMedium?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
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
