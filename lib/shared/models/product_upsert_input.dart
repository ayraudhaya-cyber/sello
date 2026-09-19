/// Draft sellable option under a parent product (editor / save path).
///
/// [id] is null for a newly created option. Existing ids must be preserved so
/// stock movements and order history stay attached to the same variant row.
class ProductVariantDraft {
  const ProductVariantDraft({
    this.id,
    required this.label,
    required this.sku,
    this.barcode,
    required this.sellingPrice,
    this.unitCost,
    this.isActive = true,
    this.isDefault = false,
    this.sortOrder = 0,
    this.openingStock,
  });

  final String? id;
  final String label;
  final String sku;
  final String? barcode;
  final num sellingPrice;

  /// Null means leave the existing cost unchanged (caller cannot view cost).
  final num? unitCost;
  final bool isActive;
  final bool isDefault;
  final int sortOrder;

  /// Initial inventory qty for a newly created option (create / add-option).
  /// Never used to overwrite stock on an existing variant id.
  final num? openingStock;
}

class ProductUpsertInput {
  const ProductUpsertInput({
    this.productId,
    required this.name,
    required this.sku,
    required this.categoryName,
    required this.sellingPrice,
    required this.costPrice,
    required this.currentStockQuantity,
    required this.reorderLevel,
    this.barcode,
    this.brand,
    this.unitLabel,
    this.description,
    this.isActive = true,
    this.preferredSupplierId,
    this.attributes = const {},
    this.variants,
  });

  final String? productId;
  final String name;
  final String sku;
  final String categoryName;
  final String? barcode;
  final String? brand;
  final String? unitLabel;
  final num sellingPrice;
  final num costPrice;
  final num currentStockQuantity;
  final num reorderLevel;
  final String? description;
  final bool isActive;

  /// Primary supplier for sourcing (null clears the link).
  final String? preferredSupplierId;

  /// Spec fields stored in `products.attributes`.
  final Map<String, String> attributes;

  /// When non-null and length > 1, option rows are authoritative for sellable
  /// fields. Null / a single mirrored draft keeps the simple-product path.
  final List<ProductVariantDraft>? variants;

  /// True when the save must manage multiple live option rows.
  bool get managesMultipleVariants =>
      variants != null && variants!.length > 1;
}
