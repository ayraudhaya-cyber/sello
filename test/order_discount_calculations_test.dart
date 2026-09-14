import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/order_upsert_input.dart';

void main() {
  group('OrderCalculations header discounts', () {
    test('amount only', () {
      expect(
        OrderCalculations.grandTotal(subtotal: 1000, orderDiscount: 100),
        900,
      );
    });

    test('percent only', () {
      expect(
        OrderCalculations.grandTotal(
          subtotal: 1000,
          orderDiscountPercent: 10,
        ),
        900,
      );
    });

    test('percent then amount', () {
      // 10% of 1000 = 100 → 900, then −50 → 850
      expect(
        OrderCalculations.grandTotal(
          subtotal: 1000,
          orderDiscount: 50,
          orderDiscountPercent: 10,
        ),
        850,
      );
      expect(
        OrderCalculations.resolvedOrderDiscount(
          subtotal: 1000,
          orderDiscountAmount: 50,
          orderDiscountPercent: 10,
        ),
        150,
      );
    });

    test('amount cannot exceed after-percent subtotal', () {
      expect(
        OrderCalculations.grandTotal(
          subtotal: 100,
          orderDiscount: 200,
          orderDiscountPercent: 10,
        ),
        0,
      );
    });
  });
}
