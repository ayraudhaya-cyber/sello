import 'package:equatable/equatable.dart';

num _num(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _date(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _text(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

enum SupplierOrderStatus {
  draft,
  awaitingDelivery,
  partiallyReceived,
  received,
  cancelled;

  String get label => switch (this) {
    SupplierOrderStatus.draft => 'Draft',
    SupplierOrderStatus.awaitingDelivery => 'Awaiting delivery',
    SupplierOrderStatus.partiallyReceived => 'Partly received',
    SupplierOrderStatus.received => 'Received',
    SupplierOrderStatus.cancelled => 'Cancelled',
  };

  String get dbValue => switch (this) {
    SupplierOrderStatus.awaitingDelivery => 'awaiting_delivery',
    SupplierOrderStatus.partiallyReceived => 'partially_received',
    _ => name,
  };

  bool get canEdit =>
      this == SupplierOrderStatus.draft ||
      this == SupplierOrderStatus.awaitingDelivery;

  bool get canReceive =>
      this == SupplierOrderStatus.awaitingDelivery ||
      this == SupplierOrderStatus.partiallyReceived;

  bool get canShare =>
      this == SupplierOrderStatus.awaitingDelivery ||
      this == SupplierOrderStatus.partiallyReceived ||
      this == SupplierOrderStatus.received;

  bool get canPay => canShare;

  static SupplierOrderStatus fromDb(String? value) {
    return switch (value) {
      'awaiting_delivery' => SupplierOrderStatus.awaitingDelivery,
      'partially_received' => SupplierOrderStatus.partiallyReceived,
      'received' => SupplierOrderStatus.received,
      'cancelled' => SupplierOrderStatus.cancelled,
      _ => SupplierOrderStatus.draft,
    };
  }
}

enum SupplierPayMethod {
  cash,
  bank,
  cheque;

  String get label => switch (this) {
    SupplierPayMethod.cash => 'Cash',
    SupplierPayMethod.bank => 'Bank',
    SupplierPayMethod.cheque => 'Cheque',
  };

  String get dbValue => name;

  static SupplierPayMethod? fromDb(String? value) {
    return switch (value) {
      'cash' => SupplierPayMethod.cash,
      'bank' => SupplierPayMethod.bank,
      'cheque' => SupplierPayMethod.cheque,
      _ => null,
    };
  }
}

class SupplierOrderLine extends Equatable {
  const SupplierOrderLine({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.quantity,
    required this.receivedQuantity,
    required this.cancelledQuantity,
    required this.unitCost,
    required this.lineTotal,
    this.variantLabel,
    this.sku,
  });

  final String id;
  final String productId;
  final String variantId;
  final String productName;
  final String? variantLabel;
  final String? sku;
  final num quantity;
  final num receivedQuantity;
  final num cancelledQuantity;
  final num unitCost;
  final num lineTotal;

  String get title {
    final label = variantLabel?.trim();
    if (label != null && label.isNotEmpty && label.toLowerCase() != 'default') {
      return '$productName · $label';
    }
    return productName;
  }

  num get stillOpen {
    final value = quantity - receivedQuantity - cancelledQuantity;
    return value < 0 ? 0 : value;
  }

  factory SupplierOrderLine.fromJson(Map<String, dynamic> json) {
    return SupplierOrderLine(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      variantId: json['variant_id'] as String,
      productName: json['product_name'] as String? ?? 'Product',
      variantLabel: _text(json['variant_label']),
      sku: _text(json['sku']),
      quantity: _num(json['quantity']),
      receivedQuantity: _num(json['received_quantity']),
      cancelledQuantity: _num(json['cancelled_quantity']),
      unitCost: _num(json['unit_cost']),
      lineTotal: _num(json['line_total']),
    );
  }

  @override
  List<Object?> get props => [id, quantity, receivedQuantity, unitCost];
}

class SupplierReceiptSummary extends Equatable {
  const SupplierReceiptSummary({
    required this.id,
    required this.receiptNumber,
    required this.receivedAt,
    required this.value,
  });

  final String id;
  final String receiptNumber;
  final DateTime receivedAt;
  final num value;

  factory SupplierReceiptSummary.fromJson(Map<String, dynamic> json) {
    var value = 0.0;
    final lines = json['supplier_receipt_lines'];
    if (lines is List) {
      for (final raw in lines) {
        if (raw is Map) value += _num(raw['line_value']);
      }
    }
    return SupplierReceiptSummary(
      id: json['id'] as String,
      receiptNumber: json['receipt_number'] as String? ?? '',
      receivedAt: _date(json['received_at']) ?? DateTime.now().toUtc(),
      value: value,
    );
  }

  @override
  List<Object?> get props => [id, receiptNumber, value];
}

class SupplierPaymentSummary extends Equatable {
  const SupplierPaymentSummary({
    required this.id,
    required this.paymentNumber,
    required this.amount,
    required this.method,
    required this.status,
    required this.paidAt,
    this.reference,
  });

  final String id;
  final String paymentNumber;
  final num amount;
  final SupplierPayMethod method;
  final String status;
  final DateTime paidAt;
  final String? reference;

  bool get isPendingCheque =>
      method == SupplierPayMethod.cheque && status == 'pending';

  String get statusLabel => switch (status) {
    'pending' => 'Waiting to clear',
    'cancelled' => 'Cancelled',
    _ => 'Paid',
  };

  factory SupplierPaymentSummary.fromJson(Map<String, dynamic> json) {
    return SupplierPaymentSummary(
      id: json['id'] as String,
      paymentNumber: json['payment_number'] as String? ?? '',
      amount: _num(json['amount']),
      method: SupplierPayMethod.fromDb(json['method'] as String?) ??
          SupplierPayMethod.cash,
      status: json['status'] as String? ?? 'completed',
      paidAt: _date(json['paid_at']) ?? DateTime.now().toUtc(),
      reference: _text(json['reference']),
    );
  }

  @override
  List<Object?> get props => [id, amount, status];
}

class SupplierOrderSummary extends Equatable {
  const SupplierOrderSummary({
    required this.id,
    required this.companyId,
    required this.branchId,
    required this.supplierId,
    required this.orderNumber,
    required this.supplierName,
    required this.status,
    required this.total,
    required this.recognizedPayable,
    required this.createdAt,
    this.paymentMethod,
    this.notes,
    this.orderedAt,
    this.supplierWhatsapp,
    this.supplierPhone,
    this.amountPaid = 0,
    this.lines = const [],
    this.receipts = const [],
    this.payments = const [],
  });

  final String id;
  final String companyId;
  final String branchId;
  final String supplierId;
  final String orderNumber;
  final String supplierName;
  final SupplierOrderStatus status;
  final SupplierPayMethod? paymentMethod;
  final num total;
  final num recognizedPayable;
  final String? notes;
  final DateTime? orderedAt;
  final DateTime createdAt;
  final String? supplierWhatsapp;
  final String? supplierPhone;
  final num amountPaid;
  final List<SupplierOrderLine> lines;
  final List<SupplierReceiptSummary> receipts;
  final List<SupplierPaymentSummary> payments;

  num get stillOwed {
    final value = recognizedPayable - amountPaid;
    return value < 0 ? 0 : value;
  }

  bool get hasReceipt => lines.any((line) => line.receivedQuantity > 0);

  bool get canEditLines => status.canEdit && !hasReceipt;

  factory SupplierOrderSummary.fromJson(Map<String, dynamic> json) {
    final supplier = json['suppliers'];
    Map<String, dynamic>? supplierMap;
    if (supplier is Map) supplierMap = Map<String, dynamic>.from(supplier);

    final lines = <SupplierOrderLine>[];
    final rawLines = json['supplier_order_lines'];
    if (rawLines is List) {
      for (final raw in rawLines) {
        if (raw is Map) {
          lines.add(SupplierOrderLine.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }

    final receipts = <SupplierReceiptSummary>[];
    final rawReceipts = json['supplier_receipts'];
    if (rawReceipts is List) {
      for (final raw in rawReceipts) {
        if (raw is Map) {
          receipts.add(
            SupplierReceiptSummary.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
    }

    final payments = <SupplierPaymentSummary>[];
    var paid = 0.0;
    final rawPayments = json['supplier_payments'];
    if (rawPayments is List) {
      for (final raw in rawPayments) {
        if (raw is! Map) continue;
        final payment = SupplierPaymentSummary.fromJson(
          Map<String, dynamic>.from(raw),
        );
        payments.add(payment);
        if (payment.status == 'completed') paid += payment.amount;
      }
    }

    return SupplierOrderSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String,
      supplierId: json['supplier_id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      supplierName:
          json['supplier_name'] as String? ??
          supplierMap?['name'] as String? ??
          'Supplier',
      status: SupplierOrderStatus.fromDb(json['status'] as String?),
      paymentMethod: SupplierPayMethod.fromDb(json['payment_method'] as String?),
      total: _num(json['total']),
      recognizedPayable: _num(json['recognized_payable']),
      notes: _text(json['notes']),
      orderedAt: _date(json['ordered_at']),
      createdAt: _date(json['created_at']) ?? DateTime.now().toUtc(),
      supplierWhatsapp: _text(supplierMap?['whatsapp']),
      supplierPhone: _text(supplierMap?['phone']),
      amountPaid: paid,
      lines: lines,
      receipts: receipts,
      payments: payments,
    );
  }

  @override
  List<Object?> get props => [id, status, total, recognizedPayable, amountPaid];
}
