import 'package:equatable/equatable.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

String? _stringValue(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, String> _optionsMap(dynamic raw) {
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

/// Sellable unit under a parent product.
///
/// Inventory, stock movements, and order lines are keyed by [id]; the parent
/// `products` row stays the catalog/family record. Every product has exactly
/// one live default variant, so simple products still have a sellable identity.
class ProductVariant extends Equatable {
  const ProductVariant({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.sku,
    required this.sellingPrice,
    required this.isDefault,
    required this.isActive,
    this.label,
    this.barcode,
    this.unitCost,
    this.options = const {},
    this.sortOrder = 0,
    this.stockQuantity,
    this.availableStockQuantity,
  });

  final String id;
  final String companyId;
  final String productId;

  /// Null/empty for the hidden default variant of a simple product.
  final String? label;
  final String sku;
  final String? barcode;
  final num sellingPrice;

  /// Only populated for cost-visible callers; the catalog select omits it so
  /// Sales never receives variant cost.
  final num? unitCost;
  final Map<String, String> options;
  final int sortOrder;
  final bool isDefault;
  final bool isActive;

  /// Branch on-hand for this variant when inventory is joined.
  final num? stockQuantity;

  /// Branch on-hand minus reserved when inventory is joined.
  final num? availableStockQuantity;

  bool get hasLabel => label != null && label!.trim().isNotEmpty;

  /// Option name for Hub/Sales UI — never exposes the internal "Default" label.
  String get optionDisplayName {
    if (hasLabel) {
      final text = label!.trim();
      if (text.toLowerCase() != 'default') return text;
    }
    final code = sku.trim();
    return code.isNotEmpty ? code : 'Option';
  }

  /// Label for UI that still shows a single sellable unit per product.
  String displayLabel(String productName) =>
      hasLabel && label!.trim().toLowerCase() != 'default'
          ? '$productName · ${label!.trim()}'
          : productName;

  ProductVariant copyWith({
    num? stockQuantity,
    num? availableStockQuantity,
  }) {
    return ProductVariant(
      id: id,
      companyId: companyId,
      productId: productId,
      label: label,
      sku: sku,
      barcode: barcode,
      sellingPrice: sellingPrice,
      unitCost: unitCost,
      options: options,
      sortOrder: sortOrder,
      isDefault: isDefault,
      isActive: isActive,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      availableStockQuantity:
          availableStockQuantity ?? this.availableStockQuantity,
    );
  }

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      productId: json['product_id'] as String,
      label: _stringValue(json['label']),
      sku: json['sku'] as String? ?? '',
      barcode: _stringValue(json['barcode']),
      sellingPrice: _numValue(json['selling_price']),
      unitCost: json['unit_cost'] == null ? null : _numValue(json['unit_cost']),
      options: _optionsMap(json['options']),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isDefault: json['is_default'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Parses an embedded `product_variants (...)` array, ordered for display.
  static List<ProductVariant> listFromEmbed(dynamic raw) {
    if (raw is! List) return const [];
    final parsed = <ProductVariant>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (map['id'] is! String) continue;
      if (map['deleted_at'] != null) continue;
      parsed.add(ProductVariant.fromJson(map));
    }
    parsed.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.sku.compareTo(b.sku);
    });
    return parsed;
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        productId,
        label,
        sku,
        barcode,
        sellingPrice,
        unitCost,
        options,
        sortOrder,
        isDefault,
        isActive,
        stockQuantity,
        availableStockQuantity,
      ];
}
