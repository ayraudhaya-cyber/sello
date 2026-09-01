import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPageResult {
  const NotificationPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<AppNotification> items;
  final bool hasMore;
}

/// Shared inbox + company activity + preferences repository (Hub and Sales).
class NotificationRepository {
  NotificationRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<int> fetchUnreadCount({required String employeeId}) async {
    try {
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('recipient_employee_id', employeeId)
          .isFilter('deleted_at', null)
          .isFilter('archived_at', null)
          .isFilter('read_at', null);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<NotificationPageResult> fetchInbox({
    required String employeeId,
    bool unreadOnly = false,
    NotificationCategory? category,
    String search = '',
    int page = 0,
    int pageSize = 40,
  }) async {
    try {
      var query = _client
          .from('notifications')
          .select()
          .eq('recipient_employee_id', employeeId)
          .isFilter('deleted_at', null)
          .isFilter('archived_at', null);

      if (unreadOnly) {
        query = query.isFilter('read_at', null);
      }
      if (category != null) {
        query = query.eq('category', category.dbValue);
      }

      final rows = (await query
          .order('created_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize - 1)) as List;

      var items = rows
          .map(
            (row) => AppNotification.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .where((n) => !n.isSnoozed)
          .toList();

      final needle = search.trim().toLowerCase();
      if (needle.isNotEmpty) {
        items = items
            .where((n) {
              final hay = [
                n.title,
                n.body,
                n.category.label,
                n.type,
              ].whereType<String>().join(' ').toLowerCase();
              return hay.contains(needle);
            })
            .toList();
      }

      return NotificationPageResult(
        items: items,
        hasMore: rows.length == pageSize,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load notifications.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load notifications.');
    }
  }

  Future<List<CompanyActivityEvent>> fetchCompanyActivity({
    required String companyId,
    NotificationCategory? category,
    String? referenceType,
    String? referenceId,
    String search = '',
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('company_activity_events')
          .select()
          .eq('company_id', companyId);

      if (category != null) {
        query = query.eq('category', category.dbValue);
      }
      if (referenceType != null && referenceType.isNotEmpty) {
        query = query.eq('reference_type', referenceType);
      }
      if (referenceId != null && referenceId.isNotEmpty) {
        query = query.eq('reference_id', referenceId);
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);

      var items = (rows as List)
          .map(
            (row) => CompanyActivityEvent.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();

      final needle = search.trim().toLowerCase();
      if (needle.isNotEmpty) {
        items = items
            .where((e) {
              final hay = [
                e.summary,
                e.actorName,
                e.category.label,
                e.eventType,
              ].whereType<String>().join(' ').toLowerCase();
              return hay.contains(needle);
            })
            .toList();
      }

      return items;
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load activity.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load activity.');
    }
  }

  Future<void> markRead({
    required String notificationId,
    required String employeeId,
  }) async {
    try {
      await _client.from('notifications').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', notificationId).eq('recipient_employee_id', employeeId);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to mark as read.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to mark as read.');
    }
  }

  Future<void> markAllRead({required String employeeId}) async {
    try {
      await _client
          .from('notifications')
          .update({
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('recipient_employee_id', employeeId)
          .isFilter('deleted_at', null)
          .isFilter('read_at', null);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to mark all as read.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to mark all as read.');
    }
  }

  /// Soft-archive — prepared for future UI.
  Future<void> archive({
    required String notificationId,
    required String employeeId,
  }) async {
    try {
      await _client.from('notifications').update({
        'archived_at': DateTime.now().toUtc().toIso8601String(),
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', notificationId).eq('recipient_employee_id', employeeId);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to archive notification.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to archive notification.');
    }
  }

  /// Soft-delete seam — prepared for future UI.
  Future<void> softDelete({
    required String notificationId,
    required String employeeId,
  }) async {
    try {
      await _client.from('notifications').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', notificationId).eq('recipient_employee_id', employeeId);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to delete notification.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to delete notification.');
    }
  }

  /// Snooze seam — prepared for future UI.
  Future<void> snooze({
    required String notificationId,
    required String employeeId,
    required DateTime until,
  }) async {
    try {
      await _client.from('notifications').update({
        'snoozed_until': until.toUtc().toIso8601String(),
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', notificationId).eq('recipient_employee_id', employeeId);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to snooze notification.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to snooze notification.');
    }
  }

  Future<List<NotificationPreference>> fetchPreferences({
    required String employeeId,
  }) async {
    try {
      await _client.rpc(
        'ensure_notification_preferences',
        params: {'p_employee_id': employeeId},
      );

      final rows = await _client
          .from('notification_preferences')
          .select()
          .eq('employee_id', employeeId)
          .order('category');

      return (rows as List)
          .map(
            (row) => NotificationPreference.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      // Migration 027 may not be applied yet — return empty gracefully.
      if (error.message.toLowerCase().contains('ensure_notification')) {
        return const [];
      }
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load notification preferences.'
            : error.message,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> updatePreference(NotificationPreference preference) async {
    try {
      await _client
          .from('notification_preferences')
          .update(preference.toUpdatePayload())
          .eq('id', preference.id)
          .eq('employee_id', preference.employeeId);
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to save preference.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to save preference.');
    }
  }
}
