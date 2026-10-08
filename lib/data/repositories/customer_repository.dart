import 'package:sello/core/error/app_failure.dart';
import 'package:sello/shared/lifecycle/business_entity_lifecycle.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_receivable_adjustment.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerPageResult {
  const CustomerPageResult({required this.items, required this.hasMore});

  final List<CustomerSummary> items;
  final bool hasMore;
}

class CustomerRepository {
  CustomerRepository({SupabaseClient? client, BusinessEventBus? events})
    : _client = client ?? SupabaseService.client,
      _events = events ?? BusinessEventBus();

  final SupabaseClient _client;
  final BusinessEventBus _events;

  static const _select = '''
    id,
    company_id,
    branch_id,
    code,
    name,
    company_name,
    customer_type,
    phone,
    whatsapp,
    email,
    address_line1,
    city,
    tax_number,
    notes,
    credit_allowed,
    credit_limit,
    opening_balance,
    current_balance,
    wallet_balance,
    last_purchase_at,
    last_visit_at,
    next_visit_at,
    is_active,
    created_at,
    updated_at
  ''';

  Future<CustomerPageResult> fetchCustomers({
    String search = '',
    bool? isActive,
    CustomerType? customerType,
    bool owingOnly = false,
    String? orderBy,
    bool ascending = false,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('customers')
          .select(_select)
          .isFilter('deleted_at', null);

      if (search.trim().isNotEmpty) {
        final needle = search.trim();
        query = query.or(
          'name.ilike.%$needle%,'
          'phone.ilike.%$needle%,'
          'email.ilike.%$needle%,'
          'company_name.ilike.%$needle%,'
          'code.ilike.%$needle%,'
          'whatsapp.ilike.%$needle%',
        );
      }
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }
      if (customerType != null) {
        query = query.eq('customer_type', customerType.dbValue);
      }
      if (owingOnly) {
        query = query.gt('current_balance', 0);
      }

      final response = await query
          .order(
            orderBy ?? (owingOnly ? 'current_balance' : 'updated_at'),
            ascending: orderBy == null ? false : ascending,
            nullsFirst: false,
          )
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final items = (response as List)
          .map(
            (row) => CustomerSummary.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      return CustomerPageResult(
        items: items,
        hasMore: items.length == pageSize,
      );
    } on PostgrestException catch (error) {
      throw AuthFailure(
        error.message.trim().isEmpty
            ? 'Unable to load customers. Please try again.'
            : error.message,
      );
    } catch (error) {
      throw const UnexpectedFailure(
        'Unable to load customers. Please try again.',
      );
    }
  }

  /// Active, non-deleted customers. A head count — no customer rows returned.
  Future<int> countActiveCustomers() async {
    try {
      return await _client
          .from('customers')
          .count()
          .isFilter('deleted_at', null)
          .eq('is_active', true);
    } on PostgrestException catch (error) {
      throw AuthFailure(
        error.message.trim().isEmpty
            ? 'Unable to count customers. Please try again.'
            : error.message,
      );
    } catch (error) {
      throw const UnexpectedFailure(
        'Unable to count customers. Please try again.',
      );
    }
  }

  Future<CustomerSummary?> fetchById(String customerId) async {
    try {
      final row = await _client
          .from('customers')
          .select(_select)
          .eq('id', customerId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return CustomerSummary.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw AuthFailure(
        error.message.trim().isEmpty
            ? 'Unable to load that customer.'
            : error.message,
      );
    } catch (error) {
      throw const UnexpectedFailure('Unable to load that customer.');
    }
  }

  Future<String> upsertCustomer({
    required CustomerUpsertInput input,
    required String companyId,
    required String employeeId,
    String? branchId,
  }) async {
    try {
      final isNew = input.customerId == null;
      final payload = <String, dynamic>{
        'company_id': companyId,
        'branch_id': branchId,
        'name': input.name.trim(),
        'code': _nullIfBlank(input.code),
        'company_name': _nullIfBlank(input.companyName),
        'customer_type': input.customerType.dbValue,
        'phone': _nullIfBlank(input.phone),
        'whatsapp': _nullIfBlank(input.whatsapp),
        'email': _nullIfBlank(input.email),
        'address_line1': _nullIfBlank(input.addressLine1),
        'city': _nullIfBlank(input.city),
        'tax_number': _nullIfBlank(input.taxNumber),
        'notes': _nullIfBlank(input.notes),
        'credit_allowed': input.creditAllowed,
        'credit_limit': input.creditLimit,
        'is_active': input.isActive,
        'updated_by': employeeId,
      };

      if (isNew) {
        payload['created_by'] = employeeId;
        // Opening balance is create-only; edits must not rewrite outstanding.
        payload['opening_balance'] = input.openingBalance;
        payload['current_balance'] = input.openingBalance;
        payload['wallet_balance'] = 0;

        final inserted = await _client
            .from('customers')
            .insert(payload)
            .select('id')
            .single();
        final customerId = inserted['id'] as String;
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: employeeId,
          event: BusinessEvents.customerCreated(
            customerId: customerId,
            name: input.name.trim(),
            excludeEmployeeId: employeeId,
          ),
        );
        return customerId;
      }

      await _client
          .from('customers')
          .update(payload)
          .eq('id', input.customerId!);
      return input.customerId!;
    } on PostgrestException catch (error) {
      throw ValidationFailure(mapCustomerSaveError(error.message));
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Lets a completed field sale leave a balance that can be collected later.
  ///
  /// Must set [employeeId] as `updated_by` so the customers UPDATE policy
  /// (`updated_by = current_employee_id()`) can accept the new row.
  Future<void> allowOnAccount({
    required String customerId,
    required String employeeId,
  }) async {
    try {
      await _client
          .from('customers')
          .update(customerAllowOnAccountPatch(employeeId: employeeId))
          .eq('id', customerId);
    } on PostgrestException catch (error) {
      throw ValidationFailure(mapCustomerSaveError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw const UnexpectedFailure('Unable to update this customer.');
    }
  }

  Future<bool> _referenced(String table, String column, String id) async {
    try {
      final rows = await _client
          .from(table)
          .select('id')
          .eq(column, id)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> archiveCustomer({
    required String customerId,
    required String employeeId,
    required bool archived,
  }) async {
    try {
      final existing = await _client
          .from('customers')
          .select('id, is_active, deleted_at')
          .eq('id', customerId)
          .maybeSingle();
      if (existing == null) {
        throw const ValidationFailure('Customer not found.');
      }
      if (existing['deleted_at'] != null) {
        throw const ValidationFailure(
          'This customer has been permanently deleted.',
        );
      }

      await _client
          .from('customers')
          .update({'is_active': !archived, 'updated_by': employeeId})
          .eq('id', customerId);

      if (archived) {
        final row = await _client
            .from('customers')
            .select('company_id, name')
            .eq('id', customerId)
            .maybeSingle();
        final companyId = row?['company_id'] as String?;
        final name = row?['name'] as String? ?? 'Customer';
        if (companyId != null) {
          await _events.publish(
            companyId: companyId,
            actorEmployeeId: employeeId,
            event: BusinessEvents.customerArchived(
              customerId: customerId,
              name: name,
              excludeEmployeeId: employeeId,
            ),
          );
        }
      }
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(mapCustomerSaveError(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Soft-delete an archived customer so history (orders) stays intact.
  Future<void> permanentlyDeleteCustomer({
    required String customerId,
    required String employeeId,
  }) async {
    try {
      final existing = await _client
          .from('customers')
          .select('id, is_active, deleted_at')
          .eq('id', customerId)
          .maybeSingle();
      if (existing == null) {
        throw const ValidationFailure('Customer not found.');
      }
      if (existing['deleted_at'] != null) {
        throw const ValidationFailure(
          'This customer has already been permanently deleted.',
        );
      }
      final used =
          await _referenced('orders', 'customer_id', customerId) ||
          await _referenced('payments', 'customer_id', customerId) ||
          await _referenced('customer_visits', 'customer_id', customerId) ||
          await _referenced('scheduled_visits', 'customer_id', customerId) ||
          await _referenced('cheques', 'customer_id', customerId);
      final decision = BusinessEntityLifecycle.permanentDelete(
        isActive: existing['is_active'] == true,
        hasHistoricalUse: used,
        noun: 'customer',
      );
      if (!decision.allowed) {
        throw ValidationFailure(decision.message!);
      }

      await _client
          .from('customers')
          .update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'is_active': false,
            'updated_by': employeeId,
          })
          .eq('id', customerId);
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(mapCustomerSaveError(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<String> recordOpeningBalanceAdjustment({
    required String customerId,
    required num amount,
    DateTime? recognizedAt,
    String? notes,
    String? referenceNumber,
  }) async {
    try {
      final result = await _client.rpc(
        'record_opening_balance_adjustment',
        params: {
          'p_customer_id': customerId,
          'p_amount': amount,
          'p_notes': _nullIfBlank(notes),
          'p_recognized_at': recognizedAt?.toUtc().toIso8601String(),
          'p_reference_number': _nullIfBlank(referenceNumber),
        },
      );
      return result is String ? result : result.toString();
    } on PostgrestException catch (error) {
      throw ValidationFailure(mapOpeningBalanceError(error.message));
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure(
        'Unable to add this opening balance. Please try again.',
      );
    }
  }

  Future<String> correctOpeningBalanceAdjustment({
    required String adjustmentId,
    required num amount,
    required String reason,
    String? notes,
    String? referenceNumber,
    DateTime? recognizedAt,
  }) async {
    try {
      final result = await _client.rpc(
        'correct_opening_balance_adjustment',
        params: {
          'p_adjustment_id': adjustmentId,
          'p_amount': amount,
          'p_reason': reason.trim(),
          'p_notes': _nullIfBlank(notes),
          'p_reference_number': _nullIfBlank(referenceNumber),
          'p_recognized_at': recognizedAt?.toUtc().toIso8601String(),
        },
      );
      return result is String ? result : result.toString();
    } on PostgrestException catch (error) {
      throw ValidationFailure(mapOpeningBalanceError(error.message));
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const UnexpectedFailure(
        'Unable to correct this opening balance. Please try again.',
      );
    }
  }

  Future<List<CustomerReceivableAdjustment>> fetchOpeningBalanceAdjustments(
    String customerId,
  ) async {
    try {
      final rows = await _client
          .from('customer_receivable_adjustments')
          .select(
            'id, adjustment_number, amount, recognized_at, notes, '
            'reference_number',
          )
          .eq('customer_id', customerId)
          .eq('kind', 'opening_balance')
          .isFilter('reversed_at', null)
          .order('recognized_at');

      final paid = <String, num>{};
      final ids = [
        for (final row in rows as List) (row as Map)['id'] as String?,
      ].whereType<String>().toList();
      if (ids.isNotEmpty) {
        final allocRows = await _client
            .from('payment_allocations')
            .select(
              'receivable_adjustment_id, amount, payments!inner(status, deleted_at)',
            )
            .inFilter('receivable_adjustment_id', ids)
            .eq('payments.status', 'completed')
            .isFilter('payments.deleted_at', null);
        for (final raw in allocRows as List) {
          final map = Map<String, dynamic>.from(raw as Map);
          final id = map['receivable_adjustment_id'] as String?;
          if (id == null) continue;
          paid[id] = (paid[id] ?? 0) + _asNum(map['amount']);
        }
      }

      return [
        for (final row in rows as List)
          () {
            final map = Map<String, dynamic>.from(row as Map);
            final id = map['id'] as String? ?? '';
            final amount = _asNum(map['amount']);
            return CustomerReceivableAdjustment.fromJson(
              map,
              remaining: (amount - (paid[id] ?? 0)).clamp(0, double.infinity),
            );
          }(),
      ];
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('reversed_at')) {
        return _fetchOpeningBalanceAdjustmentsLegacy(customerId);
      }
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load opening balances.'
            : error.message,
      );
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw const UnexpectedFailure('Unable to load opening balances.');
    }
  }

  Future<List<CustomerReceivableAdjustment>>
  _fetchOpeningBalanceAdjustmentsLegacy(String customerId) async {
    final rows = await _client
        .from('customer_receivable_adjustments')
        .select(
          'id, adjustment_number, amount, recognized_at, notes, '
          'reference_number',
        )
        .eq('customer_id', customerId)
        .eq('kind', 'opening_balance')
        .order('recognized_at');
    return [
      for (final row in rows as List)
        () {
          final map = Map<String, dynamic>.from(row as Map);
          return CustomerReceivableAdjustment.fromJson(
            map,
            remaining: _asNum(map['amount']),
          );
        }(),
    ];
  }

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  String? _nullIfBlank(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Customers UPDATE RLS requires `updated_by` to be the signed-in employee.
Map<String, dynamic> customerAllowOnAccountPatch({required String employeeId}) {
  return {'credit_allowed': true, 'updated_by': employeeId};
}

String mapCustomerSaveError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('row-level security') ||
      lower.contains('violates row-level')) {
    return 'Unable to save this customer.';
  }
  if (lower.contains('customers_company_code_active_key') ||
      lower.contains('code')) {
    return 'A customer with this code already exists.';
  }
  if (lower.contains('email')) {
    return 'Enter a valid email address.';
  }
  if (message.trim().isEmpty) {
    return 'Unable to save this customer. Please try again.';
  }
  return message;
}

String mapOpeningBalanceError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('only owner or manager')) {
    if (lower.contains('correct')) {
      return 'Only Owner or Manager can correct an opening balance.';
    }
    return 'Only Owner or Manager can add an opening balance.';
  }
  if (lower.contains('inactive')) {
    return 'This customer is inactive.';
  }
  if (lower.contains('greater than zero') || lower.contains('amount must')) {
    return 'Enter an opening balance greater than zero.';
  }
  if (lower.contains('future')) {
    return 'As-of date cannot be in the future.';
  }
  if (lower.contains('too long')) {
    return 'Old invoice / reference is too long.';
  }
  if (lower.contains('not found')) {
    return 'Customer not found.';
  }
  if (message.trim().isEmpty) {
    return 'Unable to add this opening balance. Please try again.';
  }
  return message;
}
