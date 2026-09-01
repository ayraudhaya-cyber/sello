import 'package:sello/data/repositories/visit_repository.dart';
import 'package:sello/services/reliability/sync_handler.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// Shared Reliability handler for Customer Visits — no parallel sync pipeline.
///
/// Maps queue operations onto [VisitRepository] mutations.
class CustomerVisitsSyncHandler implements SyncHandler {
  CustomerVisitsSyncHandler({
    required VisitRepository visits,
    required String Function() companyId,
    required String Function() actorEmployeeId,
  })  : _visits = visits,
        _companyId = companyId,
        _actorEmployeeId = actorEmployeeId;

  final VisitRepository _visits;
  final String Function() _companyId;
  final String Function() _actorEmployeeId;

  @override
  SyncDomain get domain => SyncDomain.customerVisits;

  @override
  Future<String?> process(SyncQueueItem item) async {
    final companyId = _companyId();
    final actorId = _actorEmployeeId();
    if (companyId.isEmpty || actorId.isEmpty) {
      throw StateError('No session available to sync visits.');
    }

    switch (item.operation) {
      case SyncOperation.create:
        return _start(companyId, actorId, item);
      case SyncOperation.complete:
        return _complete(companyId, actorId, item);
      case SyncOperation.cancel:
        return _cancel(companyId, actorId, item);
      case SyncOperation.update:
        // Notes / outcome amendments — complete is the primary path today.
        return _complete(companyId, actorId, item);
      case SyncOperation.upsert:
      case SyncOperation.delete:
        throw UnsupportedError(
          'Visit sync does not support ${item.operation.name}.',
        );
    }
  }

  Future<String?> _start(
    String companyId,
    String actorId,
    SyncQueueItem item,
  ) async {
    final payload = item.payload;
    final clientId = item.clientId;

    final existing = await _visits.fetchCustomerVisitByOfflineClientId(
      companyId: companyId,
      offlineClientId: clientId,
    );
    if (existing != null) return existing.id;

    final visit = await _visits.startCustomerVisit(
      companyId: companyId,
      actorEmployeeId: actorId,
      input: StartCustomerVisitInput(
        customerId: payload['customer_id'] as String,
        employeeId: payload['employee_id'] as String? ?? actorId,
        branchId: payload['branch_id'] as String?,
        scheduledVisitId: payload['scheduled_visit_id'] as String?,
        offlineClientId: clientId,
        gps: _gpsFromPayload(payload['gps']),
      ),
    );
    return visit.id;
  }

  Future<String?> _complete(
    String companyId,
    String actorId,
    SyncQueueItem item,
  ) async {
    final payload = item.payload;
    final visit = await _resolveVisit(companyId, item);
    if (visit == null) {
      throw StateError('Visit not found for complete sync.');
    }
    if (visit.isCompleted) return visit.id;

    final outcome = VisitOutcome.fromDb(payload['outcome'] as String?) ??
        VisitOutcome.noOrderToday;

    final completed = await _visits.completeCustomerVisit(
      companyId: companyId,
      actorEmployeeId: actorId,
      input: CompleteCustomerVisitInput(
        visitId: visit.id,
        outcome: outcome,
        notes: payload['notes'] as String?,
        gps: _gpsFromPayload(payload['gps']),
      ),
    );
    return completed.id;
  }

  Future<String?> _cancel(
    String companyId,
    String actorId,
    SyncQueueItem item,
  ) async {
    final visit = await _resolveVisit(companyId, item);
    if (visit == null) return item.entityId;
    if (!visit.isActive) return visit.id;

    await _visits.cancelCustomerVisit(
      companyId: companyId,
      actorEmployeeId: actorId,
      visitId: visit.id,
      notes: item.payload['notes'] as String?,
    );
    return visit.id;
  }

  Future<CustomerVisit?> _resolveVisit(
    String companyId,
    SyncQueueItem item,
  ) async {
    final payload = item.payload;
    final visitId = payload['visit_id'] as String? ?? item.entityId;
    final offlineId =
        payload['offline_client_id'] as String? ?? item.clientId;

    if (visitId != null &&
        visitId.isNotEmpty &&
        !visitId.startsWith('local:')) {
      final byId = await _visits.fetchCustomerVisitById(
        companyId: companyId,
        visitId: visitId,
      );
      if (byId != null) return byId;
    }

    return _visits.fetchCustomerVisitByOfflineClientId(
      companyId: companyId,
      offlineClientId: offlineId,
    );
  }

  static VisitGpsPoint? _gpsFromPayload(dynamic raw) {
    if (raw is! Map) return null;
    final lat = raw['latitude'];
    final lng = raw['longitude'];
    if (lat is! num || lng is! num) return null;
    return VisitGpsPoint(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracyMeters: (raw['accuracy_meters'] as num?)?.toDouble(),
    );
  }
}
