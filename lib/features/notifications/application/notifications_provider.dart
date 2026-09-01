import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/notification_repository.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_notification.dart';

enum NotificationInboxFilter { all, unread }

class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.activity = const [],
    this.unreadCount = 0,
    this.filter = NotificationInboxFilter.all,
    this.categoryFilter,
    this.search = '',
    this.isLoading = false,
    this.isBusy = false,
    this.errorMessage,
    this.initialized = false,
  });

  final List<AppNotification> items;
  final List<CompanyActivityEvent> activity;
  final int unreadCount;
  final NotificationInboxFilter filter;
  final NotificationCategory? categoryFilter;
  final String search;
  final bool isLoading;
  final bool isBusy;
  final String? errorMessage;
  final bool initialized;

  bool get isEmpty => !isLoading && initialized && items.isEmpty;

  NotificationsState copyWith({
    List<AppNotification>? items,
    List<CompanyActivityEvent>? activity,
    int? unreadCount,
    NotificationInboxFilter? filter,
    NotificationCategory? categoryFilter,
    bool clearCategory = false,
    String? search,
    bool? isLoading,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
    bool? initialized,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      activity: activity ?? this.activity,
      unreadCount: unreadCount ?? this.unreadCount,
      filter: filter ?? this.filter,
      categoryFilter:
          clearCategory ? null : (categoryFilter ?? this.categoryFilter),
      search: search ?? this.search,
      isLoading: isLoading ?? this.isLoading,
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      initialized: initialized ?? this.initialized,
    );
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
  NotificationsNotifier.new,
);

class NotificationsNotifier extends Notifier<NotificationsState> {
  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  @override
  NotificationsState build() {
    ref.listen(currentSessionProvider, (previous, next) {
      final prevKey = previous?.employee.id;
      final nextKey = next?.employee.id;
      if (prevKey == nextKey) return;
      Future.microtask(refresh);
    });

    Future.microtask(refresh);
    return const NotificationsState(isLoading: true);
  }

  Future<void> refresh() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      state = const NotificationsState(initialized: true);
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true, initialized: true);

    try {
      final employeeId = session.employee.id;
      final companyId = session.company.id;
      final inbox = await _repo.fetchInbox(
        employeeId: employeeId,
        unreadOnly: state.filter == NotificationInboxFilter.unread,
        category: state.categoryFilter,
        search: state.search,
      );
      final unread = await _repo.fetchUnreadCount(employeeId: employeeId);
      final activity = await _repo.fetchCompanyActivity(
        companyId: companyId,
        category: state.categoryFilter,
        search: state.search,
      );

      state = state.copyWith(
        items: inbox.items,
        activity: activity,
        unreadCount: unread,
        isLoading: false,
        clearError: true,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to load notifications.',
      );
    }
  }

  Future<void> refreshUnreadOnly() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    final unread =
        await _repo.fetchUnreadCount(employeeId: session.employee.id);
    state = state.copyWith(unreadCount: unread);
  }

  void setFilter(NotificationInboxFilter filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
    refresh();
  }

  void setCategoryFilter(NotificationCategory? category) {
    if (state.categoryFilter == category) return;
    state = state.copyWith(
      categoryFilter: category,
      clearCategory: category == null,
    );
    refresh();
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
    refresh();
  }

  Future<void> markRead(AppNotification notification) async {
    if (!notification.isUnread) return;
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    state = state.copyWith(isBusy: true);
    try {
      await _repo.markRead(
        notificationId: notification.id,
        employeeId: session.employee.id,
      );
      await refresh();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> markAllRead() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    state = state.copyWith(isBusy: true);
    try {
      await _repo.markAllRead(employeeId: session.employee.id);
      await refresh();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> archive(AppNotification notification) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    state = state.copyWith(isBusy: true);
    try {
      await _repo.archive(
        notificationId: notification.id,
        employeeId: session.employee.id,
      );
      await refresh();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> softDelete(AppNotification notification) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    state = state.copyWith(isBusy: true);
    try {
      await _repo.softDelete(
        notificationId: notification.id,
        employeeId: session.employee.id,
      );
      await refresh();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> snooze(
    AppNotification notification, {
    Duration duration = const Duration(hours: 1),
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    state = state.copyWith(isBusy: true);
    try {
      await _repo.snooze(
        notificationId: notification.id,
        employeeId: session.employee.id,
        until: DateTime.now().toUtc().add(duration),
      );
      await refresh();
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }
}
