import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/app_notification.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/scheduled_visit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VisitPageResult {
  const VisitPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<ScheduledVisit> items;
  final bool hasMore;
}

/// Shared visit planning repository — Hub schedules; Sales Home reads today.
class VisitRepository {
  VisitRepository({
    SupabaseClient? client,
    BusinessEventBus? events,
  })  : _client = client ?? SupabaseService.client,
        _events = events ?? BusinessEventBus();

  final SupabaseClient _client;
  final BusinessEventBus _events;

  static const _select = '''
    id,
    company_id,
    branch_id,
    customer_id,
    employee_id,
    visit_date,
    preferred_time,
    expected_duration_minutes,
    status,
    priority,
    purpose,
    notes,
    area,
    sort_order,
    completed_at,
    cancelled_at,
    recurrence_rule,
    created_at,
    updated_at,
    customers!customer_id (id, name, phone),
    employees!employee_id (id, full_name)
  ''';

  Future<VisitDashboardStats> fetchDashboardStats({
    required String companyId,
    DateTime? day,
  }) async {
    try {
      final focus = day ?? DateTime.now();
      final dayKey = _dateKey(focus);
      final rows = await _client
          .from('scheduled_visits')
          .select('status, visit_date')
          .eq('company_id', companyId)
          .isFilter('deleted_at', null)
          .gte('visit_date', _dateKey(focus.subtract(const Duration(days: 7))))
          .lte('visit_date', _dateKey(focus.add(const Duration(days: 30))));

      var today = 0;
      var scheduled = 0;
      var completed = 0;
      var missed = 0;
      var unplanned = 0;

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final status = VisitStatus.fromDb(row['status'] as String?);
        final visitDate = row['visit_date'] as String?;
        if (visitDate == dayKey) today++;
        switch (status) {
          case VisitStatus.scheduled:
            scheduled++;
          case VisitStatus.completed:
            completed++;
          case VisitStatus.missed:
            missed++;
          case VisitStatus.unplanned:
            unplanned++;
          case VisitStatus.cancelled:
            break;
        }
      }

      return VisitDashboardStats(
        today: today,
        scheduled: scheduled,
        completed: completed,
        missed: missed,
        unplanned: unplanned,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load schedule stats.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load schedule stats.');
    }
  }

  Future<VisitPageResult> fetchVisits({
    required String companyId,
    DateTime? from,
    DateTime? to,
    String? employeeId,
    String? customerId,
    VisitStatus? status,
    String search = '',
    int page = 0,
    int pageSize = 50,
  }) async {
    try {
      var query = _client
          .from('scheduled_visits')
          .select(_select)
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      if (from != null) {
        query = query.gte('visit_date', _dateKey(from));
      }
      if (to != null) {
        query = query.lte('visit_date', _dateKey(to));
      }
      if (employeeId != null && employeeId.isNotEmpty) {
        query = query.eq('employee_id', employeeId);
      }
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      if (status != null) {
        query = query.eq('status', status.dbValue);
      }

      final response = await query
          .order('visit_date')
          .order('sort_order')
          .order('preferred_time')
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final rows = (response as List)
          .map(
            (row) =>
                ScheduledVisit.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      final hasMore = rows.length == pageSize;

      var items = rows;
      final needle = search.trim().toLowerCase();
      if (needle.isNotEmpty) {
        items = items
            .where((visit) {
              final hay = [
                visit.customerName,
                visit.employeeName,
                visit.purpose,
                visit.notes,
                visit.customerPhone,
              ].whereType<String>().join(' ').toLowerCase();
              return hay.contains(needle);
            })
            .toList();
      }

      return VisitPageResult(
        items: items,
        hasMore: hasMore,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load visits.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load visits.');
    }
  }

  Future<List<ScheduledVisit>> fetchVisitsForDay({
    required String companyId,
    required DateTime day,
    String? employeeId,
  }) async {
    final result = await fetchVisits(
      companyId: companyId,
      from: day,
      to: day,
      employeeId: employeeId,
      pageSize: 200,
    );
    return result.items;
  }

  Future<List<ScheduledVisit>> fetchVisitsForRange({
    required String companyId,
    required DateTime from,
    required DateTime to,
    String? employeeId,
  }) async {
    final result = await fetchVisits(
      companyId: companyId,
      from: from,
      to: to,
      employeeId: employeeId,
      pageSize: 500,
    );
    return result.items;
  }

  Future<ScheduledVisit?> fetchById({
    required String companyId,
    required String visitId,
  }) async {
    try {
      final row = await _client
          .from('scheduled_visits')
          .select(_select)
          .eq('company_id', companyId)
          .eq('id', visitId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return ScheduledVisit.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load that visit.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load that visit.');
    }
  }

  Future<({DateTime? lastVisitAt, DateTime? nextVisitAt})> fetchCustomerVisitPeek({
    required String companyId,
    required String customerId,
  }) async {
    try {
      final row = await _client
          .from('customers')
          .select('last_visit_at, next_visit_at')
          .eq('company_id', companyId)
          .eq('id', customerId)
          .maybeSingle();
      if (row == null) {
        return (lastVisitAt: null, nextVisitAt: null);
      }
      return (
        lastVisitAt: _parseDateTime(row['last_visit_at']),
        nextVisitAt: _parseDate(row['next_visit_at']),
      );
    } catch (_) {
      return (lastVisitAt: null, nextVisitAt: null);
    }
  }

  Future<String> upsertVisit({
    required VisitUpsertInput input,
    required String companyId,
    required String actorEmployeeId,
    String? branchId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'company_id': companyId,
        'branch_id': branchId ?? input.branchId,
        'customer_id': input.customerId,
        'employee_id': input.employeeId,
        'visit_date': _dateKey(input.visitDate),
        'preferred_time': _minutesToTime(input.preferredTimeMinutes),
        'expected_duration_minutes': input.expectedDurationMinutes,
        'status': input.status.dbValue,
        'priority': input.priority.dbValue,
        'purpose': _blankToNull(input.purpose),
        'notes': _blankToNull(input.notes),
        'area': _blankToNull(input.area),
        'sort_order': input.sortOrder,
        'recurrence_rule': _blankToNull(input.recurrenceRule),
        'updated_by': actorEmployeeId,
      };

      final String visitId;
      if (input.isCreate) {
        payload['created_by'] = actorEmployeeId;
        final inserted = await _client
            .from('scheduled_visits')
            .insert(payload)
            .select('id')
            .single();
        visitId = inserted['id'] as String;
      } else {
        await _client
            .from('scheduled_visits')
            .update(payload)
            .eq('id', input.id!)
            .eq('company_id', companyId);
        visitId = input.id!;
      }

      if (input.isCreate) {
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          event: BusinessEvents.visitScheduled(
            visitId: visitId,
            recipientEmployeeId: input.employeeId,
            priority: input.priority == VisitPriority.urgent ||
                    input.priority == VisitPriority.high
                ? NotificationPriority.high
                : NotificationPriority.normal,
          ),
        );
      }

      return visitId;
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to save this visit.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to save this visit.');
    }
  }

  /// Plan multiple stops for one rep/day — reuses [scheduled_visits] rows.
  ///
  /// Creates are inserted in one batch. Edits (non-null id) fall back to
  /// [upsertVisit]. Emits a single route notification for new stops.
  Future<int> upsertVisits({
    required List<VisitUpsertInput> inputs,
    required String companyId,
    required String actorEmployeeId,
    String? branchId,
  }) async {
    if (inputs.isEmpty) return 0;
    if (inputs.length == 1) {
      await upsertVisit(
        input: inputs.first,
        companyId: companyId,
        actorEmployeeId: actorEmployeeId,
        branchId: branchId,
      );
      return 1;
    }

    try {
      final creates = <VisitUpsertInput>[];
      final updates = <VisitUpsertInput>[];
      for (final input in inputs) {
        if (input.isCreate) {
          creates.add(input);
        } else {
          updates.add(input);
        }
      }

      for (final input in updates) {
        await upsertVisit(
          input: input,
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          branchId: branchId,
        );
      }

      if (creates.isNotEmpty) {
        final rows = [
          for (var i = 0; i < creates.length; i++)
            {
              'company_id': companyId,
              'branch_id': branchId ?? creates[i].branchId,
              'customer_id': creates[i].customerId,
              'employee_id': creates[i].employeeId,
              'visit_date': _dateKey(creates[i].visitDate),
              'preferred_time':
                  _minutesToTime(creates[i].preferredTimeMinutes),
              'expected_duration_minutes': creates[i].expectedDurationMinutes,
              'status': creates[i].status.dbValue,
              'priority': creates[i].priority.dbValue,
              'purpose': _blankToNull(creates[i].purpose),
              'notes': _blankToNull(creates[i].notes),
              'area': _blankToNull(creates[i].area),
              'sort_order': creates[i].sortOrder > 0
                  ? creates[i].sortOrder
                  : i,
              'recurrence_rule': _blankToNull(creates[i].recurrenceRule),
              'created_by': actorEmployeeId,
              'updated_by': actorEmployeeId,
            },
        ];
        await _client.from('scheduled_visits').insert(rows);

        final first = creates.first;
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          event: BusinessEvents.routePlanned(
            recipientEmployeeId: first.employeeId,
            stopCount: creates.length,
            area: first.area,
            visitDate: first.visitDate,
          ),
        );
      }

      return inputs.length;
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to plan these visits.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to plan these visits.');
    }
  }

  Future<void> setVisitStatus({
    required String companyId,
    required String visitId,
    required String actorEmployeeId,
    required VisitStatus status,
    bool emitNotification = true,
  }) async {
    try {
      final existing = await fetchById(companyId: companyId, visitId: visitId);

      final payload = <String, dynamic>{
        'status': status.dbValue,
        'updated_by': actorEmployeeId,
      };
      if (status == VisitStatus.completed) {
        payload['completed_at'] = DateTime.now().toUtc().toIso8601String();
      }
      if (status == VisitStatus.cancelled) {
        payload['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
      }

      await _client
          .from('scheduled_visits')
          .update(payload)
          .eq('id', visitId)
          .eq('company_id', companyId);

      if (!emitNotification || existing == null) return;

      final customerLabel = existing.customerName ?? 'a customer';
      if (status == VisitStatus.completed) {
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          event: BusinessEvents.visitCompleted(
            visitId: visitId,
            referenceType: 'visit',
            summary:
                '${existing.employeeName ?? 'A sales rep'} completed a visit with $customerLabel',
            body: 'Visit with $customerLabel was marked completed.',
            routeHint: RoutePaths.hubSchedule,
            excludeEmployeeId: actorEmployeeId,
          ),
        );
      } else if (status == VisitStatus.missed) {
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          event: BusinessEvents.visitMissed(
            visitId: visitId,
            customerLabel: customerLabel,
          ),
        );
      }
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to update visit status.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to update visit status.');
    }
  }

  Future<void> softDeleteVisit({
    required String companyId,
    required String visitId,
    required String actorEmployeeId,
  }) async {
    try {
      await _client.from('scheduled_visits').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': actorEmployeeId,
      }).eq('id', visitId).eq('company_id', companyId);
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to remove this visit.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to remove this visit.');
    }
  }

  /// Future-ready route reorder — updates [sort_order] for today's stops.
  Future<void> reorderDayRoute({
    required String companyId,
    required String actorEmployeeId,
    required List<String> visitIdsInOrder,
  }) async {
    try {
      for (var i = 0; i < visitIdsInOrder.length; i++) {
        await _client.from('scheduled_visits').update({
          'sort_order': i,
          'updated_by': actorEmployeeId,
        }).eq('id', visitIdsInOrder[i]).eq('company_id', companyId);
      }
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to reorder visits.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to reorder visits.');
    }
  }

  // ---------------------------------------------------------------------------
  // Operational Customer Visits (field activity — separate from Schedule)
  // ---------------------------------------------------------------------------

  static const _customerVisitSelect = '''
    id,
    company_id,
    branch_id,
    customer_id,
    employee_id,
    scheduled_visit_id,
    status,
    outcome,
    notes,
    started_at,
    ended_at,
    duration_minutes,
    start_latitude,
    start_longitude,
    end_latitude,
    end_longitude,
    offline_client_id,
    signature_storage_path,
    photo_paths,
    voice_note_path,
    created_at,
    updated_at,
    customers!customer_id (id, name, phone),
    employees!employee_id (id, full_name)
  ''';

  Future<CustomerVisit?> fetchActiveCustomerVisit({
    required String companyId,
    required String employeeId,
  }) async {
    try {
      final row = await _client
          .from('customer_visits')
          .select(_customerVisitSelect)
          .eq('company_id', companyId)
          .eq('employee_id', employeeId)
          .eq('status', CustomerVisitStatus.inProgress.dbValue)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return CustomerVisit.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load active visit.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load active visit.');
    }
  }

  Future<CustomerVisit?> fetchCustomerVisitById({
    required String companyId,
    required String visitId,
  }) async {
    try {
      final row = await _client
          .from('customer_visits')
          .select(_customerVisitSelect)
          .eq('company_id', companyId)
          .eq('id', visitId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return CustomerVisit.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load visit.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load visit.');
    }
  }

  Future<CustomerVisit?> fetchCustomerVisitByOfflineClientId({
    required String companyId,
    required String offlineClientId,
  }) async {
    try {
      final row = await _client
          .from('customer_visits')
          .select(_customerVisitSelect)
          .eq('company_id', companyId)
          .eq('offline_client_id', offlineClientId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return CustomerVisit.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load visit.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load visit.');
    }
  }

  Future<List<CustomerVisit>> fetchCustomerVisits({
    required String companyId,
    DateTime? from,
    DateTime? to,
    String? employeeId,
    String? customerId,
    CustomerVisitStatus? status,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('customer_visits')
          .select(_customerVisitSelect)
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      if (from != null) {
        query = query.gte('started_at', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query = query.lte('started_at', to.toUtc().toIso8601String());
      }
      if (employeeId != null && employeeId.isNotEmpty) {
        query = query.eq('employee_id', employeeId);
      }
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      if (status != null) {
        query = query.eq('status', status.dbValue);
      }

      final response = await query
          .order('started_at', ascending: false)
          .limit(limit);

      final visits = (response as List)
          .map(
            (row) => CustomerVisit.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
      return _enrichVisitLinkCounts(companyId: companyId, visits: visits);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load customer visits.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to load customer visits.');
    }
  }

  /// Customer timeline — completed visits newest first.
  Future<List<CustomerVisit>> fetchCustomerVisitHistory({
    required String companyId,
    required String customerId,
    int limit = 20,
  }) {
    return fetchCustomerVisits(
      companyId: companyId,
      customerId: customerId,
      status: CustomerVisitStatus.completed,
      limit: limit,
    );
  }

  Future<CustomerVisitDayStats> fetchCustomerVisitDayStats({
    required String companyId,
    DateTime? day,
  }) async {
    final focus = day ?? DateTime.now();
    final start = DateTime(focus.year, focus.month, focus.day);
    final end = start.add(const Duration(days: 1));

    try {
      final operational = await fetchCustomerVisits(
        companyId: companyId,
        from: start,
        to: end,
        limit: 500,
      );
      final scheduled = await fetchVisitsForDay(
        companyId: companyId,
        day: focus,
      );

      var completed = 0;
      var inProgress = 0;
      var cancelled = 0;
      for (final visit in operational) {
        switch (visit.status) {
          case CustomerVisitStatus.completed:
            completed++;
          case CustomerVisitStatus.inProgress:
            inProgress++;
          case CustomerVisitStatus.cancelled:
            cancelled++;
        }
      }

      final scheduledPending = scheduled
          .where((v) => v.status == VisitStatus.scheduled)
          .length;
      final missed =
          scheduled.where((v) => v.status == VisitStatus.missed).length;

      return CustomerVisitDayStats(
        completed: completed,
        inProgress: inProgress,
        cancelled: cancelled,
        scheduledPending: scheduledPending,
        missed: missed,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to load visit day stats.');
    }
  }

  Future<CustomerVisit> startCustomerVisit({
    required String companyId,
    required String actorEmployeeId,
    required StartCustomerVisitInput input,
  }) async {
    try {
      final existing = await fetchActiveCustomerVisit(
        companyId: companyId,
        employeeId: input.employeeId,
      );
      if (existing != null) {
        if (existing.customerId == input.customerId) return existing;
        throw const ValidationFailure(
          'Finish your current visit before starting another.',
        );
      }

      final payload = <String, dynamic>{
        'company_id': companyId,
        'branch_id': input.branchId,
        'customer_id': input.customerId,
        'employee_id': input.employeeId,
        'scheduled_visit_id': input.scheduledVisitId,
        'status': CustomerVisitStatus.inProgress.dbValue,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'created_by': actorEmployeeId,
        'updated_by': actorEmployeeId,
        if (input.offlineClientId != null)
          'offline_client_id': input.offlineClientId,
      };
      final gps = input.gps;
      if (gps != null) {
        payload['start_latitude'] = gps.latitude;
        payload['start_longitude'] = gps.longitude;
        payload['start_accuracy_meters'] = gps.accuracyMeters;
      }

      final inserted = await _client
          .from('customer_visits')
          .insert(payload)
          .select(_customerVisitSelect)
          .single();

      return CustomerVisit.fromJson(Map<String, dynamic>.from(inserted));
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('customer_visits_one_active_per_employee')) {
        throw const ValidationFailure(
          'Finish your current visit before starting another.',
        );
      }
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to start visit.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to start visit.');
    }
  }

  Future<CustomerVisit> completeCustomerVisit({
    required String companyId,
    required String actorEmployeeId,
    required CompleteCustomerVisitInput input,
  }) async {
    try {
      final existing = await fetchCustomerVisitById(
        companyId: companyId,
        visitId: input.visitId,
      );
      if (existing == null) {
        throw const ValidationFailure('Visit not found.');
      }
      if (!existing.isActive) {
        throw const ValidationFailure('This visit is already finished.');
      }

      final endedAt = DateTime.now().toUtc();
      final durationMinutes =
          endedAt.difference(existing.startedAt.toUtc()).inMinutes.clamp(0, 24 * 60);

      final payload = <String, dynamic>{
        'status': CustomerVisitStatus.completed.dbValue,
        'outcome': input.outcome.dbValue,
        'notes': _blankToNull(input.notes),
        'ended_at': endedAt.toIso8601String(),
        'duration_minutes': durationMinutes,
        'updated_by': actorEmployeeId,
      };
      if (input.signatureStoragePath != null &&
          input.signatureStoragePath!.trim().isNotEmpty) {
        payload['signature_storage_path'] = input.signatureStoragePath!.trim();
      }
      final gps = input.gps;
      if (gps != null) {
        payload['end_latitude'] = gps.latitude;
        payload['end_longitude'] = gps.longitude;
        payload['end_accuracy_meters'] = gps.accuracyMeters;
      }

      final updated = await _client
          .from('customer_visits')
          .update(payload)
          .eq('id', input.visitId)
          .eq('company_id', companyId)
          .select(_customerVisitSelect)
          .single();

      final visit = CustomerVisit.fromJson(Map<String, dynamic>.from(updated));

      // Mark linked schedule stop completed (plan ≠ activity, but keep markers).
      final scheduledId = visit.scheduledVisitId;
      if (scheduledId != null) {
        await setVisitStatus(
          companyId: companyId,
          visitId: scheduledId,
          actorEmployeeId: actorEmployeeId,
          status: VisitStatus.completed,
          emitNotification: false,
        );
      }

      final customerLabel = visit.customerName ?? 'a customer';
      await _events.publish(
        companyId: companyId,
        actorEmployeeId: actorEmployeeId,
        event: BusinessEvents.visitCompleted(
          visitId: visit.id,
          referenceType: 'customer_visit',
          summary:
              '${visit.employeeName ?? 'A sales rep'} completed a visit with $customerLabel (${input.outcome.label})',
          body:
              'Visit with $customerLabel — ${input.outcome.label.toLowerCase()}.',
          routeHint: RoutePaths.hubVisits,
          excludeEmployeeId: actorEmployeeId,
        ),
      );

      if (input.outcome == VisitOutcome.followUpRequired) {
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: actorEmployeeId,
          event: BusinessEvents.followUpRequired(
            visitId: visit.id,
            customerLabel: customerLabel,
            excludeEmployeeId: actorEmployeeId,
          ),
        );
      }

      return visit;
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to complete visit.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to complete visit.');
    }
  }

  Future<void> cancelCustomerVisit({
    required String companyId,
    required String actorEmployeeId,
    required String visitId,
    String? notes,
  }) async {
    try {
      await _client.from('customer_visits').update({
        'status': CustomerVisitStatus.cancelled.dbValue,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'notes': _blankToNull(notes),
        'updated_by': actorEmployeeId,
      }).eq('id', visitId).eq('company_id', companyId);
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to cancel visit.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to cancel visit.');
    }
  }

  /// Report foundation — completed / missed / conversion for a period.
  Future<({
    int completed,
    int missed,
    int scheduled,
    int withOrders,
    int withPayments,
    int ordersLinked,
    num collectionsAmount,
    List<({String employeeId, String name, int completed, int withOrders})>
        byRepresentative,
  })> fetchVisitReportMetrics({
    required String companyId,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final visits = await fetchCustomerVisits(
        companyId: companyId,
        from: from,
        to: to,
        status: CustomerVisitStatus.completed,
        limit: 2000,
      );
      final scheduled = await fetchVisits(
        companyId: companyId,
        from: from,
        to: to,
        pageSize: 2000,
      );

      final missed = scheduled.items
          .where((v) => v.status == VisitStatus.missed)
          .length;
      final planned = scheduled.items
          .where((v) =>
              v.status == VisitStatus.scheduled ||
              v.status == VisitStatus.completed ||
              v.status == VisitStatus.missed)
          .length;

      var withOrders = 0;
      var withPayments = 0;
      var ordersLinked = 0;
      num collectionsAmount = 0;
      final orderVisitIds = <String>{};
      final paymentVisitIds = <String>{};

      if (visits.isNotEmpty) {
        final ids = visits.map((v) => v.id).toList();
        final orderRows = await _client
            .from('orders')
            .select('visit_id')
            .eq('company_id', companyId)
            .inFilter('visit_id', ids)
            .isFilter('deleted_at', null);
        final paymentRows = await _client
            .from('payments')
            .select('visit_id, amount')
            .eq('company_id', companyId)
            .inFilter('visit_id', ids);

        for (final row in orderRows as List) {
          final visitId = (row as Map)['visit_id'] as String?;
          if (visitId == null) continue;
          orderVisitIds.add(visitId);
          ordersLinked++;
        }
        for (final row in paymentRows as List) {
          final visitId = (row as Map)['visit_id'] as String?;
          if (visitId == null) continue;
          paymentVisitIds.add(visitId);
          collectionsAmount += _asNum(row['amount']);
        }
        withOrders = orderVisitIds.length;
        withPayments = paymentVisitIds.length;
      }

      final byRep = <String, ({String name, int completed, int withOrders})>{};
      for (final visit in visits) {
        final existing = byRep[visit.employeeId];
        final name = visit.employeeName ?? 'Sales rep';
        final hasOrder = orderVisitIds.contains(visit.id);
        if (existing == null) {
          byRep[visit.employeeId] = (
            name: name,
            completed: 1,
            withOrders: hasOrder ? 1 : 0,
          );
        } else {
          byRep[visit.employeeId] = (
            name: existing.name,
            completed: existing.completed + 1,
            withOrders: existing.withOrders + (hasOrder ? 1 : 0),
          );
        }
      }

      return (
        completed: visits.length,
        missed: missed,
        scheduled: planned,
        withOrders: withOrders,
        withPayments: withPayments,
        ordersLinked: ordersLinked,
        collectionsAmount: collectionsAmount,
        byRepresentative: [
          for (final entry in byRep.entries)
            (
              employeeId: entry.key,
              name: entry.value.name,
              completed: entry.value.completed,
              withOrders: entry.value.withOrders,
            ),
        ]..sort((a, b) => b.completed.compareTo(a.completed)),
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure('Unable to load visit report metrics.');
    }
  }

  Future<List<CustomerVisit>> _enrichVisitLinkCounts({
    required String companyId,
    required List<CustomerVisit> visits,
  }) async {
    if (visits.isEmpty) return visits;
    final ids = visits.map((v) => v.id).toList();
    try {
      final orderRows = await _client
          .from('orders')
          .select('visit_id')
          .eq('company_id', companyId)
          .inFilter('visit_id', ids)
          .isFilter('deleted_at', null);
      final paymentRows = await _client
          .from('payments')
          .select('visit_id')
          .eq('company_id', companyId)
          .inFilter('visit_id', ids);

      final orderCounts = <String, int>{};
      final paymentCounts = <String, int>{};
      for (final row in orderRows as List) {
        final id = (row as Map)['visit_id'] as String?;
        if (id == null) continue;
        orderCounts[id] = (orderCounts[id] ?? 0) + 1;
      }
      for (final row in paymentRows as List) {
        final id = (row as Map)['visit_id'] as String?;
        if (id == null) continue;
        paymentCounts[id] = (paymentCounts[id] ?? 0) + 1;
      }

      return [
        for (final visit in visits)
          visit.copyWith(
            orderCount: orderCounts[visit.id] ?? visit.orderCount,
            paymentCount: paymentCounts[visit.id] ?? visit.paymentCount,
          ),
      ];
    } catch (_) {
      return visits;
    }
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  String? _minutesToTime(int? minutes) {
    if (minutes == null) return null;
    final h = (minutes ~/ 60).clamp(0, 23);
    final m = (minutes % 60).clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
