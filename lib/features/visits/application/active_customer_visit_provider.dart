import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/reliability/offline_client_ids.dart';
import 'package:sello/services/reliability/reliability_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/visits/visit_gps_service.dart';
import 'package:sello/shared/models/customer_visit.dart';
import 'package:sello/shared/models/reliability/sync_models.dart';

/// Active operational visit for the signed-in sales rep (one at a time).
///
/// Online: mutates via [VisitRepository]. Offline: enqueues through the shared
/// Reliability SyncEngine (no visit-specific sync pipeline).
final activeCustomerVisitProvider =
    AsyncNotifierProvider<ActiveCustomerVisitNotifier, CustomerVisit?>(
  ActiveCustomerVisitNotifier.new,
);

class ActiveCustomerVisitNotifier extends AsyncNotifier<CustomerVisit?> {
  @override
  Future<CustomerVisit?> build() async {
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous?.employee.id != next?.employee.id) {
        Future.microtask(reload);
      }
    });
    return _load();
  }

  Future<CustomerVisit?> _load() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;
    return ref.read(visitRepositoryProvider).fetchActiveCustomerVisit(
          companyId: session.company.id,
          employeeId: session.employee.id,
        );
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<CustomerVisit> startVisit({
    required String customerId,
    String? scheduledVisitId,
    String? branchId,
    String? customerName,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      throw const ValidationFailure('Sign in to start a visit.');
    }

    final clientId = OfflineClientIds.create();
    final gps = await VisitGpsService.captureOnce();
    final online =
        ref.read(connectivityServiceProvider).snapshot.transportOnline;

    final input = StartCustomerVisitInput(
      customerId: customerId,
      employeeId: session.employee.id,
      branchId: branchId ?? session.employee.branchId,
      scheduledVisitId: scheduledVisitId,
      gps: gps,
      offlineClientId: clientId,
    );

    if (!online) {
      await ref.read(syncEngineProvider).enqueue(
            domain: SyncDomain.customerVisits,
            operation: SyncOperation.create,
            clientId: clientId,
            companyId: session.company.id,
            payload: {
              'customer_id': customerId,
              'employee_id': session.employee.id,
              'branch_id': input.branchId,
              'scheduled_visit_id': scheduledVisitId,
              'offline_client_id': clientId,
              if (gps != null) 'gps': gps.toJson(),
            },
          );

      final optimistic = CustomerVisit(
        id: 'local:$clientId',
        companyId: session.company.id,
        customerId: customerId,
        employeeId: session.employee.id,
        branchId: input.branchId,
        scheduledVisitId: scheduledVisitId,
        status: CustomerVisitStatus.inProgress,
        startedAt: DateTime.now(),
        customerName: customerName,
        employeeName: session.displayName,
        startLatitude: gps?.latitude,
        startLongitude: gps?.longitude,
        offlineClientId: clientId,
        pendingSync: true,
      );
      state = AsyncData(optimistic);
      return optimistic;
    }

    try {
      final visit = await ref.read(visitRepositoryProvider).startCustomerVisit(
            companyId: session.company.id,
            actorEmployeeId: session.employee.id,
            input: input,
          );
      state = AsyncData(visit);
      return visit;
    } on AppFailure {
      rethrow;
    } catch (_) {
      // Network blip after connectivity said online — queue safely.
      await ref.read(syncEngineProvider).enqueue(
            domain: SyncDomain.customerVisits,
            operation: SyncOperation.create,
            clientId: clientId,
            companyId: session.company.id,
            payload: {
              'customer_id': customerId,
              'employee_id': session.employee.id,
              'branch_id': input.branchId,
              'scheduled_visit_id': scheduledVisitId,
              'offline_client_id': clientId,
              if (gps != null) 'gps': gps.toJson(),
            },
          );
      final optimistic = CustomerVisit(
        id: 'local:$clientId',
        companyId: session.company.id,
        customerId: customerId,
        employeeId: session.employee.id,
        branchId: input.branchId,
        scheduledVisitId: scheduledVisitId,
        status: CustomerVisitStatus.inProgress,
        startedAt: DateTime.now(),
        customerName: customerName,
        employeeName: session.displayName,
        startLatitude: gps?.latitude,
        startLongitude: gps?.longitude,
        offlineClientId: clientId,
        pendingSync: true,
      );
      state = AsyncData(optimistic);
      return optimistic;
    }
  }

  Future<CustomerVisit> completeVisit({
    required VisitOutcome outcome,
    String? notes,
    String? signatureStoragePath,
  }) async {
    final session = ref.read(currentSessionProvider);
    final current = state.valueOrNull;
    if (session == null || current == null) {
      throw const ValidationFailure('No active visit to complete.');
    }

    // End GPS must not stall checkout — 2s max, then complete without coords.
    final gps = await VisitGpsService.captureOnceQuick();
    final online =
        ref.read(connectivityServiceProvider).snapshot.transportOnline;
    final offlineKey = current.offlineClientId ??
        (current.isLocalOnly ? current.id.replaceFirst('local:', '') : null);

    if (!online || current.pendingSync || current.isLocalOnly) {
      final clientId = OfflineClientIds.create();
      await ref.read(syncEngineProvider).enqueue(
            domain: SyncDomain.customerVisits,
            operation: SyncOperation.complete,
            clientId: clientId,
            companyId: session.company.id,
            entityId: current.isLocalOnly ? null : current.id,
            payload: {
              'visit_id': current.id,
              if (offlineKey != null) 'offline_client_id': offlineKey,
              'outcome': outcome.dbValue,
              if (notes != null) 'notes': notes,
              if (signatureStoragePath != null)
                'signature_storage_path': signatureStoragePath,
              if (gps != null) 'gps': gps.toJson(),
            },
          );

      final ended = DateTime.now();
      final completed = current.copyWith(
        status: CustomerVisitStatus.completed,
        outcome: outcome,
        notes: notes,
        endedAt: ended,
        durationMinutes: ended.difference(current.startedAt).inMinutes,
        endLatitude: gps?.latitude,
        endLongitude: gps?.longitude,
        signatureStoragePath: signatureStoragePath,
        pendingSync: true,
      );
      state = const AsyncData(null);
      return completed;
    }

    try {
      final visit = await ref.read(visitRepositoryProvider).completeCustomerVisit(
            companyId: session.company.id,
            actorEmployeeId: session.employee.id,
            input: CompleteCustomerVisitInput(
              visitId: current.id,
              outcome: outcome,
              notes: notes,
              gps: gps,
              signatureStoragePath: signatureStoragePath,
            ),
          );
      state = const AsyncData(null);
      return visit;
    } catch (_) {
      final clientId = OfflineClientIds.create();
      await ref.read(syncEngineProvider).enqueue(
            domain: SyncDomain.customerVisits,
            operation: SyncOperation.complete,
            clientId: clientId,
            companyId: session.company.id,
            entityId: current.id,
            payload: {
              'visit_id': current.id,
              if (offlineKey != null) 'offline_client_id': offlineKey,
              'outcome': outcome.dbValue,
              if (notes != null) 'notes': notes,
              if (signatureStoragePath != null)
                'signature_storage_path': signatureStoragePath,
              if (gps != null) 'gps': gps.toJson(),
            },
          );
      state = const AsyncData(null);
      return current.copyWith(
        status: CustomerVisitStatus.completed,
        outcome: outcome,
        notes: notes,
        endedAt: DateTime.now(),
        signatureStoragePath: signatureStoragePath,
        pendingSync: true,
      );
    }
  }

  Future<void> cancelVisit({String? notes}) async {
    final session = ref.read(currentSessionProvider);
    final current = state.valueOrNull;
    if (session == null || current == null) return;

    final online =
        ref.read(connectivityServiceProvider).snapshot.transportOnline;
    final offlineKey = current.offlineClientId ??
        (current.isLocalOnly ? current.id.replaceFirst('local:', '') : null);

    if (!online || current.pendingSync || current.isLocalOnly) {
      await ref.read(syncEngineProvider).enqueue(
            domain: SyncDomain.customerVisits,
            operation: SyncOperation.cancel,
            clientId: OfflineClientIds.create(),
            companyId: session.company.id,
            entityId: current.isLocalOnly ? null : current.id,
            payload: {
              'visit_id': current.id,
              if (offlineKey != null) 'offline_client_id': offlineKey,
              if (notes != null) 'notes': notes,
            },
          );
      state = const AsyncData(null);
      return;
    }

    await ref.read(visitRepositoryProvider).cancelCustomerVisit(
          companyId: session.company.id,
          actorEmployeeId: session.employee.id,
          visitId: current.id,
          notes: notes,
        );
    state = const AsyncData(null);
  }
}
