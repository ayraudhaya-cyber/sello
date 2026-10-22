import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/orders/application/order_return_math.dart';
import 'package:sello/shared/models/order_summary.dart';

OrderLineItem _line({
  required num quantity,
  required num lineTotal,
  num? unitPrice,
}) {
  return OrderLineItem(
    id: 'line',
    productId: 'product',
    quantity: quantity,
    unitPrice: unitPrice ?? lineTotal / quantity,
    lineTotal: lineTotal,
  );
}

void main() {
  test('unpaid return comes off what they owe', () {
    final line = _line(quantity: 10, lineTotal: 1000);
    final quote = OrderReturnQuote.quote(
      orderSubtotal: 1000,
      orderTotal: 1000,
      lineShareSum: OrderReturnQuote.lineShare(line, 3),
      stillOwed: 1000,
    );
    expect(quote.returnValue, 300);
    expect(quote.owedReduction, 300);
    expect(quote.paidPortion, 0);
    expect(quote.hasPaidPortion, isFalse);
  });

  test('a paid order leaves the whole value to give back or save', () {
    final line = _line(quantity: 4, lineTotal: 400);
    final quote = OrderReturnQuote.quote(
      orderSubtotal: 400,
      orderTotal: 400,
      lineShareSum: OrderReturnQuote.lineShare(line, 1),
      stillOwed: 0,
    );
    expect(quote.returnValue, 100);
    expect(quote.owedReduction, 0);
    expect(quote.paidPortion, 100);
  });

  test('a partly paid order splits owed and paid', () {
    final line = _line(quantity: 2, lineTotal: 200);
    final quote = OrderReturnQuote.quote(
      orderSubtotal: 1000,
      orderTotal: 900,
      lineShareSum: OrderReturnQuote.lineShare(line, 2),
      stillOwed: 100,
    );
    // Line is 200 of a 1000 subtotal, on a 900 total after discount.
    expect(quote.returnValue, 180);
    expect(quote.owedReduction, 100);
    expect(quote.paidPortion, 80);
  });

  test('item discount is the gap between price and the line total', () {
    final line = _line(quantity: 4, lineTotal: 720, unitPrice: 200);
    expect(OrderReturnQuote.itemDiscountFor(line, 2), 40);
  });

  test('invoice discount follows the units being returned', () {
    expect(
      OrderReturnQuote.invoiceShare(
        orderSubtotal: 1000,
        orderDiscount: 50,
        lineShareSum: 400,
      ),
      20,
    );
  });
}
