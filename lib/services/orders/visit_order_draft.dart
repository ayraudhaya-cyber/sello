/// Local visit-order draft — identifiers + quantities, not full product blobs.
class VisitOrderDraft {
  const VisitOrderDraft({
    required this.companyId,
    required this.employeeId,
    required this.lines,
    required this.updatedAt,
    this.customerId,
    this.customerName,
    this.walkIn = false,
    this.scheduledVisitId,
    this.visitNotes,
    this.stage = VisitOrderDraftStage.catalog,
    this.arrangement,
    this.chequeFollowUpAt,
    this.runningTotal = 0,
    this.orderDiscount = 0,
    this.orderDiscountPercent = 0,
  });

  final String companyId;
  final String employeeId;
  final String? customerId;
  final String? customerName;
  final bool walkIn;
  final String? scheduledVisitId;
  final List<VisitOrderDraftLine> lines;
  final String? visitNotes;
  final VisitOrderDraftStage stage;
  final String? arrangement;
  final DateTime? chequeFollowUpAt;
  final DateTime updatedAt;
  final num runningTotal;
  final num orderDiscount;
  final num orderDiscountPercent;

  bool get hasLines => lines.isNotEmpty;

  num get itemQuantity =>
      lines.fold<num>(0, (sum, line) => sum + line.quantity);

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'employeeId': employeeId,
        'customerId': customerId,
        'customerName': customerName,
        'walkIn': walkIn,
        'scheduledVisitId': scheduledVisitId,
        'lines': lines.map((line) => line.toJson()).toList(),
        'visitNotes': visitNotes,
        'stage': stage.name,
        'arrangement': arrangement,
        'chequeFollowUpAt': chequeFollowUpAt?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'runningTotal': runningTotal,
        'orderDiscount': orderDiscount,
        'orderDiscountPercent': orderDiscountPercent,
      };

  factory VisitOrderDraft.fromJson(Map<String, dynamic> json) {
    return VisitOrderDraft(
      companyId: json['companyId'] as String,
      employeeId: json['employeeId'] as String,
      customerId: json['customerId'] as String?,
      customerName: json['customerName'] as String?,
      walkIn: json['walkIn'] as bool? ?? false,
      scheduledVisitId: json['scheduledVisitId'] as String?,
      lines: _linesFromJson(json['lines']),
      visitNotes: json['visitNotes'] as String?,
      stage: VisitOrderDraftStageX.fromStorage(json['stage'] as String?),
      arrangement: json['arrangement'] as String?,
      chequeFollowUpAt: _date(json['chequeFollowUpAt']),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
      runningTotal: _num(json['runningTotal']),
      orderDiscount: _num(json['orderDiscount']),
      orderDiscountPercent: _num(json['orderDiscountPercent']),
    );
  }

  static List<VisitOrderDraftLine> _linesFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          VisitOrderDraftLine.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  static DateTime? _date(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  static num _num(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }
}

class VisitOrderDraftLine {
  const VisitOrderDraftLine({
    required this.productId,
    required this.quantity,
    this.variantId,
  });

  final String productId;

  /// Sellable unit. Absent in drafts written before product variants shipped —
  /// those restore through the product's default variant.
  final String? variantId;

  final num quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'quantity': quantity,
      };

  factory VisitOrderDraftLine.fromJson(Map<String, dynamic> json) {
    final variantId = json['variantId'];
    return VisitOrderDraftLine(
      productId: json['productId'] as String,
      variantId: variantId is String && variantId.trim().isNotEmpty
          ? variantId.trim()
          : null,
      quantity: _parseNum(json['quantity']),
    );
  }

  static num _parseNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }
}

enum VisitOrderDraftStage {
  catalog,
  checkout,
}

extension VisitOrderDraftStageX on VisitOrderDraftStage {
  static VisitOrderDraftStage fromStorage(String? raw) {
    return raw == 'checkout'
        ? VisitOrderDraftStage.checkout
        : VisitOrderDraftStage.catalog;
  }
}
