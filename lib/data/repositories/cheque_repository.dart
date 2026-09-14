import 'dart:typed_data';

import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChequePageResult {
  const ChequePageResult({required this.items, required this.hasMore});

  final List<ChequeSummary> items;
  final bool hasMore;
}

class ChequeRepository {
  ChequeRepository({
    SupabaseClient? client,
    BusinessEventBus? events,
    MediaStorageService? storage,
  })  : _client = client ?? SupabaseService.client,
        _events = events ?? BusinessEventBus(),
        _storage = storage ?? MediaStorageService();

  final SupabaseClient _client;
  final BusinessEventBus _events;
  final MediaStorageService _storage;

  static const _listSelect = '''
    id,
    company_id,
    customer_id,
    employee_id,
    cheque_number_label,
    amount,
    bank_name,
    cheque_number,
    holder_name,
    cheque_date,
    collection_date,
    photo_path,
    notes,
    status,
    visit_id,
    payment_id,
    applied_ar_amount,
    applied_wallet_amount,
    balance_applied_at,
    balance_reversed_at,
    collected_at,
    deposited_at,
    cleared_at,
    bounced_at,
    cancelled_at,
    bounce_reason,
    cancel_reason,
    created_at,
    customers!customer_id (
      id,
      name,
      phone
    ),
    employees!employee_id (
      id,
      full_name
    )
  ''';

  Future<ChequePageResult> fetchCheques({
    String search = '',
    ChequeStatus? status,
    bool? pendingApprovalOnly,
    bool? appliedCollectedOnly,
    String? customerId,
    String? bankName,
    DateTime? chequeDateFrom,
    DateTime? chequeDateTo,
    DateTime? collectionDateFrom,
    DateTime? collectionDateTo,
    bool dueToday = false,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('cheques')
          .select(_listSelect)
          .isFilter('deleted_at', null);

      if (pendingApprovalOnly == true) {
        query = query
            .eq('status', ChequeStatus.collected.dbValue)
            .isFilter('balance_applied_at', null);
      } else if (appliedCollectedOnly == true) {
        query = query
            .eq('status', ChequeStatus.collected.dbValue)
            .not('balance_applied_at', 'is', null);
      } else if (status != null) {
        query = query.eq('status', status.dbValue);
      }
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      if (bankName != null && bankName.trim().isNotEmpty) {
        query = query.ilike('bank_name', '%${bankName.trim()}%');
      }
      if (chequeDateFrom != null) {
        query = query.gte('cheque_date', _dateOnly(chequeDateFrom));
      }
      if (chequeDateTo != null) {
        query = query.lte('cheque_date', _dateOnly(chequeDateTo));
      }
      if (collectionDateFrom != null) {
        query = query.gte('collection_date', _dateOnly(collectionDateFrom));
      }
      if (collectionDateTo != null) {
        query = query.lte('collection_date', _dateOnly(collectionDateTo));
      }
      if (dueToday) {
        final today = _dateOnly(DateTime.now());
        query = query
            .eq('status', ChequeStatus.awaitingCollection.dbValue)
            .or('collection_date.eq.$today,and(collection_date.is.null,cheque_date.lte.$today)');
      }

      final needle = search.trim();
      if (needle.isNotEmpty) {
        final customerRows = await _client
            .from('customers')
            .select('id')
            .isFilter('deleted_at', null)
            .or(
              'name.ilike.%$needle%,phone.ilike.%$needle%,code.ilike.%$needle%',
            )
            .limit(50);
        final customerIds = (customerRows as List)
            .map((row) => row['id'] as String)
            .toList();
        if (customerIds.isEmpty) {
          query = query.or(
            'cheque_number.ilike.%$needle%,bank_name.ilike.%$needle%,holder_name.ilike.%$needle%,cheque_number_label.ilike.%$needle%',
          );
        } else {
          final idList = customerIds.join(',');
          query = query.or(
            'customer_id.in.($idList),cheque_number.ilike.%$needle%,bank_name.ilike.%$needle%,holder_name.ilike.%$needle%,cheque_number_label.ilike.%$needle%',
          );
        }
      }

      final from = page * pageSize;
      final to = from + pageSize;
      final rows = await query
          .order('created_at', ascending: false)
          .range(from, to);

      final items = (rows as List)
          .map((row) => ChequeSummary.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      final hasMore = items.length > pageSize;
      return ChequePageResult(
        items: hasMore ? items.sublist(0, pageSize) : items,
        hasMore: hasMore,
      );
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<ChequeSummary?> fetchById(String id) async {
    try {
      final row = await _client
          .from('cheques')
          .select(_listSelect)
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return ChequeSummary.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<ChequeDashboardStats> fetchDashboardStats() async {
    try {
      final result = await _client.rpc('cheque_dashboard_stats');
      if (result is Map<String, dynamic>) {
        return ChequeDashboardStats.fromJson(result);
      }
      if (result is Map) {
        return ChequeDashboardStats.fromJson(Map<String, dynamic>.from(result));
      }
      return const ChequeDashboardStats();
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<String> uploadChequePhoto({
    required String companyId,
    required String chequeKey,
    required Uint8List bytes,
    required String contentType,
  }) {
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
            ? 'webp'
            : MediaConstants.jpegExtension;
    final path = '$companyId/$chequeKey/cheque.$ext';
    return _storage.upload(
      bucket: MediaConstants.chequeImagesBucket,
      path: path,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<String?> signChequePhoto(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _storage.createSignedUrl(
      bucket: MediaConstants.chequeImagesBucket,
      path: path,
    );
  }

  Future<ChequeSummary> createCheque(CreateChequeInput input) async {
    if (input.amount <= 0) {
      throw const ValidationFailure('Enter a cheque amount greater than zero.');
    }
    if (input.markCollected && input.collectionDate == null) {
      throw const ValidationFailure(
        'Collection date is required when the cheque is collected.',
      );
    }

    try {
      final result = await _client.rpc(
        'create_cheque',
        params: {
          'p_customer_id': input.customerId,
          'p_amount': input.amount,
          'p_bank_name': input.bankName.trim(),
          'p_cheque_number': input.chequeNumber.trim(),
          'p_holder_name': input.holderName.trim(),
          'p_cheque_date': _dateOnly(input.chequeDate),
          'p_collection_date': input.collectionDate == null
              ? null
              : _dateOnly(input.collectionDate!),
          'p_photo_path': input.photoPath,
          'p_notes': input.notes,
          'p_allocations': [
            for (final alloc in input.allocations) alloc.toJson(),
          ],
          'p_visit_id': input.visitId,
          'p_mark_collected': input.markCollected,
        },
      );
      final chequeId = result is String ? result : result.toString();
      final detail = await fetchById(chequeId);
      if (detail == null) {
        throw const UnexpectedFailure('Cheque was created but could not be loaded.');
      }
      await _notifyCreated(detail);
      return detail;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapChequeError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<ChequeSummary> collectCheque(CollectChequeInput input) async {
    try {
      await _client.rpc(
        'collect_cheque',
        params: {
          'p_cheque_id': input.chequeId,
          'p_collection_date': _dateOnly(input.collectionDate),
          'p_allocations': [
            for (final alloc in input.allocations) alloc.toJson(),
          ],
          'p_photo_path': input.photoPath,
          'p_notes': input.notes,
        },
      );
      final detail = await fetchById(input.chequeId);
      if (detail == null) {
        throw const UnexpectedFailure('Unable to load collected cheque.');
      }
      await _notifyStatus(detail, title: 'Cheque collected');
      return detail;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapChequeError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<ChequeSummary> depositCheque(String chequeId) async {
    return _transition(
      rpc: 'deposit_cheque',
      params: {'p_cheque_id': chequeId},
      chequeId: chequeId,
      title: 'Cheque deposited',
    );
  }

  Future<ChequeSummary> clearCheque(String chequeId) async {
    return _transition(
      rpc: 'clear_cheque',
      params: {'p_cheque_id': chequeId},
      chequeId: chequeId,
      title: 'Cheque cleared',
    );
  }

  Future<ChequeSummary> approveChequeCollection(String chequeId) async {
    return _transition(
      rpc: 'approve_cheque_collection',
      params: {'p_cheque_id': chequeId},
      chequeId: chequeId,
      title: 'Cheque collection approved',
    );
  }

  Future<ChequeSummary> bounceCheque(String chequeId, {String? reason}) async {
    return _transition(
      rpc: 'bounce_cheque',
      params: {'p_cheque_id': chequeId, 'p_reason': reason},
      chequeId: chequeId,
      title: 'Cheque bounced',
    );
  }

  Future<ChequeSummary> cancelCheque(String chequeId, {String? reason}) async {
    return _transition(
      rpc: 'cancel_cheque',
      params: {'p_cheque_id': chequeId, 'p_reason': reason},
      chequeId: chequeId,
      title: 'Cheque cancelled',
    );
  }

  Future<ChequeSummary> _transition({
    required String rpc,
    required Map<String, dynamic> params,
    required String chequeId,
    required String title,
  }) async {
    try {
      await _client.rpc(rpc, params: params);
      final detail = await fetchById(chequeId);
      if (detail == null) {
        throw const UnexpectedFailure('Unable to load cheque.');
      }
      await _notifyStatus(detail, title: title);
      return detail;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapChequeError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> _notifyCreated(ChequeSummary cheque) async {
    try {
      await _events.publish(
        companyId: cheque.companyId,
        event: BusinessEvents.chequeRecorded(
          chequeId: cheque.id,
          customerName: cheque.customerName ?? 'a customer',
          amountLabel: cheque.amount.toStringAsFixed(2),
          awaitingCollection:
              cheque.status == ChequeStatus.awaitingCollection,
          pendingApproval: cheque.isPendingApproval,
        ),
        actorEmployeeId: cheque.employeeId,
        actorName: cheque.employeeName,
      );
    } catch (_) {}
  }

  Future<void> _notifyStatus(ChequeSummary cheque, {required String title}) async {
    try {
      await _events.publish(
        companyId: cheque.companyId,
        event: BusinessEvents.chequeStatusChanged(
          chequeId: cheque.id,
          customerName: cheque.customerName ?? 'a customer',
          amountLabel: cheque.amount.toStringAsFixed(2),
          title: title,
          statusLabel: cheque.displayLabel,
        ),
        actorEmployeeId: cheque.employeeId,
        actorName: cheque.employeeName,
      );
    } catch (_) {}
  }

  static String _dateOnly(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _mapChequeError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('amount')) return message;
    if (lower.contains('forbidden') || lower.contains('only owner')) {
      return message;
    }
    if (lower.contains('session context')) {
      return 'Your session expired. Sign in again.';
    }
    return message.trim().isEmpty ? 'Unable to update cheque.' : message;
  }
}
