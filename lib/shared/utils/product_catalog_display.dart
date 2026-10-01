import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Selling price for catalog cards and presentation.
///
/// Multi-option products show the range of active option prices instead of
/// the parent row's single price (often copied from the default option).
String productCatalogPriceLabel(
  ProductSummary product, {
  required String symbol,
}) {
  final range = product.activePriceRange;
  if (range == null) {
    return SelloFormatters.currency(product.sellingPrice, symbol: symbol);
  }
  final low = SelloFormatters.currency(range.low, symbol: symbol);
  if (range.low == range.high) return low;
  return '$low – ${SelloFormatters.currency(range.high, symbol: symbol)}';
}

/// Leading catalog subtitle token — parent SKU, or option count when
/// there is more than one sellable option.
String productCatalogIdentityHint(ProductSummary product) {
  if (product.hasMultipleActiveVariants) {
    return '${product.activeOptionCount} options';
  }
  return product.sku;
}
