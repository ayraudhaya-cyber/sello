import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/providers/theme_mode_provider.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';

/// Placeholder global search control for shell chrome.
class GlobalSearchControl extends StatelessWidget {
  const GlobalSearchControl({
    super.key,
    this.expanded = false,
    this.onTap,
  });

  final bool expanded;
  final VoidCallback? onTap;

  void _defaultTap(BuildContext context) {
    SelloSnackbars.show(
      context,
      message: 'Global search will be available in a later phase.',
      icon: Icons.search_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      return SizedBox(
        width: 280,
        height: 40,
        child: Material(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.inputAll,
          child: InkWell(
            onTap: onTap ?? () => _defaultTap(context),
            borderRadius: AppRadius.inputAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: context.selloColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Search…',
                      style: context.texts.bodyMedium?.copyWith(
                        color: context.selloColors.textTertiary,
                      ),
                    ),
                  ),
                  Text(
                    '⌘K',
                    style: context.texts.labelSmall?.copyWith(
                      color: context.selloColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Search',
      onPressed: onTap ?? () => _defaultTap(context),
      icon: const Icon(Icons.search_rounded),
    );
  }
}

/// Notification bell placeholder.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () {
        SelloSnackbars.show(
          context,
          message: 'Notifications will appear here.',
          icon: Icons.notifications_none_rounded,
        );
      },
      icon: Badge(
        isLabelVisible: false,
        child: Icon(
          Icons.notifications_none_rounded,
          color: context.selloColors.textSecondary,
        ),
      ),
    );
  }
}

/// User avatar + overflow menu (profile, theme stub, sign out).
class UserProfileMenu extends ConsumerWidget {
  const UserProfileMenu({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return const SizedBox.shrink();

    return PopupMenuButton<_ProfileAction>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      onSelected: (action) async {
        switch (action) {
          case _ProfileAction.profile:
            SelloSnackbars.show(
              context,
              message: 'Profile settings arrive with Phase 2.',
            );
          case _ProfileAction.theme:
            ref.read(themeModeProvider.notifier).toggleLightDark();
            SelloSnackbars.show(
              context,
              message:
                  'Theme mode toggled (dark palette not implemented yet — stays light).',
              icon: Icons.contrast_rounded,
            );
          case _ProfileAction.signOut:
            final confirmed = await showSelloDialog(
              context: context,
              title: 'Sign out?',
              message: 'You will need to sign in again to continue.',
              confirmLabel: 'Sign out',
              destructive: true,
            );
            if (confirmed == true) {
              await ref.read(authSessionProvider.notifier).signOut();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.displayName, style: context.texts.titleSmall),
              Text(
                session.email,
                style: context.texts.bodySmall?.copyWith(
                  color: context.selloColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                session.role.label,
                style: context.texts.labelSmall?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _ProfileAction.profile,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline_rounded),
            title: Text('Profile'),
          ),
        ),
        const PopupMenuItem(
          value: _ProfileAction.theme,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.contrast_rounded),
            title: Text('Theme (preview)'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _ProfileAction.signOut,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: compact ? 16 : 18,
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.primary,
              child: Text(
                session.initials,
                style: context.texts.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: context.selloColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ProfileAction { profile, theme, signOut }
