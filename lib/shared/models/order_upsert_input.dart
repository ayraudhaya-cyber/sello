import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';

/// Shared order math — quantity × price − discount (+ future tax).
abstract final class OrderCalculations {
  static num lineDiscountAmount({
    required num quantity,
    required num unitPrice,
    num? discount,
    String? discountType,
  }) {
    if (discount == null || discount <= 0 || discountType == null) return 0;
    final gross = quantity * unitPrice;
    if (discountType == 'percentage') {
      return (gross * (discount / 100)).clamp(0, gross);
    }
    return discount.clamp(0, gross);
  }

  static num lineTotal({
    required num quantity,
    required num unitPrice,
    num? discount,
    String? discountType,
  }) {
    final gross = quantity * unitPrice;
    return (gross -
            lineDiscountAmount(
              quantity: quantity,
              unitPrice: unitPrice,
              discount: discount,
              discountType: discountType,
            ))
        .clamp(0, double.infinity);
  }

  static num subtotal(Iterable<num> lineTotals) =>
      lineTotals.fold<num>(0, (sum, value) => sum + value);

  static num grandTotal({
    required num subtotal,
    num orderDiscount = 0,
    num taxAmount = 0,
  }) {
    final afterDiscount = (subtotal - orderDiscount).clamp(0, double.infinity);
    return afterDiscount + taxAmount;
  }
}

class OrderLineDraft {
  OrderLineDraft({
    required this.productId,
    required this.productName,
    this.productSku,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    this.availableStock,
    this.unitLabel,
    this.discount,
    this.discountType,
    this.existingItemId,
    this.productBrand,
    this.productAttributes = const {},
  });

  final String productId;
  final String productName;
  final String? productSku;
  final String? imageUrl;
  num unitPrice;
  num quantity;
  final num? availableStock;
  final String? unitLabel;
  num? discount;
  String? discountType;
  final String? existingItemId;
  final String? productBrand;
  final Map<String, String> productAttributes;

  num get lineTotal => OrderCalculations.lineTotal(
        quantity: quantity,
        unitPrice: unitPrice,
        discount: discount,
        discountType: discountType,
      );

  OrderLineDraft copyWith({
    num? unitPrice,
    num? quantity,
    num? availableStock,
    num? discount,
    String? discountType,
    bool clearDiscount = false,
  }) {
    return OrderLineDraft(
      productId: productId,
      productName: productName,
      productSku: productSku,
      imageUrl: imageUrl,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      availableStock: availableStock ?? this.availableStock,
      unitLabel: unitLabel,
      discount: clearDiscount ? null : (discount ?? this.discount),
      discountType: clearDiscount ? null : (discountType ?? this.discountType),
      existingItemId: existingItemId,
      productBrand: productBrand,
      productAttributes: productAttributes,
    );
  }
}

class OrderUpsertInput {
  const OrderUpsertInput({
    this.orderId,
    required this.customerId,
    required this.lines,
    this.notes,
    this.paymentMethod,
    this.paymentStatus = PaymentStatus.unpaid,
    this.orderDiscount = 0,
    this.taxAmount = 0,
    this.status = OrderStatus.draft,
    this.visitId,
    this.offlineClientId,
  });

  final String? orderId;
  final String customerId;
  final List<OrderLineDraft> lines;
  final String? notes;
  final PaymentMethod? paymentMethod;
  final PaymentStatus paymentStatus;
  final num orderDiscount;
  final num taxAmount;
  final OrderStatus status;

  /// Operational customer visit this order was created during.
  final String? visitId;

  /// Idempotent offline key — maps to `orders.offline_client_id`.
  final String? offlineClientId;

  num get subtotal =>
      OrderCalculations.subtotal(lines.map((line) => line.lineTotal));

  num get total => OrderCalculations.grandTotal(
        subtotal: subtotal,
        orderDiscount: orderDiscount,
        taxAmount: taxAmount,
      );
}
