import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/product_repository.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/stock_movement_type.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryPageResult {
  const InventoryPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<InventoryItem> items;
  final bool hasMore;
}

/// Shared inventory domain — Hub manages; Sales reads availability only.
class InventoryRepository {
  InventoryRepository({
    SupabaseClient? client,
    MediaStorageService? imageStorage,
    BusinessEventBus? events,
  })  : _client = client ?? SupabaseService.client,
        _imageStorage = imageStorage ?? MediaStorageService(),
        _events = events ?? BusinessEventBus();

  final SupabaseClient _client;
  final MediaStorageService _imageStorage;
  final BusinessEventBus _events;

  static const _listSelect = '''
    id,
    company_id,
    branch_id,
    product_id,
    variant_id,
    quantity,
    reserved_quantity,
    reorder_level,
    last_movement_at,
    updated_at,
    product_variants (
      id,
      label,
      sku,
      is_default
    ),
    products!inner (
      id,
      name,
      sku,
      unit_label,
      is_active,
      category_id,
      preferred_supplier_id,
      deleted_at,
      categories (
        id,
        name
      ),
      preferred_supplier:suppliers!preferred_supplier_id (
        id,
        name
      ),
      product_images (
        id,
        storage_path,
        sort_order,
        is_primary
      )
    )
  ''';

  Future<List<ProductCategory>> fetchCategories() async {
    try {
      final rows = await _client
          .from('categories')
          .select('id, company_id, name, sort_order')
          .isFilter('deleted_at', null)
          .order('sort_order')
          .order('name');
      return (rows as List)
          .map(
            (row) => ProductCategory.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<InventoryPageResult> fetchStock({
    String search = '',
    String? categoryId,
    String? branchId,
    StockStatusFilter status = StockStatusFilter.all,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('inventory')
          .select(_listSelect)
          .isFilter('products.deleted_at', null);

      if (branchId != null && branchId.isNotEmpty) {
        query = query.eq('branch_id', branchId);
      }

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('products.category_id', categoryId);
      }

      switch (status) {
        case StockStatusFilter.archived:
          query = query.eq('products.is_active', false);
        case StockStatusFilter.outOfStock:
          query = query.eq('products.is_active', true).lte('quantity', 0);
        case StockStatusFilter.negativeStock:
          query = query.eq('products.is_active', true).lt('quantity', 0);
        case StockStatusFilter.recentlyUpdated:
          final cutoff = DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 7))
              .toIso8601String();
          query = query
              .eq('products.is_active', true)
              .gte('updated_at', cutoff);
        case StockStatusFilter.all:
          break;
        case StockStatusFilter.inStock:
        case StockStatusFilter.lowStock:
          query = query.eq('products.is_active', true).gt('quantity', 0);
      }

      final needle = search.trim();
      if (needle.isNotEmpty) {
        query = query.or(
          'name.ilike.%$needle%,sku.ilike.%$needle%,barcode.ilike.%$needle%,brand.ilike.%$needle%',
          referencedTable: 'products',
        );
      }

      // Over-fetch when low-stock needs client-side reorder comparison.
      final fetchSize = status == StockStatusFilter.lowStock ||
              status == StockStatusFilter.inStock
          ? pageSize * 8
          : pageSize + 1;

      final response = await query
          .order('updated_at', ascending: false)
          .range(0, (page + 1) * fetchSize - 1);

      final byId = <String, InventoryItem>{};
      for (final row in response as List) {
        final item = InventoryItem.fromQueryRow(
          Map<String, dynamic>.from(row as Map),
        );
        byId[item.inventoryId] = item;
      }

      // Also match sellable option SKU / barcode without a new RPC.
      if (needle.isNotEmpty) {
        try {
          var variantQuery = _client
              .from('inventory')
              .select(_listSelect)
              .isFilter('products.deleted_at', null)
              .or(
                'sku.ilike.%$needle%,barcode.ilike.%$needle%',
                referencedTable: 'product_variants',
              );
          if (branchId != null && branchId.isNotEmpty) {
            variantQuery = variantQuery.eq('branch_id', branchId);
          }
          if (categoryId != null && categoryId.isNotEmpty) {
            variantQuery =
                variantQuery.eq('products.category_id', categoryId);
          }
          final variantRows = await variantQuery
              .order('updated_at', ascending: false)
              .range(0, (page + 1) * fetchSize - 1);
          for (final row in variantRows as List) {
            final item = InventoryItem.fromQueryRow(
              Map<String, dynamic>.from(row as Map),
            );
            byId.putIfAbsent(item.inventoryId, () => item);
          }
        } catch (_) {
          // Variant search is additive — product search still works.
        }
      }

      var items = byId.values.toList()
        ..sort((a, b) {
          final aAt = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bAt = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bAt.compareTo(aAt);
        });

      items = items.where((item) {
        return switch (status) {
          StockStatusFilter.all => true,
          StockStatusFilter.archived => !item.isActive,
          StockStatusFilter.outOfStock => item.isActive && item.quantity <= 0,
          StockStatusFilter.negativeStock => item.isActive && item.quantity < 0,
          StockStatusFilter.lowStock => item.isActive && item.isLowStock,
          StockStatusFilter.inStock =>
            item.isActive && item.stockStatus == StockStatus.healthy,
          StockStatusFilter.recentlyUpdated => item.isActive,
        };
      }).toList();

      final pageItems = items.skip(page * pageSize).take(pageSize).toList();
      final signed = await _signThumbs(pageItems);

      return InventoryPageResult(
        items: await _attachCosts(signed),
        hasMore: items.length > (page + 1) * pageSize,
      );
    } on PostgrestException catch (error) {
      // reserved_quantity may be missing before migration 020.
      if (error.message.toLowerCase().contains('reserved_quantity')) {
        return _fetchStockLegacy(
          search: search,
          categoryId: categoryId,
          branchId: branchId,
          status: status,
          page: page,
          pageSize: pageSize,
        );
      }
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Fallback select without reserved_quantity until migration 020 lands.
  Future<InventoryPageResult> _fetchStockLegacy({
    required String search,
    String? categoryId,
    String? branchId,
    required StockStatusFilter status,
    required int page,
    required int pageSize,
  }) async {
    var query = _client.from('inventory').select('''
      id, company_id, branch_id, product_id, quantity, reorder_level,
      last_movement_at, updated_at,
      products!inner (
        id, name, sku, unit_label, is_active, category_id, deleted_at,
        categories (id, name),
        product_images (id, storage_path, sort_order, is_primary)
      )
    ''').isFilter('products.deleted_at', null);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.eq('branch_id', branchId);
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.eq('products.category_id', categoryId);
    }

    final response = await query
        .order('updated_at', ascending: false)
        .range(0, (page + 1) * pageSize * 8 - 1);

    var items = <InventoryItem>[];
    for (final row in response as List) {
      items.add(
        InventoryItem.fromQueryRow(Map<String, dynamic>.from(row as Map)),
      );
    }
    items = items.where((item) {
      return switch (status) {
        StockStatusFilter.all => true,
        StockStatusFilter.archived => !item.isActive,
        StockStatusFilter.outOfStock => item.isActive && item.quantity <= 0,
        StockStatusFilter.negativeStock => item.isActive && item.quantity < 0,
        StockStatusFilter.lowStock => item.isActive && item.isLowStock,
        StockStatusFilter.inStock =>
          item.isActive && item.stockStatus == StockStatus.healthy,
        StockStatusFilter.recentlyUpdated => item.isActive &&
            item.updatedAt != null &&
            item.updatedAt!
                .isAfter(DateTime.now().toUtc().subtract(const Duration(days: 7))),
      };
    }).toList();

    final pageItems = items.skip(page * pageSize).take(pageSize).toList();
    return InventoryPageResult(
      items: await _attachCosts(await _signThumbs(pageItems)),
      hasMore: items.length > (page + 1) * pageSize,
    );
  }

  /// Resolves cost for [items] through the shared `product_unit_costs`
  /// accessor. Roles that may not view cost keep a null [InventoryItem.costPrice],
  /// so stock value renders as zero exactly as it did under the masked field.
  Future<List<InventoryItem>> _attachCosts(List<InventoryItem> items) async {
    if (items.isEmpty) return items;

    final costs = await fetchProductUnitCosts(
      _client,
      [for (final item in items) item.productId],
    );
    if (costs.isEmpty) return items;

    return [
      for (final item in items)
        costs.containsKey(item.productId)
            ? item.copyWith(costPrice: costs[item.productId])
            : item,
    ];
  }

  Future<List<InventoryItem>> _signThumbs(List<InventoryItem> pageItems) async {
    final signed = <InventoryItem>[];
    for (final item in pageItems) {
      if (item.imageStoragePath == null || item.imageStoragePath!.isEmpty) {
        signed.add(item);
        continue;
      }
      try {
        final url = await _imageStorage.signProductImage(item.imageStoragePath!);
        signed.add(item.copyWith(imageUrl: url));
      } catch (_) {
        signed.add(item);
      }
    }
    return signed;
  }

  Future<InventoryDashboardStats> fetchDashboardStats({
    String? branchId,
  }) async {
    try {
      var query = _client.from('inventory').select('''
        quantity,
        reserved_quantity,
        reorder_level,
        updated_at,
        products!inner (
          is_active,
          deleted_at
        )
      ''').isFilter('products.deleted_at', null);

      if (branchId != null && branchId.isNotEmpty) {
        query = query.eq('branch_id', branchId);
      }

      final rows = await query;
      final now = DateTime.now().toUtc();
      final recentCutoff = now.subtract(const Duration(days: 7));

      var total = 0;
      var low = 0;
      var out = 0;
      var negative = 0;
      var recent = 0;

      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final product = map['products'];
        final isActive = product is Map
            ? product['is_active'] as bool? ?? true
            : true;
        if (!isActive) continue;

        total++;
        final qty = _asNum(map['quantity']);
        final reorder = map['reorder_level'] == null
            ? null
            : _asNum(map['reorder_level']);
        if (qty < 0) {
          negative++;
          out++;
        } else if (qty <= 0) {
          out++;
        } else if (reorder != null && qty <= reorder) {
          low++;
        }
        final updated = DateTime.tryParse(map['updated_at'] as String? ?? '');
        if (updated != null && updated.isAfter(recentCutoff)) {
          recent++;
        }
      }

      var recentMovements = 0;
      try {
        var movementQuery = _client
            .from('stock_movements')
            .select('id')
            .gte('created_at', recentCutoff.toIso8601String());
        if (branchId != null && branchId.isNotEmpty) {
          movementQuery = movementQuery.eq('branch_id', branchId);
        }
        final movementRows = await movementQuery;
        recentMovements = (movementRows as List).length;
      } catch (_) {
        // Best-effort.
      }

      return InventoryDashboardStats(
        totalItems: total,
        lowStock: low,
        outOfStock: out,
        negativeStock: negative,
        recentlyUpdated: recent,
        stockValue: await _fetchStockValue(branchId),
        recentMovements: recentMovements,
      );
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('reserved_quantity')) {
        return _fetchDashboardStatsLegacy(branchId: branchId);
      }
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<InventoryDashboardStats> _fetchDashboardStatsLegacy({
    String? branchId,
  }) async {
    var query = _client.from('inventory').select('''
      quantity, reorder_level, updated_at,
      products!inner (is_active, deleted_at)
    ''').isFilter('products.deleted_at', null);
    if (branchId != null && branchId.isNotEmpty) {
      query = query.eq('branch_id', branchId);
    }
    final rows = await query;
    final recentCutoff =
        DateTime.now().toUtc().subtract(const Duration(days: 7));
    var total = 0;
    var low = 0;
    var out = 0;
    var negative = 0;
    var recent = 0;
    for (final row in rows as List) {
      final map = Map<String, dynamic>.from(row as Map);
      final product = map['products'];
      if (product is Map && product['is_active'] == false) continue;
      total++;
      final qty = _asNum(map['quantity']);
      final reorder =
          map['reorder_level'] == null ? null : _asNum(map['reorder_level']);
      if (qty < 0) {
        negative++;
        out++;
      } else if (qty <= 0) {
        out++;
      } else if (reorder != null && qty <= reorder) {
        low++;
      }
      final updated = DateTime.tryParse(map['updated_at'] as String? ?? '');
      if (updated != null && updated.isAfter(recentCutoff)) recent++;
    }
    return InventoryDashboardStats(
      totalItems: total,
      lowStock: low,
      outOfStock: out,
      negativeStock: negative,
      recentlyUpdated: recent,
      stockValue: await _fetchStockValue(branchId),
    );
  }

  /// Branch valuation from `inventory_stock_value`.
  ///
  /// Valuation moved server-side because product cost is no longer selectable;
  /// the function returns 0 for roles that may not view cost, which is what the
  /// client-side sum produced when the masked field came back null.
  Future<num> _fetchStockValue(String? branchId) async {
    try {
      final value = await _client.rpc(
        'inventory_stock_value',
        params: {
          'p_branch_id':
              branchId != null && branchId.isNotEmpty ? branchId : null,
        },
      );
      return _asNum(value);
    } catch (_) {
      // Valuation is supplementary — never fail the dashboard over it.
      return 0;
    }
  }

  /// History for one sellable unit. Pass [variantId] to scope to a single
  /// variant; omit it to see every variant of the parent product.
  Future<List<StockMovement>> fetchMovements({
    required String productId,
    String? variantId,
    String? branchId,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('stock_movements')
          .select('''
            id,
            product_id,
            variant_id,
            branch_id,
            movement_type,
            quantity_delta,
            quantity_after,
            reason,
            notes,
            reference_type,
            reference_id,
            created_at,
            employees!created_by (
              full_name
            ),
            product_variants (
              id,
              label,
              sku
            )
          ''')
          .eq('product_id', productId);

      if (variantId != null && variantId.isNotEmpty) {
        query = query.eq('variant_id', variantId);
      }

      if (branchId != null && branchId.isNotEmpty) {
        query = query.eq('branch_id', branchId);
      }

      final rows =
          await query.order('created_at', ascending: false).limit(limit);

      return (rows as List)
          .map(
            (row) => StockMovement.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Branch-wide recent ledger for the Inventory workspace.
  Future<List<StockMovement>> fetchRecentMovements({
    String? branchId,
    int limit = 12,
  }) async {
    try {
      var query = _client.from('stock_movements').select('''
        id,
        product_id,
        variant_id,
        branch_id,
        movement_type,
        quantity_delta,
        quantity_after,
        reason,
        notes,
        reference_type,
        reference_id,
        created_at,
        employees!created_by (full_name),
        products (name, sku),
        product_variants (id, label, sku)
      ''');

      if (branchId != null && branchId.isNotEmpty) {
        query = query.eq('branch_id', branchId);
      }

      final rows =
          await query.order('created_at', ascending: false).limit(limit);

      return (rows as List)
          .map(
            (row) => StockMovement.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> adjustStock(StockAdjustInput input) async {
    if (input.quantityDelta == 0) {
      throw const ValidationFailure('Enter a non-zero quantity change.');
    }

    try {
      await _client.rpc(
        'adjust_inventory',
        params: {
          'p_branch_id': input.branchId,
          'p_product_id': input.productId,
          'p_quantity_delta': input.quantityDelta,
          'p_movement_type': input.movementType.dbValue,
          'p_reason': input.reason ?? input.movementType.label,
          'p_notes': input.notes,
          'p_reference_type': 'manual',
          'p_reference_id': null,
          // Null lets the server resolve the product's default variant.
          'p_variant_id': input.variantId,
        },
      );

      try {
        var lookup = _client
            .from('inventory')
            .select('''
              company_id,
              products!inner (id, name)
            ''')
            .eq('branch_id', input.branchId);
        lookup = input.variantId != null
            ? lookup.eq('variant_id', input.variantId!)
            : lookup.eq('product_id', input.productId);

        final row = await lookup.limit(1).maybeSingle();
        if (row == null) return;

        final companyId = row['company_id'] as String?;
        final product = row['products'];
        final productName = product is Map
            ? (product['name'] as String? ?? 'Product')
            : 'Product';
        if (companyId == null) return;

        await _events.publish(
          companyId: companyId,
          event: BusinessEvents.stockAdjusted(
            productId: input.productId,
            productName: productName,
          ),
        );
        // Negative-stock crossing is emitted transactionally by adjust_inventory.
      } catch (_) {
        // Never block stock adjustment on notification failure.
      }
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapError(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Availability for Sales / Orders — on-hand minus reserved.
  ///
  /// Pass [variantId] for the sellable unit. Without it the product's variants
  /// are summed, which only matches a single sellable unit while a product has
  /// one variant.
  Future<num> fetchAvailableQuantity({
    required String productId,
    String? variantId,
    required String branchId,
  }) async {
    try {
      var query = _client
          .from('inventory')
          .select('quantity, reserved_quantity')
          .eq('branch_id', branchId);
      query = variantId != null && variantId.isNotEmpty
          ? query.eq('variant_id', variantId)
          : query.eq('product_id', productId);

      final rows = await query;
      num available = 0;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final value = _asNum(row['quantity']) - _asNum(row['reserved_quantity']);
        available += value < 0 ? 0 : value;
      }
      return available;
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('reserved_quantity')) {
        final rows = await _client
            .from('inventory')
            .select('quantity')
            .eq('product_id', productId)
            .eq('branch_id', branchId);
        num available = 0;
        for (final raw in rows as List) {
          available += _asNum(Map<String, dynamic>.from(raw as Map)['quantity']);
        }
        return available;
      }
      throw ProvisioningFailure(error.message);
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    }
  }

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static String _mapError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('insufficient')) {
      return 'Not enough stock for this adjustment.';
    }
    if (lower.contains('non-zero') || lower.contains('quantity')) {
      return message;
    }
    return message;
  }
}
