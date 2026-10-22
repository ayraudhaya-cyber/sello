import 'package:equatable/equatable.dart';

/// Where money the customer had already paid goes.
enum OrderReturnStatus {
  recorded,
  cancelled;

  String get label => switch (this) {
    OrderReturnStatus.recorded => 'Recorded',
    OrderReturnStatus.cancelled => 'Cancelled',
  };

  static OrderReturnStatus fromDb(String? value) {
    return value == 'cancelled'
        ? OrderReturnStatus.cancelled
        : OrderReturnStatus.recorded;
  }
}

enum OrderReturnDestination {
  none,
  cash,
  wallet;

  String get dbValue => name;

  static OrderReturnDestination fromDb(String? value) {
    return switch (value) {
      'cash' => OrderReturnDestination.cash,
      'wallet' => OrderReturnDestination.wallet,
      _ => OrderReturnDestination.none,
    };
  }
}

/// Figures the return screen needs before a quantity is chosen.
class OrderReturnContext extends Equatable {
  const OrderReturnContext({
    required this.netDelivered,
    required this.amountPaid,
    required this.stillOwed,
    required this.approvalWaiting,
    required this.chequeWaiting,
  });

  final num netDelivered;
  final num amountPaid;
  final num stillOwed;
  final bool approvalWaiting;
  final bool chequeWaiting;

  /// A waiting approval blocks the whole return.
  String? get approvalGuide => approvalWaiting
      ? 'A payment on this order is still waiting for approval. '
            'Open Payments, approve or reject that payment, then record the return.'
      : null;

  /// An uncleared cheque blocks only money that was already paid.
  String? get chequeGuide => chequeWaiting
      ? 'A cheque on this order has not cleared yet. Clear it on Payments '
            'before giving money back or saving it. You can still return only '
            'what they have not paid.'
      : null;

  factory OrderReturnContext.fromJson(Map<String, dynamic> json) {
    return OrderReturnContext(
      netDelivered: _num(json['net_delivered']),
      amountPaid: _num(json['amount_paid']),
      stillOwed: _num(json['still_owed']),
      approvalWaiting: json['approval_waiting'] == true,
      chequeWaiting: json['cheque_waiting'] == true,
    );
  }

  @override
  List<Object?> get props => [stillOwed, approvalWaiting, chequeWaiting];
}

/// A product line on a recorded return, for the register.
class OrderReturnLineLabel extends Equatable {
  const OrderReturnLineLabel({
    required this.title,
    required this.quantity,
    this.value = 0,
  });

  final String title;
  final num quantity;
  final num value;

  @override
  List<Object?> get props => [title, quantity, value];
}

/// One recorded return, for the register and the order.
class OrderReturnSummary extends Equatable {
  const OrderReturnSummary({
    required this.id,
    required this.returnNumber,
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.returnValue,
    required this.owedReduction,
    required this.paidPortion,
    required this.destination,
    required this.restock,
    required this.returnedAt,
    this.status = OrderReturnStatus.recorded,
    this.lines = const [],
  });

  final String id;
  final String returnNumber;
  final String orderId;
  final String orderNumber;
  final String customerName;
  final num returnValue;
  final num owedReduction;
  final num paidPortion;
  final OrderReturnDestination destination;
  final bool restock;
  final DateTime returnedAt;
  final OrderReturnStatus status;
  final List<OrderReturnLineLabel> lines;

  bool get isCancelled => status == OrderReturnStatus.cancelled;

  /// Same local calendar day. The server uses Sri Lanka time as the final check.
  bool get canCancelToday {
    if (isCancelled) return false;
    final local = returnedAt.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  String get moneyLabel {
    final parts = <String>[];
    if (owedReduction > 0.001) parts.add('Comes off what they owe');
    if (paidPortion > 0.001) {
      parts.add(
        destination == OrderReturnDestination.wallet
            ? 'Saved for next order'
            : 'Given back',
      );
    }
    if (parts.isEmpty) return '—';
    return parts.join(' · ');
  }

  String get stockLabel => restock ? 'Back in stock' : 'Not for sale';

  factory OrderReturnSummary.fromJson(Map<String, dynamic> json) {
    final lines = <OrderReturnLineLabel>[];
    final rawLines = json['order_return_lines'];
    if (rawLines is List) {
      for (final raw in rawLines) {
        if (raw is! Map) continue;
        final line = Map<String, dynamic>.from(raw);
        final item = line['order_items'];
        Map<String, dynamic>? itemMap;
        if (item is Map<String, dynamic>) {
          itemMap = item;
        } else if (item is Map) {
          itemMap = Map<String, dynamic>.from(item);
        }
        final name = (itemMap?['product_name'] as String?)?.trim();
        final variant = (itemMap?['variant_label'] as String?)?.trim();
        final title = (name == null || name.isEmpty)
            ? 'Item'
            : (variant != null &&
                  variant.isNotEmpty &&
                  variant.toLowerCase() != 'default')
            ? '$name · $variant'
            : name;
        lines.add(
          OrderReturnLineLabel(
            title: title,
            quantity: _num(line['quantity']),
            value: _num(line['line_value']),
          ),
        );
      }
    }

    return OrderReturnSummary(
      id: json['id'] as String,
      returnNumber: (json['return_number'] as String?)?.trim() ?? '',
      orderId: json['order_id'] as String,
      orderNumber: (json['order_number'] as String?)?.trim() ?? '',
      customerName: (json['customer_name'] as String?)?.trim() ?? '',
      returnValue: _num(json['return_value']),
      owedReduction: _num(json['owed_reduction']),
      paidPortion: _num(json['paid_portion']),
      destination: OrderReturnDestination.fromDb(
        json['paid_destination'] as String?,
      ),
      restock: json['restock'] != false,
      returnedAt:
          DateTime.tryParse(json['returned_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
      status: OrderReturnStatus.fromDb(json['status'] as String?),
      lines: lines,
    );
  }

  factory OrderReturnSummary.fromResult(Map<String, dynamic> json) {
    return OrderReturnSummary(
      id: json['id'] as String,
      returnNumber: (json['return_number'] as String?)?.trim() ?? '',
      orderId: '',
      orderNumber: '',
      customerName: '',
      returnValue: _num(json['return_value']),
      owedReduction: _num(json['owed_reduction']),
      paidPortion: _num(json['paid_portion']),
      destination: OrderReturnDestination.fromDb(
        json['paid_destination'] as String?,
      ),
      restock: json['restock'] != false,
      returnedAt: DateTime.now().toUtc(),
      status: OrderReturnStatus.recorded,
    );
  }

  @override
  List<Object?> get props => [id, returnNumber, returnValue, returnedAt];
}

num _num(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}
