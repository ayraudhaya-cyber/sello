import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/audit_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared audit writer — best-effort; never blocks domain writes.
///
/// Prefer calling from BusinessEventBus subscribers or PermissionService
/// sensitive actions. Generation of compliance exports comes later.
class AuditService {
  AuditService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<void> log({
    required String companyId,
    required AuditLogInput input,
    String? actorEmployeeId,
    String? actorName,
  }) async {
    try {
      await _client.rpc(
        'log_audit_event',
        params: {
          'p_company_id': companyId,
          'p_actor_employee_id': actorEmployeeId,
          'p_actor_name': actorName,
          'p_action': input.action,
          'p_summary': input.summary,
          'p_module_key': input.moduleKey,
          'p_reference_type': input.referenceType,
          'p_reference_id': input.referenceId,
          'p_metadata': input.metadata,
        },
      );
    } on PostgrestException catch (error) {
      // Soft-fail when migration 029 is not applied yet.
      if (error.message.toLowerCase().contains('log_audit_event')) return;
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to write audit event.'
            : error.message,
      );
    } catch (_) {
      // Best-effort.
    }
  }

  Future<List<AuditEvent>> fetchRecent({
    required String companyId,
    int limit = 50,
    String? moduleKey,
  }) async {
    try {
      final rows = moduleKey != null && moduleKey.isNotEmpty
          ? await _client
              .from('audit_events')
              .select()
              .eq('company_id', companyId)
              .eq('module_key', moduleKey)
              .order('created_at', ascending: false)
              .limit(limit)
          : await _client
              .from('audit_events')
              .select()
              .eq('company_id', companyId)
              .order('created_at', ascending: false)
              .limit(limit);
      return [
        for (final row in rows as List)
          AuditEvent.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } on PostgrestException {
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
