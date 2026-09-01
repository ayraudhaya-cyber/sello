import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/notifications/application/notifications_provider.dart';
import 'package:sello/features/notifications/presentation/notification_center_panel.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/providers/theme_mode_provider.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/chrome/quick_actions_button.dart';
import 'package:sello/shared/widgets/feedback/sello_feedback.dart';

/// Premium command-style global search control for shell chrome.
class GlobalSearchControl extends StatefulWidget {
  const GlobalSearchControl({
    super.key,
    this.expanded = false,
    this.onTap,
  });

  final bool expanded;
  final VoidCallback? onTap;

  @override
  State<GlobalSearchControl> createState() => _GlobalSearchControlState();
}

class _GlobalSearchControlState extends State<GlobalSearchControl> {
  bool _hovered = false;

  void _defaultTap(BuildContext context) {
    SelloSnackbars.info(
      context,
      'Global search will be available in a later phase.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expanded) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: AppDurations.hover,
          width: 360,
          height: AppSpacing.controlHeight,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surface : AppColors.surfaceMuted,
            borderRadius: AppRadius.inputAll,
            border: Border.all(
              color: _hovered ? AppColors.outlineStrong : AppColors.outline,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap ?? () => _defaultTap(context),
              borderRadius: AppRadius.inputAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: context.selloColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Search products, customers or orders...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium?.copyWith(
                          color: context.selloColors.textTertiary,
                          letterSpacing: -0.05,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Text(
                        '⌘K',
                        style: context.texts.labelSmall?.copyWith(
                          color: context.selloColors.textTertiary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Search',
      onPressed: widget.onTap ?? () => _defaultTap(context),
      icon: const Icon(Icons.search_rounded),
    );
  }
}

/// Notification bell — opens the shared Notification Center.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      notificationsProvider.select((s) => s.unreadCount),
    );
    final hasUnread = unread > 0;

    return SizedBox(
      width: AppSpacing.controlHeight,
      height: AppSpacing.controlHeight,
      child: IconButton(
        tooltip: hasUnread ? 'Notifications ($unread unread)' : 'Notifications',
        iconSize: 20,
        onPressed: () => openNotificationCenter(context),
        icon: Badge(
          isLabelVisible: hasUnread,
          label: Text(
            unread > 9 ? '9+' : '$unread',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
          ),
          backgroundColor: AppColors.attention,
          child: Icon(
            hasUnread
                ? Icons.notifications_rounded
                : Icons.notifications_none_rounded,
            color: IconTheme.of(context).color ??
                context.selloColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// User avatar + overflow menu (settings, theme stub, sign out).
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
          case _ProfileAction.settings:
            if (session.usesHub) {
              context.go(RoutePaths.hubSettings);
            } else {
              context.go(RoutePaths.selloProfile);
            }
          case _ProfileAction.theme:
            ref.read(themeModeProvider.notifier).toggleLightDark();
            SelloSnackbars.info(
              context,
              'Theme mode toggled (dark palette not implemented yet — stays light).',
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
                session.role.name,
                style: context.texts.labelSmall?.copyWith(
                  color: context.brandAccent,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _ProfileAction.settings,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xxs : AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: compact ? 15 : 16,
              backgroundColor: context.selloColors.surfaceSelected,
              child: Text(
                session.initials,
                style: context.texts.labelMedium?.copyWith(
                  color: context.brandAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  session.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: context.selloColors.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ProfileAction { settings, theme, signOut }
