import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/notifications/application/notifications_provider.dart';
import 'package:sello/services/notifications/notification_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:sello/shared/widgets/feedback/sello_activity_timeline.dart';

/// Opens the Notification Center — desktop anchored panel, mobile sheet.
Future<void> openNotificationCenter(BuildContext context) {
  if (context.isMobile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const SizedBox(
        height: 560,
        child: NotificationCenterPanel(),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (context) => const Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(top: 64, right: 24),
        child: Material(
          color: AppColors.surface,
          elevation: 12,
          shadowColor: Color(0x33000000),
          borderRadius: AppRadius.cardAll,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 420,
            height: 560,
            child: NotificationCenterPanel(),
          ),
        ),
      ),
    ),
  );
}

class NotificationCenterPanel extends ConsumerStatefulWidget {
  const NotificationCenterPanel({super.key});

  @override
  ConsumerState<NotificationCenterPanel> createState() =>
      _NotificationCenterPanelState();
}

class _NotificationCenterPanelState
    extends ConsumerState<NotificationCenterPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  static final _timeFmt = DateFormat('dd MMM · HH:mm');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    Future.microtask(
      () => ref.read(notificationsProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openNotification(AppNotification item) async {
    final session = ref.read(currentSessionProvider);
    await ref.read(notificationsProvider.notifier).markRead(item);

    if (!mounted) return;
    Navigator.of(context).maybePop();

    final route = session?.usesHub == true
        ? NotificationDeepLink.resolve(item)
        : NotificationDeepLink.resolveForSales(item);
    if (route != null && mounted) {
      context.go(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              if (state.unreadCount > 0)
                TextButton(
                  onPressed: state.isBusy
                      ? null
                      : () => ref
                          .read(notificationsProvider.notifier)
                          .markAllRead(),
                  child: const Text('Mark all read'),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: state.isLoading
                    ? null
                    : () =>
                        ref.read(notificationsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: [
            Tab(
              text: state.unreadCount > 0
                  ? 'Inbox (${state.unreadCount})'
                  : 'Inbox',
            ),
            const Tab(text: 'Activity'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _InboxTab(
                state: state,
                timeFmt: _timeFmt,
                onOpen: _openNotification,
                onFilter: (filter) => ref
                    .read(notificationsProvider.notifier)
                    .setFilter(filter),
                onCategory: (category) => ref
                    .read(notificationsProvider.notifier)
                    .setCategoryFilter(category),
                onSearch: (value) =>
                    ref.read(notificationsProvider.notifier).setSearch(value),
                onArchive: (item) =>
                    ref.read(notificationsProvider.notifier).archive(item),
                onSnooze: (item) =>
                    ref.read(notificationsProvider.notifier).snooze(item),
                onDelete: (item) =>
                    ref.read(notificationsProvider.notifier).softDelete(item),
              ),
              _ActivityTab(
                state: state,
                timeFmt: _timeFmt,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InboxTab extends StatelessWidget {
  const _InboxTab({
    required this.state,
    required this.timeFmt,
    required this.onOpen,
    required this.onFilter,
    required this.onCategory,
    required this.onSearch,
    required this.onArchive,
    required this.onSnooze,
    required this.onDelete,
  });

  final NotificationsState state;
  final DateFormat timeFmt;
  final ValueChanged<AppNotification> onOpen;
  final ValueChanged<NotificationInboxFilter> onFilter;
  final ValueChanged<NotificationCategory?> onCategory;
  final ValueChanged<String> onSearch;
  final ValueChanged<AppNotification> onArchive;
  final ValueChanged<AppNotification> onSnooze;
  final ValueChanged<AppNotification> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search notifications…',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: state.filter == NotificationInboxFilter.all &&
                      state.categoryFilter == null,
                  onTap: () {
                    onFilter(NotificationInboxFilter.all);
                    onCategory(null);
                  },
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Unread',
                  selected: state.filter == NotificationInboxFilter.unread,
                  onTap: () => onFilter(NotificationInboxFilter.unread),
                ),
                const SizedBox(width: 8),
                for (final category in const [
                  NotificationCategory.orders,
                  NotificationCategory.payments,
                  NotificationCategory.visits,
                  NotificationCategory.schedule,
                  NotificationCategory.inventory,
                  NotificationCategory.products,
                  NotificationCategory.customers,
                  NotificationCategory.suppliers,
                  NotificationCategory.team,
                  NotificationCategory.reliability,
                  NotificationCategory.intelligence,
                ]) ...[
                  _FilterChip(
                    label: category.label,
                    selected: state.categoryFilter == category,
                    onTap: () => onCategory(
                      state.categoryFilter == category ? null : category,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: state.isLoading && state.items.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : state.errorMessage != null && state.items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          state.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : state.items.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No notifications match.\nTry clearing filters or search.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                          itemCount: state.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = state.items[index];
                            return _NotificationTile(
                              item: item,
                              timeLabel:
                                  timeFmt.format(item.createdAt.toLocal()),
                              onTap: () => onOpen(item),
                              onArchive: () => onArchive(item),
                              onSnooze: () => onSnooze(item),
                              onDelete: () => onDelete(item),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.state,
    required this.timeFmt,
  });

  final NotificationsState state;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.activity.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        SelloActivityTimeline(
          events: state.activity,
          emptyMessage:
              'Activity will appear as your team creates orders, visits, and updates.',
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
      color: selected ? AppColors.opsSoft : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: selected ? AppColors.ops : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.timeLabel,
    required this.onTap,
    required this.onArchive,
    required this.onSnooze,
    required this.onDelete,
  });

  final AppNotification item;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onSnooze;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tone = switch (item.priority) {
      NotificationPriority.critical || NotificationPriority.high =>
        AppColors.attention,
      NotificationPriority.information => AppColors.info,
      NotificationPriority.normal => AppColors.ops,
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _iconFor(item.category),
                size: 18,
                color: tone,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: item.isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (item.isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.attention,
                            shape: BoxShape.circle,
                          ),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          switch (value) {
                            case 'snooze':
                              onSnooze();
                            case 'archive':
                              onArchive();
                            case 'delete':
                              onDelete();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'snooze',
                            child: Text('Snooze 1 hour'),
                          ),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text('Archive'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                      ),
                    ],
                  ),
                  if (item.body != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${item.category.label} · $timeLabel',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(NotificationCategory category) {
    return switch (category) {
      NotificationCategory.orders => Icons.receipt_long_outlined,
      NotificationCategory.inventory => Icons.inventory_2_outlined,
      NotificationCategory.payments => Icons.payments_outlined,
      NotificationCategory.customers => Icons.storefront_outlined,
      NotificationCategory.schedule ||
      NotificationCategory.visits =>
        Icons.event_outlined,
      NotificationCategory.team => Icons.groups_outlined,
      NotificationCategory.suppliers => Icons.local_shipping_outlined,
      NotificationCategory.products => Icons.shopping_bag_outlined,
      NotificationCategory.intelligence => Icons.auto_awesome_outlined,
      NotificationCategory.reliability => Icons.cloud_sync_outlined,
      NotificationCategory.system => Icons.info_outline_rounded,
    };
  }
}
