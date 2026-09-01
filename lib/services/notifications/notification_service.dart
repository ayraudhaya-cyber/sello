import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Platform emit API — prefer [BusinessEventBus.publish] from domain code.
///
/// Best-effort: failures are swallowed so domain writes are never blocked.
class NotificationService {
  NotificationService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// Emit in-app notification(s) and optionally log company activity.
  Future<void> emit({
    required String companyId,
    required NotificationEmitInput input,
    String? actorEmployeeId,
    String? actorName,
  }) async {
    try {
      if (input.notifyHubRoles) {
        await _client.rpc(
          'emit_notifications_for_hub_roles',
          params: {
            'p_company_id': companyId,
            'p_category': input.category.dbValue,
            'p_type': input.type,
            'p_title': input.title,
            'p_body': input.body,
            'p_priority': input.priority.dbValue,
            'p_actor_employee_id': actorEmployeeId,
            'p_reference_type': input.referenceType,
            'p_reference_id': input.referenceId,
            'p_route_hint': input.routeHint,
            'p_payload': <String, dynamic>{},
            'p_exclude_employee_id': input.excludeEmployeeId,
          },
        );
      } else if (input.recipientEmployeeId != null) {
        await _client.rpc(
          'emit_notification',
          params: {
            'p_company_id': companyId,
            'p_recipient_employee_id': input.recipientEmployeeId,
            'p_category': input.category.dbValue,
            'p_type': input.type,
            'p_title': input.title,
            'p_body': input.body,
            'p_priority': input.priority.dbValue,
            'p_actor_employee_id': actorEmployeeId,
            'p_reference_type': input.referenceType,
            'p_reference_id': input.referenceId,
            'p_route_hint': input.routeHint,
            'p_payload': <String, dynamic>{},
          },
        );
      }

      if (input.logActivity) {
        await logActivity(
          companyId: companyId,
          category: input.category,
          eventType: input.type,
          summary: input.activitySummary ?? input.title,
          actorEmployeeId: actorEmployeeId,
          actorName: actorName,
          referenceType: input.referenceType,
          referenceId: input.referenceId,
        );
      }
    } catch (_) {
      // Never fail the primary domain write because of notifications.
    }
  }

  Future<void> logActivity({
    required String companyId,
    required NotificationCategory category,
    required String eventType,
    required String summary,
    String? actorEmployeeId,
    String? actorName,
    String? referenceType,
    String? referenceId,
  }) async {
    try {
      await _client.rpc(
        'log_company_activity',
        params: {
          'p_company_id': companyId,
          'p_category': category.dbValue,
          'p_event_type': eventType,
          'p_summary': summary,
          'p_actor_employee_id': actorEmployeeId,
          'p_actor_name': actorName,
          'p_reference_type': referenceType,
          'p_reference_id': referenceId,
          'p_metadata': <String, dynamic>{},
        },
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to log activity.'
            : error.message,
      );
    } catch (_) {
      // Best-effort when called from emit().
    }
  }
}

/// Resolves deep-link routes from notification metadata.
abstract final class NotificationDeepLink {
  /// Prefer entity-aware hints when reference ids are known.
  static String? hintFor({
    required NotificationCategory category,
    String? referenceType,
    String? referenceId,
  }) {
    final id = referenceId?.trim();
    if (id != null && id.isNotEmpty) {
      final typed = referenceType?.trim();
      return switch (typed) {
        'order' => '${RoutePaths.hubOrders}?id=$id',
        'customer' => '${RoutePaths.hubCustomers}?id=$id',
        'product' => '${RoutePaths.hubProducts}?id=$id',
        'supplier' => '${RoutePaths.hubSuppliers}?id=$id',
        'payment' => '${RoutePaths.hubPayments}?id=$id',
        'customer_visit' || 'visit' => '${RoutePaths.hubVisits}?id=$id',
        'employee' => '${RoutePaths.hubEmployees}?id=$id',
        'scheduled_visit' => RoutePaths.hubSchedule,
        _ => null,
      };
    }

    return switch (category) {
      NotificationCategory.orders => RoutePaths.hubOrders,
      NotificationCategory.inventory => RoutePaths.hubInventory,
      NotificationCategory.payments => RoutePaths.hubPayments,
      NotificationCategory.customers => RoutePaths.hubCustomers,
      NotificationCategory.suppliers => RoutePaths.hubSuppliers,
      NotificationCategory.products => RoutePaths.hubProducts,
      NotificationCategory.schedule => RoutePaths.hubSchedule,
      NotificationCategory.visits => RoutePaths.hubVisits,
      NotificationCategory.team => RoutePaths.hubEmployees,
      NotificationCategory.system => RoutePaths.hubDashboard,
      NotificationCategory.intelligence => RoutePaths.hubReports,
      NotificationCategory.reliability => RoutePaths.hubSettings,
    };
  }

  static String? resolve(AppNotification notification) {
    final hint = notification.routeHint?.trim();
    if (hint != null && hint.isNotEmpty) return hint;

    return hintFor(
      category: notification.category,
      referenceType: notification.referenceType,
      referenceId: notification.referenceId,
    );
  }

  /// Sales-app equivalent when the user is on the field shell.
  static String? resolveForSales(AppNotification notification) {
    final hint = notification.routeHint?.trim();
    if (hint != null &&
        hint.isNotEmpty &&
        hint.startsWith(RoutePaths.sello)) {
      return hint;
    }

    final id = notification.referenceId?.trim();
    if (id != null && id.isNotEmpty) {
      return switch (notification.referenceType) {
        'order' => '${RoutePaths.selloOrders}?id=$id',
        'customer' => '${RoutePaths.selloCustomers}?id=$id',
        'product' => '${RoutePaths.selloProducts}?id=$id',
        'customer_visit' || 'visit' => RoutePaths.selloDashboard,
        _ => null,
      };
    }

    return switch (notification.category) {
      NotificationCategory.orders => RoutePaths.selloOrders,
      NotificationCategory.customers => RoutePaths.selloCustomers,
      NotificationCategory.inventory ||
      NotificationCategory.products =>
        RoutePaths.selloInventory,
      NotificationCategory.payments => RoutePaths.selloOrders,
      NotificationCategory.schedule ||
      NotificationCategory.visits =>
        RoutePaths.selloDashboard,
      _ => RoutePaths.selloDashboard,
    };
  }
}
