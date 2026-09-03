import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_timeline.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _stringValue(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _embedName(dynamic value, String key) {
  if (value is Map<String, dynamic>) {
    return _stringValue(value[key]);
  }
  if (value is List && value.isNotEmpty && value.first is Map) {
    return _stringValue((value.first as Map)[key]);
  }
  return null;
}

String? _embedId(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value['id'] as String?;
  }
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map)['id'] as String?;
  }
  return null;
}

/// List-row summary for Hub / Sales order lists.
class OrderSummary extends Equatable {
  const OrderSummary({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.customerId,
    required this.employeeId,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.orderedAt,
    required this.updatedAt,
    this.paymentMethod,
    this.customerName,
    this.customerPhone,
    this.employeeName,
    this.notes,
    this.completedAt,
    this.cancelledAt,
  });

  final String id;
  final String companyId;
  final String branchId;
  final String customerId;
  final String employeeId;
  final String orderNumber;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod? paymentMethod;
  final num subtotal;
  final num discountAmount;
  final num taxAmount;
  final num total;
  final DateTime orderedAt;
  final DateTime updatedAt;
  final String? customerName;
  final String? customerPhone;
  final String? employeeName;
  final String? notes;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  bool get isDraft => status == OrderStatus.draft;
  bool get isEditable => status == OrderStatus.draft;

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String,
      customerId: json['customer_id'] as String? ??
          _embedId(json['customers']) ??
          '',
      employeeId: json['employee_id'] as String? ??
          _embedId(json['employees']) ??
          '',
      orderNumber: json['order_number'] as String? ?? '',
      status: OrderStatus.fromDb(json['status'] as String?),
      paymentStatus: PaymentStatus.fromDb(json['payment_status'] as String?),
      paymentMethod: PaymentMethod.fromDb(json['payment_method'] as String?),
      subtotal: _numValue(json['subtotal']),
      discountAmount: _numValue(json['discount_amount']),
      taxAmount: _numValue(json['tax_amount']),
      total: _numValue(json['total']),
      orderedAt: _dateValue(json['ordered_at']) ?? DateTime.now().toUtc(),
      updatedAt: _dateValue(json['updated_at']) ?? DateTime.now().toUtc(),
      customerName: _embedName(json['customers'], 'name'),
      customerPhone: _embedName(json['customers'], 'phone'),
      employeeName: _embedName(json['employees'], 'full_name'),
      notes: _stringValue(json['notes']),
      completedAt: _dateValue(json['completed_at']),
      cancelledAt: _dateValue(json['cancelled_at']),
    );
  }

  @override
  List<Object?> get props => [id, orderNumber, status, total, updatedAt];
}

class OrderLineItem extends Equatable {
  const OrderLineItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.deliveredQuantity = 0,
    this.cancelledQuantity = 0,
    this.productName,
    this.productSku,
    this.imageUrl,
    this.discount,
    this.discountType,
    this.productBrand,
    this.productAttributes = const {},
  });

  final String id;
  final String productId;
  /// Ordered / requested quantity (customer demand).
  final num quantity;
  /// Cumulative quantity actually fulfilled (inventory deducted).
  final num deliveredQuantity;
  /// Cumulative quantity closed without delivery.
  final num cancelledQuantity;
  final num unitPrice;
  final num lineTotal;
  final String? productName;
  final String? productSku;
  final String? imageUrl;
  final num? discount;
  final String? discountType;
  final String? productBrand;
  final Map<String, String> productAttributes;

  /// Outstanding quantity still open for delivery or cancel.
  num get remainingQuantity {
    final value = quantity - deliveredQuantity - cancelledQuantity;
    return value < 0 ? 0 : value;
  }

  factory OrderLineItem.fromJson(Map<String, dynamic> json) {
    final products = json['products'];
    Map<String, dynamic>? productMap;
    if (products is Map<String, dynamic>) {
      productMap = products;
    } else if (products is Map) {
      productMap = Map<String, dynamic>.from(products);
    }

    final attrs = <String, String>{};
    final rawAttrs = productMap?['attributes'];
    if (rawAttrs is Map) {
      for (final entry in rawAttrs.entries) {
        final value = entry.value?.toString().trim();
        if (value != null && value.isNotEmpty) {
          attrs[entry.key.toString()] = value;
        }
      }
    }

    return OrderLineItem(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      quantity: _numValue(json['quantity']),
      deliveredQuantity: _numValue(json['delivered_quantity']),
      cancelledQuantity: _numValue(json['cancelled_quantity']),
      unitPrice: _numValue(json['unit_price']),
      lineTotal: _numValue(json['line_total']),
      productName: _embedName(json['products'], 'name'),
      productSku: _embedName(json['products'], 'sku'),
      imageUrl: null,
      discount: json['discount'] == null ? null : _numValue(json['discount']),
      discountType: _stringValue(json['discount_type']),
      productBrand: _embedName(json['products'], 'brand'),
      productAttributes: attrs,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        quantity,
        deliveredQuantity,
        cancelledQuantity,
        lineTotal,
      ];
}

class OrderDetail extends Equatable {
  const OrderDetail({
    required this.summary,
    required this.lines,
    this.customerOutstanding,
    this.customerWallet,
    this.customerCreditAllowed,
    this.customerCreditLimit,
    this.timeline = const [],
  });

  final OrderSummary summary;
  final List<OrderLineItem> lines;
  final num? customerOutstanding;
  final num? customerWallet;
  final bool? customerCreditAllowed;
  final num? customerCreditLimit;
  final List<OrderTimelineEvent> timeline;

  @override
  List<Object?> get props => [summary, lines, timeline];
}

class OrderCounts {
  const OrderCounts({
    required this.total,
    required this.draft,
    required this.completed,
    required this.cancelled,
  });

  final int total;
  final int draft;
  final int completed;
  final int cancelled;
}

/// Open fulfillment demand counts for Hub Needs Attention.
class FulfillmentAttentionCounts {
  const FulfillmentAttentionCounts({
    this.placed = 0,
    this.partiallyDelivered = 0,
    this.waitingPlaced = 0,
    this.waitingPartial = 0,
  });

  final int placed;
  final int partiallyDelivered;
  final int waitingPlaced;
  final int waitingPartial;
}

class SalesRepOption {
  const SalesRepOption({
    required this.id,
    required this.name,
    this.roleCode,
  });

  final String id;
  final String name;

  /// `roles.code` when loaded — used for IAM eligibility filters.
  final String? roleCode;

  bool get canPerformFieldVisits =>
      RolePermissionProfile.roleCanPerformFieldVisits(roleCode);
}
