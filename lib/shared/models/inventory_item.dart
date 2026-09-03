import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/stock_movement_type.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _stringValue(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Branch-scoped stock row joined with product identity for Hub Inventory.
class InventoryItem extends Equatable {
  const InventoryItem({
    required this.inventoryId,
    required this.productId,
    required this.companyId,
    required this.branchId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.isActive,
    this.reservedQuantity = 0,
    this.categoryId,
    this.categoryName,
    this.reorderLevel,
    this.unitLabel,
    this.costPrice,
    this.preferredSupplierId,
    this.preferredSupplierName,
    this.imageUrl,
    this.imageStoragePath,
    this.lastMovementAt,
    this.updatedAt,
  });

  final String inventoryId;
  final String productId;
  final String companyId;
  final String branchId;
  final String name;
  final String sku;
  final num quantity;
  /// Held for future reservations / open orders — not deducted from on-hand yet.
  final num reservedQuantity;
  final num? reorderLevel;
  final bool isActive;
  final String? categoryId;
  final String? categoryName;
  final String? unitLabel;
  final num? costPrice;
  final String? preferredSupplierId;
  final String? preferredSupplierName;
  final String? imageUrl;
  final String? imageStoragePath;
  final DateTime? lastMovementAt;
  final DateTime? updatedAt;

  /// Sellable quantity after reserved holds.
  num get availableQuantity {
    final available = quantity - reservedQuantity;
    return available < 0 ? 0 : available;
  }

  num get stockValue => quantity * (costPrice ?? 0);

  StockStatus get stockStatus {
    if (!isActive) return StockStatus.archived;
    if (quantity <= 0) return StockStatus.out;
    final reorder = reorderLevel;
    if (reorder != null && quantity <= reorder) return StockStatus.low;
    return StockStatus.healthy;
  }

  bool get isLowStock => stockStatus == StockStatus.low;
  bool get isOutOfStock => stockStatus == StockStatus.out;

  InventoryItem copyWith({String? imageUrl}) {
    return InventoryItem(
      inventoryId: inventoryId,
      productId: productId,
      companyId: companyId,
      branchId: branchId,
      name: name,
      sku: sku,
      quantity: quantity,
      reservedQuantity: reservedQuantity,
      reorderLevel: reorderLevel,
      isActive: isActive,
      categoryId: categoryId,
      categoryName: categoryName,
      unitLabel: unitLabel,
      costPrice: costPrice,
      preferredSupplierId: preferredSupplierId,
      preferredSupplierName: preferredSupplierName,
      imageUrl: imageUrl ?? this.imageUrl,
      imageStoragePath: imageStoragePath,
      lastMovementAt: lastMovementAt,
      updatedAt: updatedAt,
    );
  }

  factory InventoryItem.fromQueryRow(Map<String, dynamic> json) {
    final product = json['products'];
    Map<String, dynamic>? productMap;
    if (product is Map<String, dynamic>) {
      productMap = product;
    } else if (product is Map) {
      productMap = Map<String, dynamic>.from(product);
    }

    String? categoryName;
    String? categoryId;
    String? imagePath;
    String? preferredSupplierName;
    if (productMap != null) {
      final categories = productMap['categories'];
      if (categories is Map) {
        categoryName = _stringValue(categories['name']);
        categoryId = categories['id'] as String?;
      }
      final preferred = productMap['preferred_supplier'];
      if (preferred is Map) {
        preferredSupplierName = _stringValue(preferred['name']);
      }
      final images = productMap['product_images'];
      if (images is List && images.isNotEmpty) {
        Map<String, dynamic>? primary;
        for (final row in images) {
          if (row is Map && row['is_primary'] == true) {
            primary = Map<String, dynamic>.from(row);
            break;
          }
        }
        primary ??=
            images.first is Map ? Map<String, dynamic>.from(images.first as Map) : null;
        imagePath = primary?['storage_path'] as String?;
      }
    }

    return InventoryItem(
      inventoryId: json['id'] as String,
      productId: json['product_id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String,
      name: productMap?['name'] as String? ?? 'Product',
      sku: productMap?['sku'] as String? ?? '',
      quantity: _numValue(json['quantity']),
      reservedQuantity: _numValue(json['reserved_quantity']),
      reorderLevel: json['reorder_level'] == null
          ? null
          : _numValue(json['reorder_level']),
      isActive: productMap?['is_active'] as bool? ?? true,
      categoryId: categoryId ?? productMap?['category_id'] as String?,
      categoryName: categoryName,
      unitLabel: _stringValue(productMap?['unit_label']),
      costPrice: productMap?['cost_price'] == null
          ? null
          : _numValue(productMap?['cost_price']),
      preferredSupplierId: productMap?['preferred_supplier_id'] as String?,
      preferredSupplierName: preferredSupplierName,
      imageStoragePath: imagePath,
      updatedAt: _dateValue(json['updated_at']),
      lastMovementAt: _dateValue(json['last_movement_at']),
    );
  }

  @override
  List<Object?> get props => [inventoryId, productId, quantity, reservedQuantity, updatedAt];
}

class StockMovement extends Equatable {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.branchId,
    required this.movementType,
    required this.quantityDelta,
    required this.quantityAfter,
    required this.createdAt,
    this.reason,
    this.notes,
    this.referenceType,
    this.referenceId,
    this.createdByName,
    this.productName,
    this.productSku,
  });

  final String id;
  final String productId;
  final String branchId;
  final StockMovementType movementType;
  final num quantityDelta;
  final num quantityAfter;
  final DateTime createdAt;
  final String? reason;
  final String? notes;
  final String? referenceType;
  final String? referenceId;
  final String? createdByName;
  final String? productName;
  final String? productSku;

  String get displayTitle {
    if (referenceType == 'order' && movementType == StockMovementType.sale) {
      return 'Order completed';
    }
    if (reason != null &&
        reason!.toLowerCase().contains('opening') &&
        movementType == StockMovementType.purchase) {
      return 'Initial stock';
    }
    if (referenceType == 'manual') {
      return movementType.label;
    }
    return movementType.label;
  }

  String? get referenceLabel {
    if (referenceType == null) return null;
    return switch (referenceType) {
      'order' => 'Order',
      'manual' => 'Manual',
      'product' => 'Product',
      'grn' => 'GRN',
      'purchase_order' => 'Purchase order',
      _ => referenceType,
    };
  }

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    String? employeeName;
    final employee = json['employees'];
    if (employee is Map) {
      employeeName = _stringValue(employee['full_name']);
    }

    String? productName;
    String? productSku;
    final product = json['products'];
    if (product is Map) {
      productName = _stringValue(product['name']);
      productSku = _stringValue(product['sku']);
    }

    return StockMovement(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      branchId: json['branch_id'] as String,
      movementType: StockMovementType.fromDb(json['movement_type'] as String?),
      quantityDelta: _numValue(json['quantity_delta']),
      quantityAfter: _numValue(json['quantity_after']),
      createdAt: _dateValue(json['created_at']) ?? DateTime.now().toUtc(),
      reason: _stringValue(json['reason']),
      notes: _stringValue(json['notes']),
      referenceType: _stringValue(json['reference_type']),
      referenceId: json['reference_id'] as String?,
      createdByName: employeeName,
      productName: productName,
      productSku: productSku,
    );
  }

  @override
  List<Object?> get props => [id, quantityDelta, createdAt];
}

class InventoryDashboardStats {
  const InventoryDashboardStats({
    required this.totalItems,
    required this.lowStock,
    required this.outOfStock,
    required this.recentlyUpdated,
    this.negativeStock = 0,
    this.stockValue = 0,
    this.recentMovements = 0,
  });

  final int totalItems;
  final int lowStock;
  final int outOfStock;

  /// Active products with physical on-hand `quantity < 0`.
  final int negativeStock;
  final int recentlyUpdated;
  final num stockValue;
  /// Movements in the last 7 days (branch-scoped when provided).
  final int recentMovements;
}

class StockAdjustInput {
  const StockAdjustInput({
    required this.branchId,
    required this.productId,
    required this.quantityDelta,
    required this.movementType,
    this.reason,
    this.notes,
  });

  final String branchId;
  final String productId;
  final num quantityDelta;
  final StockMovementType movementType;
  final String? reason;
  final String? notes;
}
