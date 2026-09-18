import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/product_media_repository.dart';
import 'package:sello/services/notifications/business_event_bus.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/product_category.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/models/product_upsert_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Product id -> unit cost through the `product_unit_costs` accessor.
///
/// `products.unit_cost` is not selectable by API clients; roles that may not
/// view cost get no rows back. Shared by the product, inventory, and supplier
/// reads so they all resolve cost the same way.
Future<Map<String, num>> fetchProductUnitCosts(
  SupabaseClient client,
  List<String> productIds,
) async {
  final unique = <String>{
    for (final id in productIds)
      if (id.trim().isNotEmpty) id.trim(),
  }.toList();
  if (unique.isEmpty) return const {};

  try {
    final rows = await client.rpc(
      'product_unit_costs',
      params: {'p_product_ids': unique},
    );
    final costs = <String, num>{};
    for (final raw in (rows as List? ?? const [])) {
      if (raw is! Map) continue;
      final id = raw['product_id'] as String?;
      if (id == null) continue;
      final value = raw['unit_cost'];
      costs[id] = value is num ? value : num.tryParse('$value') ?? 0;
    }
    return costs;
  } catch (_) {
    // Cost is supplementary — never fail a catalog load over it.
    return const {};
  }
}

class ProductPageResult {
  const ProductPageResult({
    required this.items,
    required this.hasMore,
  });

  final List<ProductSummary> items;
  final bool hasMore;
}

class ProductRepository {
  ProductRepository({
    SupabaseClient? client,
    MediaStorageService? imageStorage,
    ProductMediaRepository? mediaRepository,
    BusinessEventBus? events,
  })  : _client = client ?? SupabaseService.client,
        _imageStorage = imageStorage ?? MediaStorageService(),
        _mediaRepository = mediaRepository ?? ProductMediaRepository(),
        _events = events ?? BusinessEventBus();

  final SupabaseClient _client;
  final MediaStorageService _imageStorage;
  final ProductMediaRepository _mediaRepository;
  final BusinessEventBus _events;

  ProductMediaRepository get media => _mediaRepository;

  static const _productSelect = '''
    id,
    company_id,
    category_id,
    sku,
    barcode,
    name,
    brand,
    description,
    unit_label,
    selling_price,
    preferred_supplier_id,
    is_active,
    attributes,
    created_at,
    updated_at,
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
    ),
    inventory (
      branch_id,
      variant_id,
      quantity,
      reserved_quantity,
      reorder_level
    ),
    product_variants (
      id,
      company_id,
      product_id,
      label,
      options,
      sku,
      barcode,
      selling_price,
      sort_order,
      is_default,
      is_active
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
          .map((row) => ProductCategory.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<ProductPageResult> fetchProducts({
    String search = '',
    String? categoryId,
    bool? isActive,
    String? branchId,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      var query = _client
          .from('products')
          .select(_productSelect)
          .isFilter('deleted_at', null);

      if (search.trim().isNotEmpty) {
        final needle = search.trim();
        query = query.or(
          'name.ilike.%$needle%,sku.ilike.%$needle%,barcode.ilike.%$needle%,brand.ilike.%$needle%',
        );
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }

      final response = await query
          .order('updated_at', ascending: false)
          .range(page * pageSize, (page * pageSize) + pageSize - 1);

      final list = response as List;
      final items = <ProductSummary>[];
      for (final row in list) {
        final item = ProductSummary.fromQueryRow(
          Map<String, dynamic>.from(row),
          branchId: branchId,
        );
        if (item.imageStoragePath != null && item.imageStoragePath!.isNotEmpty) {
          try {
            final imageUrl =
                await _imageStorage.signProductImage(item.imageStoragePath!);
            items.add(item.copyWith(imageUrl: imageUrl));
          } catch (_) {
            items.add(item);
          }
        } else {
          items.add(item);
        }
      }

      return ProductPageResult(
        items: await attachUnitCosts(items),
        hasMore: items.length == pageSize,
      );
    } on PostgrestException catch (error) {
      throw AuthFailure(
        error.message.trim().isEmpty
            ? 'Unable to load products. Please try again.'
            : error.message,
      );
    } catch (error) {
      throw const UnexpectedFailure(
        'Unable to load products. Please try again.',
      );
    }
  }

  /// Resolves cost for [items] through `product_unit_costs`.
  ///
  /// Cost is not selectable from `products`; roles that may not view it simply
  /// get no rows back, which leaves [ProductSummary.costPrice] at zero — the
  /// same value the masked `cost_price` field used to produce for them.
  Future<List<ProductSummary>> attachUnitCosts(List<ProductSummary> items) async {
    if (items.isEmpty) return items;

    final costs = await fetchUnitCosts([for (final item in items) item.id]);
    if (costs.isEmpty) return items;

    return [
      for (final item in items)
        costs.containsKey(item.id)
            ? item.copyWith(costPrice: costs[item.id])
            : item,
    ];
  }

  /// Product id -> unit cost for the caller, empty when cost is not visible.
  Future<Map<String, num>> fetchUnitCosts(List<String> productIds) =>
      fetchProductUnitCosts(_client, productIds);

  /// Loads specific products by id (visit draft restore, etc.).
  Future<List<ProductSummary>> fetchProductsByIds({
    required List<String> ids,
    String? branchId,
    bool? isActive = true,
  }) async {
    final unique = <String>{
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    }.toList();
    if (unique.isEmpty) return const [];

    try {
      var query = _client
          .from('products')
          .select(_productSelect)
          .isFilter('deleted_at', null)
          .inFilter('id', unique);

      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }

      final response = await query;
      final list = response as List;
      final items = <ProductSummary>[];
      for (final row in list) {
        final item = ProductSummary.fromQueryRow(
          Map<String, dynamic>.from(row),
          branchId: branchId,
        );
        if (item.imageStoragePath != null && item.imageStoragePath!.isNotEmpty) {
          try {
            final imageUrl =
                await _imageStorage.signProductImage(item.imageStoragePath!);
            items.add(item.copyWith(imageUrl: imageUrl));
          } catch (_) {
            items.add(item);
          }
        } else {
          items.add(item);
        }
      }
      return await attachUnitCosts(items);
    } on PostgrestException catch (error) {
      throw AuthFailure(
        error.message.trim().isEmpty
            ? 'Unable to load products. Please try again.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure(
        'Unable to load products. Please try again.',
      );
    }
  }

  /// Inserts/updates product + inventory and returns the product id.
  /// Does not upload gallery images — call [syncProductGallery] separately.
  Future<String> upsertProductRecord({
    required ProductUpsertInput input,
    required String companyId,
    required String employeeId,
    required String branchId,
  }) async {
    String? productId = input.productId;
    final categoryId = await _ensureCategory(
      companyId: companyId,
      employeeId: employeeId,
      name: input.categoryName,
    );

    try {
      final productPayload = {
        'company_id': companyId,
        'category_id': categoryId,
        'sku': input.sku.trim(),
        'barcode': _nullIfBlank(input.barcode),
        'name': input.name.trim(),
        'brand': _nullIfBlank(input.brand),
        'description': _nullIfBlank(input.description),
        'unit_label': _nullIfBlank(input.unitLabel),
        // Physical column is unit_cost; cost_price is a role-masked computed field.
        'unit_cost': input.costPrice,
        'selling_price': input.sellingPrice,
        'preferred_supplier_id': input.preferredSupplierId,
        'is_active': input.isActive,
        'attributes': {
          for (final entry in input.attributes.entries)
            if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
        },
        'updated_by': employeeId,
      };

      final isNew = input.productId == null;

      if (productId == null) {
        final inserted = await _client
            .from('products')
            .insert({
              ...productPayload,
              'created_by': employeeId,
            })
            .select('id')
            .single();
        productId = inserted['id'] as String;
      } else {
        await _client.from('products').update(productPayload).eq('id', productId);
      }

      // New products get their default variant from an AFTER INSERT trigger.
      final variantId = await _syncDefaultVariant(
        productId: productId,
        input: input,
        employeeId: employeeId,
      );

      if (isNew) {
        // Seed inventory at zero; opening qty goes through the ledger.
        await _client.from('inventory').upsert(
          {
            'company_id': companyId,
            'branch_id': branchId,
            'product_id': productId,
            'variant_id': variantId,
            'quantity': 0,
            'reorder_level': input.reorderLevel,
            'created_by': employeeId,
            'updated_by': employeeId,
          },
          onConflict: 'company_id,branch_id,variant_id',
        );

        if (input.currentStockQuantity > 0) {
          await _client.rpc(
            'adjust_inventory',
            params: {
              'p_branch_id': branchId,
              'p_product_id': productId,
              'p_quantity_delta': input.currentStockQuantity,
              'p_movement_type': 'purchase',
              'p_reason': 'Opening stock',
              'p_notes': null,
              'p_reference_type': 'product',
              'p_reference_id': productId,
              'p_variant_id': variantId,
            },
          );
        }
      } else {
        // Quantity changes belong in Inventory adjustments — only sync reorder.
        final existing = await _client
            .from('inventory')
            .select('id')
            .eq('company_id', companyId)
            .eq('branch_id', branchId)
            .eq('variant_id', variantId)
            .maybeSingle();

        if (existing == null) {
          await _client.from('inventory').insert({
            'company_id': companyId,
            'branch_id': branchId,
            'product_id': productId,
            'variant_id': variantId,
            'quantity': 0,
            'reorder_level': input.reorderLevel,
            'created_by': employeeId,
            'updated_by': employeeId,
          });
        } else {
          await _client.from('inventory').update({
            'reorder_level': input.reorderLevel,
            'updated_by': employeeId,
          }).eq('id', existing['id'] as String);
        }
      }

      final savedProductId = productId;
      final name = input.name.trim();
      if (isNew) {
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: employeeId,
          event: BusinessEvents.productCreated(
            productId: savedProductId,
            name: name,
          ),
        );
      } else {
        await _events.publish(
          companyId: companyId,
          actorEmployeeId: employeeId,
          event: BusinessEvents.productUpdated(
            productId: savedProductId,
            name: name,
          ),
        );
      }

      return savedProductId;
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        _mapProductError(error.message, code: error.code),
      );
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> syncProductGallery({
    required String companyId,
    required String employeeId,
    required String productId,
    required List<MediaGalleryDraft> gallery,
    void Function(MediaUploadProgress progress)? onMediaProgress,
  }) async {
    final needsSync = gallery.any(
      (d) => d.dirty || d.removed || (d.isNew && d.localBytes != null),
    );
    if (!needsSync) return;

    try {
      await _mediaRepository.syncGallery(
        companyId: companyId,
        employeeId: employeeId,
        productId: productId,
        drafts: gallery,
        onProgress: onMediaProgress,
      );
    } on StorageException catch (error) {
      throw ValidationFailure(
        error.message.isEmpty
            ? 'Unable to upload the product image.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<String> saveProduct({
    required ProductUpsertInput input,
    required String companyId,
    required String employeeId,
    required String branchId,
    List<MediaGalleryDraft> gallery = const [],
    void Function(MediaUploadProgress progress)? onMediaProgress,
  }) async {
    final productId = await upsertProductRecord(
      input: input,
      companyId: companyId,
      employeeId: employeeId,
      branchId: branchId,
    );
    await syncProductGallery(
      companyId: companyId,
      employeeId: employeeId,
      productId: productId,
      gallery: gallery,
      onMediaProgress: onMediaProgress,
    );
    return productId;
  }

  Future<void> archiveProduct({
    required String productId,
    required String employeeId,
    required bool archived,
  }) async {
    try {
      final existing = await _client
          .from('products')
          .select('id, is_active, deleted_at')
          .eq('id', productId)
          .maybeSingle();
      if (existing == null) {
        throw const ValidationFailure('Product not found.');
      }
      if (existing['deleted_at'] != null) {
        throw const ValidationFailure(
          'This product has been permanently deleted.',
        );
      }

      await _client.from('products').update({
        'is_active': !archived,
        'updated_by': employeeId,
      }).eq('id', productId);

      if (archived) {
        final row = await _client
            .from('products')
            .select('company_id, name')
            .eq('id', productId)
            .maybeSingle();
        final companyId = row?['company_id'] as String?;
        final name = row?['name'] as String? ?? 'Product';
        if (companyId != null) {
          await _events.publish(
            companyId: companyId,
            actorEmployeeId: employeeId,
            event: BusinessEvents.productArchived(
              productId: productId,
              name: name,
              excludeEmployeeId: employeeId,
            ),
          );
        }
      }
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapProductError(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Permanently remove an archived product from the catalog.
  ///
  /// Purges gallery files, then soft-deletes the product (`deleted_at`) so
  /// historical order lines keep referential integrity. Active products must
  /// be archived first.
  Future<void> permanentlyDeleteProduct({
    required String productId,
    required String employeeId,
  }) async {
    try {
      final existing = await _client
          .from('products')
          .select('id, is_active, deleted_at')
          .eq('id', productId)
          .maybeSingle();
      if (existing == null) {
        throw const ValidationFailure('Product not found.');
      }
      if (existing['deleted_at'] != null) {
        throw const ValidationFailure(
          'This product has already been permanently deleted.',
        );
      }
      if (existing['is_active'] == true) {
        throw const ValidationFailure(
          'Archive the product before permanently deleting it.',
        );
      }

      await _mediaRepository.purgeProductImages(productId);

      await _client.from('products').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': false,
        'updated_by': employeeId,
      }).eq('id', productId);
    } on ValidationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw ValidationFailure(_mapProductError(error.message));
    } on StorageException catch (error) {
      throw ValidationFailure(
        error.message.isEmpty
            ? 'Unable to remove product photos.'
            : error.message,
      );
    } on AppFailure {
      rethrow;
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Returns the product's live default variant id, mirroring the parent's
  /// sellable fields onto it while the product still has a single variant.
  ///
  /// Products with more than one live variant are left alone — their sellable
  /// values are managed per variant, not from the parent.
  Future<String> _syncDefaultVariant({
    required String productId,
    required ProductUpsertInput input,
    required String employeeId,
  }) async {
    final rows = await _client
        .from('product_variants')
        .select('id, is_default, is_active')
        .eq('product_id', productId)
        .isFilter('deleted_at', null);

    final variants = [
      for (final row in rows as List) Map<String, dynamic>.from(row as Map),
    ];

    Map<String, dynamic>? defaultVariant;
    for (final variant in variants) {
      if (variant['is_default'] == true) {
        defaultVariant = variant;
        break;
      }
    }

    if (defaultVariant == null) {
      throw const ProvisioningFailure(
        'This product has no sellable variant yet. Please try again.',
      );
    }

    final variantId = defaultVariant['id'] as String;

    if (variants.length == 1) {
      await _client.from('product_variants').update({
        'sku': input.sku.trim(),
        'barcode': _nullIfBlank(input.barcode),
        'selling_price': input.sellingPrice,
        'unit_cost': input.costPrice,
        'is_active': input.isActive,
        'updated_by': employeeId,
      }).eq('id', variantId);
    }

    return variantId;
  }

  Future<String?> _ensureCategory({
    required String companyId,
    required String employeeId,
    required String name,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;

    final existing = await _client
        .from('categories')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', normalized)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (existing != null) {
      return existing['id'] as String;
    }

    try {
      final inserted = await _client
          .from('categories')
          .insert({
            'company_id': companyId,
            'name': normalized,
            'created_by': employeeId,
            'updated_by': employeeId,
          })
          .select('id')
          .single();
      return inserted['id'] as String;
    } on PostgrestException {
      final retry = await _client
          .from('categories')
          .select('id')
          .eq('company_id', companyId)
          .eq('name', normalized)
          .isFilter('deleted_at', null)
          .single();
      return retry['id'] as String;
    }
  }

  String? _nullIfBlank(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  String _mapProductError(String message, {String? code}) {
    final upper = message.toUpperCase();
    final isDuplicate = code == '23505' ||
        upper.contains('23505') ||
        upper.contains('DUPLICATE KEY') ||
        upper.contains('UNIQUE CONSTRAINT');

    if (upper.contains('PRODUCTS_COMPANY_SKU_ACTIVE_KEY') ||
        (isDuplicate && upper.contains('SKU'))) {
      return 'That item code (SKU) already exists in your catalog. '
          'Use a unique code for each product.';
    }
    if (upper.contains('PRODUCTS_COMPANY_BARCODE_ACTIVE_KEY') ||
        (isDuplicate && upper.contains('BARCODE'))) {
      return 'That barcode already exists in your catalog.';
    }
    if (isDuplicate) {
      return 'A product with the same item code or barcode already exists.';
    }
    if (upper.contains('CATEGORIES_COMPANY_NAME_ACTIVE_KEY')) {
      return 'That category already exists.';
    }
    if (upper.contains('VALIDATE_PRODUCT_CATEGORY_COMPANY')) {
      return 'Choose a category from your company.';
    }
    if (upper.contains('PRODUCTS_SKU_NOT_BLANK') ||
        upper.contains('SKU_NOT_BLANK')) {
      return 'Enter an item code.';
    }
    if (upper.contains('PRODUCT_IMAGES')) {
      return 'Unable to update the product image.';
    }
    if (message.trim().isNotEmpty) {
      return message;
    }
    return 'Unable to save the product. Please try again.';
  }
}
