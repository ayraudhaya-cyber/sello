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
    cost_price,
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
      quantity,
      reorder_level
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
        final item = ProductSummary.fromQueryRow(Map<String, dynamic>.from(row));
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
        items: items,
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
        'cost_price': input.costPrice,
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

      if (isNew) {
        // Seed inventory at zero; opening qty goes through the ledger.
        await _client.from('inventory').upsert(
          {
            'company_id': companyId,
            'branch_id': branchId,
            'product_id': productId,
            'quantity': 0,
            'reorder_level': input.reorderLevel,
            'created_by': employeeId,
            'updated_by': employeeId,
          },
          onConflict: 'company_id,branch_id,product_id',
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
            .eq('product_id', productId)
            .maybeSingle();

        if (existing == null) {
          await _client.from('inventory').insert({
            'company_id': companyId,
            'branch_id': branchId,
            'product_id': productId,
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
      throw ValidationFailure(_mapProductError(error.message));
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

  String _mapProductError(String message) {
    final upper = message.toUpperCase();
    if (upper.contains('PRODUCTS_COMPANY_SKU_ACTIVE_KEY')) {
      return 'That SKU already exists in your catalog.';
    }
    if (upper.contains('PRODUCTS_COMPANY_BARCODE_ACTIVE_KEY')) {
      return 'That barcode already exists in your catalog.';
    }
    if (upper.contains('CATEGORIES_COMPANY_NAME_ACTIVE_KEY')) {
      return 'That category already exists.';
    }
    if (upper.contains('VALIDATE_PRODUCT_CATEGORY_COMPANY')) {
      return 'Choose a category from your company.';
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
