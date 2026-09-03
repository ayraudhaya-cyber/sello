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
  });

  final String productId;
  final num quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity': quantity,
      };

  factory VisitOrderDraftLine.fromJson(Map<String, dynamic> json) {
    return VisitOrderDraftLine(
      productId: json['productId'] as String,
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
