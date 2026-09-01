import 'package:sello/shared/models/product_field.dart';

/// Soft industry templates — recommendations only, never locking.
enum ProductIndustry {
  hardware,
  stationery,
  grocery,
  electrical,
  furniture,
  pharmacy,
  clothing;

  String get label => switch (this) {
        ProductIndustry.hardware => 'Hardware',
        ProductIndustry.stationery => 'Stationery',
        ProductIndustry.grocery => 'Grocery',
        ProductIndustry.electrical => 'Electrical',
        ProductIndustry.furniture => 'Furniture',
        ProductIndustry.pharmacy => 'Pharmacy',
        ProductIndustry.clothing => 'Clothing',
      };

  String get emoji => switch (this) {
        ProductIndustry.hardware => '🔧',
        ProductIndustry.stationery => '📚',
        ProductIndustry.grocery => '🛒',
        ProductIndustry.electrical => '⚡',
        ProductIndustry.furniture => '🛋',
        ProductIndustry.pharmacy => '💊',
        ProductIndustry.clothing => '👕',
      };

  /// Catalog group for this industry (browse filter).
  ProductDetailGroup get detailGroup => switch (this) {
        ProductIndustry.hardware => ProductDetailGroup.hardware,
        ProductIndustry.stationery => ProductDetailGroup.stationery,
        ProductIndustry.grocery => ProductDetailGroup.grocery,
        ProductIndustry.electrical => ProductDetailGroup.electrical,
        ProductIndustry.furniture => ProductDetailGroup.furniture,
        ProductIndustry.pharmacy => ProductDetailGroup.pharmacy,
        ProductIndustry.clothing => ProductDetailGroup.clothing,
      };

  /// Suggested field keys for this industry (plus Common stays available).
  List<String> get recommendedFieldKeys => switch (this) {
        ProductIndustry.hardware => const [
            'brand',
            'barcode',
            'item_code',
            'material',
            'color',
            'size',
            'made_in_country',
            'finish',
            'dimensions',
            'weight',
          ],
        ProductIndustry.stationery => const [
            'brand',
            'barcode',
            'item_code',
            'book_type',
            'ruling',
            'pages',
            'book_size',
            'cover',
            'made_in_country',
          ],
        ProductIndustry.grocery => const [
            'brand',
            'barcode',
            'pack_size',
            'net_weight',
            'expiry',
            'made_in_country',
          ],
        ProductIndustry.electrical => const [
            'brand',
            'barcode',
            'item_code',
            'voltage',
            'capacity',
            'power',
            'wattage',
            'made_in_country',
          ],
        ProductIndustry.furniture => const [
            'brand',
            'item_code',
            'furniture_material',
            'color',
            'dimensions',
            'seating_capacity',
            'finish',
            'made_in_country',
          ],
        ProductIndustry.pharmacy => const [
            'brand',
            'barcode',
            'dosage',
            'active_ingredient',
            'prescription_required',
            'expiry',
            'made_in_country',
          ],
        ProductIndustry.clothing => const [
            'brand',
            'barcode',
            'item_code',
            'clothing_size',
            'clothing_colour',
            'fabric',
            'gender',
            'made_in_country',
          ],
      };
}

/// Applies industry recommendations onto a draft field list (enable only).
abstract final class ProductIndustryRecommendations {
  static List<CompanyProductField> apply({
    required List<CompanyProductField> fields,
    required ProductIndustry industry,
  }) {
    final keys = industry.recommendedFieldKeys.toSet();
    return [
      for (final field in fields)
        if (keys.contains(field.fieldKey) && !field.enabled)
          field.copyWith(
            enabled: true,
            showInCatalog: true,
            showInList: field.showInList ||
                field.definition.group == ProductDetailGroup.common,
          )
        else
          field,
    ];
  }
}
