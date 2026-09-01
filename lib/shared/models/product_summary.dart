import 'package:equatable/equatable.dart';
import 'package:sello/shared/utils/country_catalog.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

Map<String, String> _attributesMap(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((key, value) {
    if (key == null || value == null) return;
    final text = value.toString().trim();
    if (text.isEmpty) return;
    out[key.toString()] = text;
  });
  return out;
}

class ProductSummary extends Equatable {
  const ProductSummary({
    required this.id,
    required this.companyId,
    required this.name,
    required this.sku,
    required this.sellingPrice,
    required this.costPrice,
    required this.currentStockQuantity,
    required this.isActive,
    this.categoryId,
    this.categoryName,
    this.barcode,
    this.brand,
    this.unitLabel,
    this.description,
    this.reorderLevel,
    this.preferredSupplierId,
    this.preferredSupplierName,
    this.attributes = const {},
    this.imageStoragePath,
    this.imageUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? categoryId;
  final String? categoryName;
  final String sku;
  final String? barcode;
  final String name;
  final String? brand;
  final String? unitLabel;
  final String? description;
  final num costPrice;
  final num sellingPrice;
  final num currentStockQuantity;
  final num? reorderLevel;
  /// Primary sourcing partner — V1 single preferred; multi via product_suppliers later.
  final String? preferredSupplierId;
  final String? preferredSupplierName;
  final bool isActive;
  final Map<String, String> attributes;
  final String? imageStoragePath;
  final String? imageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String? attribute(String key) {
    final value = attributes[key];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  /// Display helper for list/catalog specs (country includes flag).
  String? displayAttribute(String key) {
    final value = attribute(key);
    if (value == null) return null;
    if (key == 'made_in_country') return CountryCatalog.display(value);
    return value;
  }

  ProductSummary copyWith({String? imageUrl}) {
    return ProductSummary(
      id: id,
      companyId: companyId,
      categoryId: categoryId,
      categoryName: categoryName,
      sku: sku,
      barcode: barcode,
      name: name,
      brand: brand,
      unitLabel: unitLabel,
      description: description,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      currentStockQuantity: currentStockQuantity,
      reorderLevel: reorderLevel,
      preferredSupplierId: preferredSupplierId,
      preferredSupplierName: preferredSupplierName,
      isActive: isActive,
      attributes: attributes,
      imageStoragePath: imageStoragePath,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory ProductSummary.fromQueryRow(Map<String, dynamic> json) {
    final category = json['categories'];
    final images = (json['product_images'] as List?) ?? const [];
    final inventory = (json['inventory'] as List?) ?? const [];

    Map<String, dynamic>? primaryImage;
    final parsedImages = <Map<String, dynamic>>[];
    for (final item in images) {
      if (item is! Map) continue;
      parsedImages.add(Map<String, dynamic>.from(item));
    }
    parsedImages.sort((a, b) {
      final aPrimary = a['is_primary'] == true;
      final bPrimary = b['is_primary'] == true;
      if (aPrimary != bPrimary) return aPrimary ? -1 : 1;
      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });
    if (parsedImages.isNotEmpty) {
      primaryImage = parsedImages.first;
    }

    num totalStock = 0;
    num? reorderLevel;
    for (final item in inventory) {
      if (item is! Map) continue;
      totalStock += _numValue(item['quantity']);
      final value = item['reorder_level'];
      if (value != null) {
        reorderLevel = (reorderLevel ?? 0) + _numValue(value);
      }
    }

    final preferred = json['preferred_supplier'];
    String? preferredName;
    if (preferred is Map) {
      preferredName = preferred['name'] as String?;
    }

    return ProductSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      categoryId: json['category_id'] as String?,
      categoryName:
          category is Map<String, dynamic> ? category['name'] as String? : null,
      sku: json['sku'] as String,
      barcode: json['barcode'] as String?,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      unitLabel: json['unit_label'] as String?,
      description: json['description'] as String?,
      costPrice: _numValue(json['cost_price']),
      sellingPrice: _numValue(json['selling_price']),
      currentStockQuantity: totalStock,
      reorderLevel: reorderLevel,
      preferredSupplierId: json['preferred_supplier_id'] as String?,
      preferredSupplierName: preferredName,
      isActive: json['is_active'] as bool? ?? true,
      attributes: _attributesMap(json['attributes']),
      imageStoragePath: primaryImage?['storage_path'] as String?,
      createdAt: _dateValue(json['created_at']),
      updatedAt: _dateValue(json['updated_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        categoryId,
        categoryName,
        sku,
        barcode,
        name,
        brand,
        unitLabel,
        description,
        costPrice,
        sellingPrice,
        currentStockQuantity,
        reorderLevel,
        preferredSupplierId,
        preferredSupplierName,
        isActive,
        attributes,
        imageStoragePath,
        imageUrl,
        createdAt,
        updatedAt,
      ];
}
