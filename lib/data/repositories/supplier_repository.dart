import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/supplier_summary.dart';
import 'package:sello/shared/models/supplier_upsert_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupplierPageResult {
  const SupplierPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<SupplierSummary> items;
  final bool hasMore;
}

/// Shared procurement repository — Hub today; future POs / GRN / payments.
class SupplierRepository {
  SupplierRepository({
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
    contact_name,
    phone,
    whatsapp,
    email,
    address_line1,
    address_line2,
    city,
    state,
    postal_code,
    country,
    tax_number,
    category,
    payment_terms,
    bank_name,
    bank_account,
    notes,
    credit_limit,
    opening_balance,
    current_balance,
    last_purchase_at,
    lead_time_days,
    is_active,
    created_at,
    updated_at
  ''';

  Future<SupplierDashboardStats> fetchDashboardStats({
    required String companyId,
  }) async {
    try {
      final rows = await _client
          .from('suppliers')
          .select('is_active, created_at')
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      final cutoff =
          DateTime.now().toUtc().subtract(const Duration(days: 30));
      var total = 0;
      var active = 0;
      var recentlyAdded = 0;

      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        total++;
        if (row['is_active'] == true) active++;
        final created = row['created_at'] as String?;
        if (created != null) {
          final at = DateTime.tryParse(created);
          if (at != null && !at.isBefore(cutoff)) recentlyAdded++;
        }
      }

      return SupplierDashboardStats(
        total: total,
        active: active,
        recentlyAdded: recentlyAdded,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load supplier stats.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load supplier stats.');
    }
  }

  Future<SupplierPageResult> fetchSuppliers({
    required String companyId,
    String search = '',
    bool? isActive,
    String? category,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('suppliers')
          .select(_select)
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      if (search.trim().isNotEmpty) {
        final needle = search.trim();
        query = query.or(
          'name.ilike.%$needle%,'
          'contact_name.ilike.%$needle%,'
          'phone.ilike.%$needle%,'
          'email.ilike.%$needle%,'
          'code.ilike.%$needle%,'
          'whatsapp.ilike.%$needle%',
        );
      }
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }
      if (category != null && category.trim().isNotEmpty) {
        query = query.eq('category', category.trim());
      }

      final response = await query
          .order('updated_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final items = (response as List)
          .map(
            (row) =>
                SupplierSummary.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();

      return SupplierPageResult(
        items: items,
        hasMore: items.length == pageSize,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load suppliers. Please try again.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure(
        'Unable to load suppliers. Please try again.',
      );
    }
  }

  /// Active suppliers for future PO / product sourcing pickers.
  Future<List<SupplierSummary>> fetchActiveSuppliers({
    required String companyId,
    String search = '',
    int limit = 50,
  }) async {
    final result = await fetchSuppliers(
      companyId: companyId,
      search: search,
      isActive: true,
      page: 0,
      pageSize: limit,
    );
    return result.items;
  }

  Future<SupplierSummary?> fetchById({
    required String companyId,
    required String supplierId,
  }) async {
    try {
      final row = await _client
          .from('suppliers')
          .select(_select)
          .eq('company_id', companyId)
          .eq('id', supplierId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (row == null) return null;
      return SupplierSummary.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load that supplier.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load that supplier.');
    }
  }

  /// Products where this supplier is the preferred / primary source.
  Future<List<SupplierProductLink>> fetchProductsForSupplier({
    required String companyId,
    required String supplierId,
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from('products')
          .select('''
            id,
            name,
            sku,
            unit_label,
            cost_price,
            selling_price,
            is_active,
            categories (name),
            inventory (quantity)
          ''')
          .eq('company_id', companyId)
          .eq('preferred_supplier_id', supplierId)
          .isFilter('deleted_at', null)
          .order('name')
          .limit(limit);

      return (rows as List)
          .map(
            (row) => SupplierProductLink.fromQueryRow(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load products for this supplier.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure(
        'Unable to load products for this supplier.',
      );
    }
  }

  /// Stock movements on products sourced from this supplier.
  Future<List<StockMovementRef>> fetchInventoryActivity({
    required String companyId,
    required String supplierId,
    int limit = 20,
  }) async {
    try {
      final productRows = await _client
          .from('products')
          .select('id')
          .eq('company_id', companyId)
          .eq('preferred_supplier_id', supplierId)
          .isFilter('deleted_at', null);

      final productIds = (productRows as List)
          .map((row) => (row as Map)['id'] as String)
          .toList();
      if (productIds.isEmpty) return const [];

      final rows = await _client
          .from('stock_movements')
          .select('''
            id,
            product_id,
            movement_type,
            quantity_delta,
            quantity_after,
            reason,
            notes,
            reference_type,
            created_at,
            employees!created_by (full_name),
            products (name, sku)
          ''')
          .inFilter('product_id', productIds)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map(
            (row) => StockMovementRef.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load inventory activity.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load inventory activity.');
    }
  }

  Future<SupplierDetail?> fetchDetail({
    required String companyId,
    required String supplierId,
  }) async {
    final supplier = await fetchById(
      companyId: companyId,
      supplierId: supplierId,
    );
    if (supplier == null) return null;

    final products = await fetchProductsForSupplier(
      companyId: companyId,
      supplierId: supplierId,
    );
    final movements = await fetchInventoryActivity(
      companyId: companyId,
      supplierId: supplierId,
    );

    return SupplierDetail(
      supplier: supplier,
      products: products,
      recentMovements: movements,
      timeline: _buildTimeline(supplier, products, movements),
    );
  }

  List<SupplierTimelineEvent> _buildTimeline(
    SupplierSummary supplier,
    List<SupplierProductLink> products,
    List<StockMovementRef> movements,
  ) {
    final events = <SupplierTimelineEvent>[];

    if (supplier.createdAt != null) {
      events.add(
        SupplierTimelineEvent(
          kind: SupplierTimelineKind.created,
          title: 'Supplier created',
          subtitle: supplier.name,
          at: supplier.createdAt!,
        ),
      );
    }

    if (supplier.updatedAt != null &&
        (supplier.createdAt == null ||
            supplier.updatedAt!.difference(supplier.createdAt!).inSeconds.abs() >
                2)) {
      events.add(
        SupplierTimelineEvent(
          kind: supplier.isActive
              ? SupplierTimelineKind.updated
              : SupplierTimelineKind.archived,
          title: supplier.isActive ? 'Profile updated' : 'Supplier archived',
          at: supplier.updatedAt!,
        ),
      );
    }

    if (supplier.lastPurchaseAt != null) {
      events.add(
        SupplierTimelineEvent(
          kind: SupplierTimelineKind.purchase,
          title: 'Last purchase recorded',
          subtitle: 'Purchase history will expand with Purchase Orders',
          at: supplier.lastPurchaseAt!,
        ),
      );
    }

    if (products.isNotEmpty && supplier.updatedAt != null) {
      events.add(
        SupplierTimelineEvent(
          kind: SupplierTimelineKind.productLinked,
          title: products.length == 1
              ? '1 product sourced'
              : '${products.length} products sourced',
          subtitle: products.take(3).map((p) => p.name).join(', '),
          at: supplier.updatedAt!,
        ),
      );
    }

    for (final movement in movements.take(12)) {
      final delta = movement.quantityDelta;
      final signed = delta > 0 ? '+$delta' : '$delta';
      events.add(
        SupplierTimelineEvent(
          kind: SupplierTimelineKind.stockMovement,
          title: movement.displayTitle,
          subtitle: [
            signed,
            if (movement.createdByName != null) movement.createdByName!,
            if (movement.reason != null) movement.reason!,
          ].join(' · '),
          at: movement.createdAt,
        ),
      );
    }

    if (supplier.notes != null &&
        supplier.notes!.trim().isNotEmpty &&
        supplier.updatedAt != null) {
      events.add(
        SupplierTimelineEvent(
          kind: SupplierTimelineKind.note,
          title: 'Notes on file',
          subtitle: supplier.notes!.trim(),
          at: supplier.updatedAt!,
        ),
      );
    }

    events.sort((a, b) => b.at.compareTo(a.at));
    return events;
  }

  Future<String> upsertSupplier({
    required SupplierUpsertInput input,
    required String companyId,
    required String employeeId,
    String? branchId,
  }) async {
    try {
      final isNew = input.isCreate;
      final payload = <String, dynamic>{
        'company_id': companyId,
        'branch_id': branchId,
        'name': input.name.trim(),
        'code': _nullIfBlank(input.code),
        'contact_name': _nullIfBlank(input.contactName),
        'phone': _nullIfBlank(input.phone),
        'whatsapp': _nullIfBlank(input.whatsapp),
        'email': _nullIfBlank(input.email),
        'address_line1': _nullIfBlank(input.addressLine1),
        'address_line2': _nullIfBlank(input.addressLine2),
        'city': _nullIfBlank(input.city),
        'state': _nullIfBlank(input.state),
        'postal_code': _nullIfBlank(input.postalCode),
        'country': _nullIfBlank(input.country),
        'tax_number': _nullIfBlank(input.taxNumber),
        'category': _nullIfBlank(input.category),
        'payment_terms': _nullIfBlank(input.paymentTerms),
        'bank_name': _nullIfBlank(input.bankName),
        'bank_account': _nullIfBlank(input.bankAccount),
        'notes': _nullIfBlank(input.notes),
        'credit_limit': input.creditLimit,
        'lead_time_days': input.leadTimeDays,
        'is_active': input.isActive,
        'updated_by': employeeId,
      };

      if (isNew) {
        payload['created_by'] = employeeId;
        payload['opening_balance'] = input.openingBalance;
        payload['current_balance'] = input.openingBalance;

        final inserted = await _client
            .from('suppliers')
            .insert(payload)
            .select('id')
            .single();
        final supplierId = inserted['id'] as String;
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: employeeId,
          event: BusinessEvents.supplierCreated(
            supplierId: supplierId,
            name: input.name.trim(),
            excludeEmployeeId: employeeId,
          ),
        );
        return supplierId;
      }

      await _client
          .from('suppliers')
          .update(payload)
          .eq('id', input.supplierId!)
          .eq('company_id', companyId);
      return input.supplierId!;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapError(error.message));
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> archiveSupplier({
    required String companyId,
    required String supplierId,
    required String employeeId,
    required bool archived,
  }) async {
    try {
      final existing = await _client
          .from('suppliers')
          .select('id, is_active, deleted_at')
          .eq('id', supplierId)
          .eq('company_id', companyId)
          .maybeSingle();
      if (existing == null) {
        throw const ValidationFailure('Supplier not found.');
      }
      if (existing['deleted_at'] != null) {
        throw const ValidationFailure(
          'This supplier has been permanently deleted.',
        );
      }

      await _client.from('suppliers').update({
        'is_active': !archived,
        'updated_by': employeeId,
      }).eq('id', supplierId).eq('company_id', companyId);
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapError(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> permanentlyDeleteSupplier({
    required String companyId,
    required String supplierId,
    required String employeeId,
  }) async {
    try {
      final existing = await _client
          .from('suppliers')
          .select('id, is_active, deleted_at')
          .eq('id', supplierId)
          .eq('company_id', companyId)
          .maybeSingle();
      if (existing == null) {
        throw const ValidationFailure('Supplier not found.');
      }
      if (existing['deleted_at'] != null) {
        throw const ValidationFailure(
          'This supplier has already been permanently deleted.',
        );
      }
      if (existing['is_active'] == true) {
        throw const ValidationFailure(
          'Archive the supplier before permanently deleting them.',
        );
      }

      await _client.from('suppliers').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': false,
        'updated_by': employeeId,
      }).eq('id', supplierId).eq('company_id', companyId);
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapError(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  String? _nullIfBlank(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _mapError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('suppliers_company_code_active_key') ||
        lower.contains('code')) {
      return 'A supplier with this code already exists.';
    }
    if (lower.contains('email')) {
      return 'Enter a valid email address.';
    }
    if (message.trim().isEmpty) {
      return 'Unable to save this supplier. Please try again.';
    }
    return message;
  }
}
