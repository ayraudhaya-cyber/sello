import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_record_status.dart';

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
  if (value is Map) return _stringValue(value[key]);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return _stringValue((value.first as Map)[key]);
  }
  return null;
}

class PaymentAllocation extends Equatable {
  const PaymentAllocation({
    required this.id,
    required this.amount,
    this.orderId,
    this.orderNumber,
    this.receivableAdjustmentId,
    this.adjustmentNumber,
    this.adjustmentReferenceNumber,
  });

  final String id;
  final String? orderId;
  final num amount;
  final String? orderNumber;
  final String? receivableAdjustmentId;
  final String? adjustmentNumber;

  /// Pre-Sello invoice / reference on an opening-balance allocation.
  final String? adjustmentReferenceNumber;

  bool get isOpeningBalance =>
      receivableAdjustmentId != null && receivableAdjustmentId!.isNotEmpty;

  /// Order number, or "Opening balance · OB-…" for adjustment allocations.
  String get displayLabel {
    if (isOpeningBalance) {
      final number = adjustmentNumber?.trim();
      if (number != null && number.isNotEmpty) {
        return 'Opening balance · $number';
      }
      return 'Opening balance';
    }
    final order = orderNumber?.trim();
    if (order != null && order.isNotEmpty) return order;
    return orderId ?? '';
  }

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) {
    return PaymentAllocation(
      id: json['id'] as String,
      orderId: json['order_id'] as String?,
      amount: _numValue(json['amount']),
      orderNumber: _embedName(json['orders'], 'order_number'),
      receivableAdjustmentId: json['receivable_adjustment_id'] as String?,
      adjustmentNumber: _embedName(
        json['customer_receivable_adjustments'],
        'adjustment_number',
      ),
      adjustmentReferenceNumber: _embedName(
        json['customer_receivable_adjustments'],
        'reference_number',
      ),
    );
  }

  @override
  List<Object?> get props => [
        id,
        orderId,
        amount,
        receivableAdjustmentId,
        adjustmentReferenceNumber,
      ];
}

class PaymentSummary extends Equatable {
  const PaymentSummary({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.employeeId,
    required this.paymentNumber,
    required this.amount,
    required this.method,
    required this.status,
    required this.receivedAt,
    this.customerName,
    this.customerPhone,
    this.employeeName,
    this.reference,
    this.notes,
    this.relatedOrderNumber,
    this.refundedAt,
    this.cancelledAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewerName,
    this.rejectionReason,
    this.correctsPaymentId,
    this.correctedByPaymentId,
    this.correctionReason,
    this.allocations = const [],
  });

  final String id;
  final String companyId;
  final String customerId;
  final String employeeId;
  final String paymentNumber;
  final num amount;
  final PaymentMethod method;
  final PaymentRecordStatus status;
  final DateTime receivedAt;
  final String? customerName;
  final String? customerPhone;
  final String? employeeName;
  final String? reference;
  final String? notes;
  final String? relatedOrderNumber;
  final DateTime? refundedAt;
  final DateTime? cancelledAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewerName;
  final String? rejectionReason;
  final String? correctsPaymentId;
  final String? correctedByPaymentId;
  final String? correctionReason;

  /// What this collection paid (orders and/or opening-balance invoices).
  final List<PaymentAllocation> allocations;

  bool get paysOrder => allocations.any((a) => !a.isOpeningBalance);

  bool get paysOpeningBalance => allocations.any((a) => a.isOpeningBalance);

  /// Plain-language type for lists and exports.
  String get collectionTypeLabel {
    if (paysOrder && paysOpeningBalance) return 'Order + Opening balance';
    if (paysOpeningBalance) return 'Opening balance';
    if (paysOrder) return 'Order';
    return 'On account';
  }

  /// "SO-1001, Opening balance · OB-0003" — empty when nothing is allocated.
  String get allocationSummary => allocations
      .map((a) => a.displayLabel.trim())
      .where((label) => label.isNotEmpty)
      .join(', ');

  bool get isCorrected =>
      status == PaymentRecordStatus.cancelled &&
      (correctedByPaymentId ?? '').isNotEmpty;

  String get displayStatusLabel => isCorrected ? 'Corrected' : status.label;

  factory PaymentSummary.fromJson(Map<String, dynamic> json) {
    String? relatedOrder;
    final allocations = json['payment_allocations'];
    if (allocations is List && allocations.isNotEmpty) {
      final first = allocations.first;
      if (first is Map) {
        relatedOrder = _embedName(first['orders'], 'order_number');
        if (allocations.length > 1 && relatedOrder != null) {
          relatedOrder = '$relatedOrder +${allocations.length - 1}';
        }
      }
    }

    return PaymentSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      customerId: json['customer_id'] as String,
      employeeId: json['employee_id'] as String,
      paymentNumber: json['payment_number'] as String? ?? '',
      amount: _numValue(json['amount']),
      method:
          PaymentMethod.fromDb(json['method'] as String?) ?? PaymentMethod.cash,
      status: PaymentRecordStatus.fromDb(json['status'] as String?),
      receivedAt: _dateValue(json['received_at']) ?? DateTime.now().toUtc(),
      customerName: _embedName(json['customers'], 'name'),
      customerPhone: _embedName(json['customers'], 'phone'),
      employeeName: _embedName(json['employees'], 'full_name'),
      reference: _stringValue(json['reference']),
      notes: _stringValue(json['notes']),
      relatedOrderNumber: relatedOrder,
      refundedAt: _dateValue(json['refunded_at']),
      cancelledAt: _dateValue(json['cancelled_at']),
      reviewedBy: _stringValue(json['reviewed_by']),
      reviewedAt: _dateValue(json['reviewed_at']),
      reviewerName: _embedName(json['reviewed_by_employee'], 'full_name'),
      rejectionReason: _stringValue(json['rejection_reason']),
      correctsPaymentId: json['corrects_payment_id'] as String?,
      correctedByPaymentId: json['corrected_by_payment_id'] as String?,
      correctionReason: _stringValue(json['correction_reason']),
      allocations: [
        if (allocations is List)
          for (final raw in allocations)
            if (raw is Map && raw['id'] is String)
              PaymentAllocation.fromJson(Map<String, dynamic>.from(raw)),
      ],
    );
  }

  @override
  List<Object?> get props => [id, paymentNumber, amount, status, receivedAt];
}

class PaymentDetail extends Equatable {
  const PaymentDetail({
    required this.summary,
    required this.allocations,
    this.customerOutstanding,
    this.customerWallet,
    this.customerCreditAllowed,
    this.customerCreditLimit,
  });

  final PaymentSummary summary;
  final List<PaymentAllocation> allocations;
  final num? customerOutstanding;
  final num? customerWallet;
  final bool? customerCreditAllowed;
  final num? customerCreditLimit;

  @override
  List<Object?> get props => [summary, allocations];
}

class PaymentDashboardStats {
  const PaymentDashboardStats({
    required this.collectedToday,
    required this.outstandingReceivables,
    required this.walletIssued,
    required this.pendingCredit,
  });

  final num collectedToday;
  final num outstandingReceivables;
  final num walletIssued;
  final num pendingCredit;
}

class PaymentAllocationInput {
  const PaymentAllocationInput({
    this.orderId,
    this.receivableAdjustmentId,
    required this.amount,
  });

  factory PaymentAllocationInput.fromReceivable(
    ReceivableOrder receivable,
    num amount,
  ) {
    if (receivable.isOpeningBalance) {
      return PaymentAllocationInput(
        receivableAdjustmentId: receivable.id,
        amount: amount,
      );
    }
    return PaymentAllocationInput(orderId: receivable.id, amount: amount);
  }

  final String? orderId;
  final String? receivableAdjustmentId;
  final num amount;

  Map<String, dynamic> toJson() {
    if (receivableAdjustmentId != null && receivableAdjustmentId!.isNotEmpty) {
      return {
        'receivable_adjustment_id': receivableAdjustmentId,
        'amount': amount,
      };
    }
    return {'order_id': orderId, 'amount': amount};
  }
}

class ReceivePaymentInput {
  const ReceivePaymentInput({
    required this.customerId,
    required this.amount,
    required this.method,
    this.allocations = const [],
    this.reference,
    this.notes,
    this.visitId,
  });

  final String customerId;
  final num amount;
  final PaymentMethod method;
  final List<PaymentAllocationInput> allocations;
  final String? reference;
  final String? notes;

  /// Operational customer visit this payment was collected during.
  final String? visitId;
}

/// Result of [PaymentRepository.receivePayment].
class ReceivePaymentResult {
  const ReceivePaymentResult({
    required this.paymentId,
    required this.status,
    this.acknowledgement,
  });

  final String paymentId;
  final PaymentRecordStatus status;

  /// Outbound share intents when a pending collection acknowledgement was prepared.
  final OrderConfirmationOutcome? acknowledgement;

  bool get isPendingReview => status.isPendingReview;
}

/// One collection already linked to a specific order.
class OrderCollectionEntry {
  const OrderCollectionEntry({
    required this.paymentId,
    required this.paymentNumber,
    required this.amount,
    required this.method,
    required this.status,
    required this.receivedAt,
  });

  final String paymentId;
  final String paymentNumber;
  final num amount;
  final PaymentMethod method;
  final PaymentRecordStatus status;
  final DateTime receivedAt;

  bool get countsTowardPaid => status == PaymentRecordStatus.completed;
}

class OrderCollectionBalance {
  const OrderCollectionBalance({
    required this.entries,
    required this.amountPaid,
    this.amountPending = 0,
  });

  final List<OrderCollectionEntry> entries;

  /// Sum of completed allocations on this order.
  final num amountPaid;

  /// Collections waiting for approval. They are reserved against this order.
  final num amountPending;

  num outstandingFor(num total) =>
      (total - amountPaid - amountPending).clamp(0, double.infinity);
}

enum ReceivableKind { openingBalance, order }

/// Outstanding order or opening-balance row for the receive-payment picker.
class ReceivableOrder {
  const ReceivableOrder({
    required this.id,
    required this.orderNumber,
    required this.total,
    required this.amountPaid,
    required this.orderedAt,
    this.kind = ReceivableKind.order,
    this.referenceNumber,
  });

  final String id;
  final String orderNumber;
  final num total;
  final num amountPaid;

  /// Order [orderedAt], or opening-balance [recognizedAt].
  final DateTime orderedAt;
  final ReceivableKind kind;

  /// Pre-Sello invoice / reference on opening-balance receivables.
  final String? referenceNumber;

  bool get isOpeningBalance => kind == ReceivableKind.openingBalance;

  num get remaining => (total - amountPaid).clamp(0, double.infinity);

  String get pickerTitle =>
      isOpeningBalance ? 'Opening balance' : orderNumber;
}
