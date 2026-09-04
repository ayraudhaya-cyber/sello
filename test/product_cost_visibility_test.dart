import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/product_summary.dart';

void main() {
  test('ProductSummary treats null cost_price as zero (Sales-safe API)', () {
    final product = ProductSummary.fromQueryRow({
      'id': 'p1',
      'company_id': 'c1',
      'name': 'Widget',
      'sku': 'W-1',
      'selling_price': 100,
      'cost_price': null,
      'is_active': true,
      'inventory': const [],
    });

    expect(product.costPrice, 0);
    expect(product.sellingPrice, 100);
  });
}
