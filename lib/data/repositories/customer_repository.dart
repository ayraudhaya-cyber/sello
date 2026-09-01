import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/customer_upsert_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerPageResult {
  const CustomerPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<CustomerSummary> items;
  final bool hasMore;
}

class CustomerRepository {
  CustomerRepository({
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

      final response = await query
          .order('updated_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final items = (response as List)
          .map((row) => CustomerSummary.fromJson(Map<String, dynamic>.from(row)))
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
      throw ValidationFailure(_mapCustomerError(error.message));
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
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

      await _client.from('customers').update({
        'is_active': !archived,
        'updated_by': employeeId,
      }).eq('id', customerId);

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
      throw ValidationFailure(_mapCustomerError(error.message));
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
      if (existing['is_active'] == true) {
        throw const ValidationFailure(
          'Archive the customer before permanently deleting them.',
        );
      }

      await _client.from('customers').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': false,
        'updated_by': employeeId,
      }).eq('id', customerId);
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapCustomerError(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  String? _nullIfBlank(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _mapCustomerError(String message) {
    final lower = message.toLowerCase();
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
}
