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
}
