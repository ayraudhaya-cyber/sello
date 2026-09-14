import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/cheque_source.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/payment_summary.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

DateTime? _dateOnly(dynamic value) {
  if (value is String && value.isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
  return null;
}

String? _stringValue(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _embedName(dynamic value, String key) {
  if (value is Map<String, dynamic>) return _stringValue(value[key]);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return _stringValue((value.first as Map)[key]);
  }
  return null;
}

class ChequeSummary extends Equatable {
  const ChequeSummary({
    required this.id,
    required this.companyId,
    required this.customerId,
    required this.employeeId,
    required this.chequeNumberLabel,
    required this.amount,
    required this.bankName,
    required this.chequeNumber,
    required this.holderName,
    required this.chequeDate,
    required this.status,
    required this.createdAt,
    this.collectionDate,
    this.photoPath,
    this.notes,
    this.visitId,
    this.paymentId,
    this.customerName,
    this.customerPhone,
    this.employeeName,
    this.appliedArAmount = 0,
    this.appliedWalletAmount = 0,
    this.balanceAppliedAt,
    this.balanceReversedAt,
    this.collectedAt,
    this.depositedAt,
    this.clearedAt,
    this.bouncedAt,
    this.cancelledAt,
    this.bounceReason,
    this.cancelReason,
    this.source = ChequeSource.sello,
  });

  final String id;
  final String companyId;
  final String customerId;
  final String employeeId;
  final String chequeNumberLabel;
  final num amount;
  final String bankName;
  final String chequeNumber;
  final String holderName;
  final DateTime chequeDate;
  final DateTime? collectionDate;
  final String? photoPath;
  final String? notes;
  final ChequeStatus status;
  final ChequeSource source;
  final String? visitId;
  final String? paymentId;
  final String? customerName;
  final String? customerPhone;
  final String? employeeName;
  final num appliedArAmount;
  final num appliedWalletAmount;
  final DateTime? balanceAppliedAt;
  final DateTime? balanceReversedAt;
  final DateTime? collectedAt;
  final DateTime? depositedAt;
  final DateTime? clearedAt;
  final DateTime? bouncedAt;
  final DateTime? cancelledAt;
  final String? bounceReason;
  final String? cancelReason;
  final DateTime createdAt;

  /// Pre-Sello instrument with no Sello payment / balance apply yet.
  bool get isTrackingOnly =>
      source == ChequeSource.existing && paymentId == null;

  bool get isPendingClearance =>
      (status == ChequeStatus.collected || status == ChequeStatus.deposited) &&
      balanceAppliedAt != null;

  /// Collected instrument waiting for Owner/Manager collection approval.
  bool get isPendingApproval =>
      status == ChequeStatus.collected &&
      balanceAppliedAt == null &&
      !isTrackingOnly;

  bool get reducesOutstanding =>
      balanceAppliedAt != null &&
      balanceReversedAt == null &&
      (status == ChequeStatus.collected ||
          status == ChequeStatus.deposited ||
          status == ChequeStatus.cleared);

  bool get canDeposit =>
      status == ChequeStatus.collected && balanceAppliedAt != null;

  bool get canApproveCollection => isPendingApproval;

  bool get canCollect => status == ChequeStatus.awaitingCollection;

  bool get canBounce =>
      (balanceAppliedAt != null &&
          balanceReversedAt == null &&
          (status == ChequeStatus.collected ||
              status == ChequeStatus.deposited ||
              status == ChequeStatus.cleared)) ||
      (isTrackingOnly &&
          (status == ChequeStatus.collected ||
              status == ChequeStatus.deposited ||
              status == ChequeStatus.cleared));

  String get displayLabel {
    if (isTrackingOnly) {
      return switch (status) {
        ChequeStatus.awaitingCollection => 'Awaiting collection',
        ChequeStatus.collected => 'Collected · Historical',
        ChequeStatus.deposited => 'Deposited · Historical',
        ChequeStatus.cleared => 'Cleared · Historical',
        ChequeStatus.bounced => 'Bounced · Historical',
        ChequeStatus.cancelled => 'Cancelled · Historical',
      };
    }
    if (isPendingApproval) return 'Collected · Pending approval';
    if (status == ChequeStatus.collected && balanceAppliedAt != null) {
      return 'Collected · Pending clearance';
    }
    return status.shortLabel;
  }

  factory ChequeSummary.fromJson(Map<String, dynamic> json) {
    return ChequeSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      customerId: json['customer_id'] as String,
      employeeId: json['employee_id'] as String,
      chequeNumberLabel: json['cheque_number_label'] as String? ?? '',
      amount: _numValue(json['amount']),
      bankName: json['bank_name'] as String? ?? '',
      chequeNumber: json['cheque_number'] as String? ?? '',
      holderName: json['holder_name'] as String? ?? '',
      chequeDate: _dateOnly(json['cheque_date']) ?? DateTime.now(),
      collectionDate: _dateOnly(json['collection_date']),
      photoPath: _stringValue(json['photo_path']),
      notes: _stringValue(json['notes']),
      status: ChequeStatus.fromDb(json['status'] as String?) ??
          ChequeStatus.awaitingCollection,
      source: ChequeSource.fromDb(json['source'] as String?),
      visitId: _stringValue(json['visit_id']),
      paymentId: _stringValue(json['payment_id']),
      customerName: _embedName(json['customers'], 'name'),
      customerPhone: _embedName(json['customers'], 'phone'),
      employeeName: _embedName(json['employees'], 'full_name'),
      appliedArAmount: _numValue(json['applied_ar_amount']),
      appliedWalletAmount: _numValue(json['applied_wallet_amount']),
      balanceAppliedAt: _dateValue(json['balance_applied_at']),
      balanceReversedAt: _dateValue(json['balance_reversed_at']),
      collectedAt: _dateValue(json['collected_at']),
      depositedAt: _dateValue(json['deposited_at']),
      clearedAt: _dateValue(json['cleared_at']),
      bouncedAt: _dateValue(json['bounced_at']),
      cancelledAt: _dateValue(json['cancelled_at']),
      bounceReason: _stringValue(json['bounce_reason']),
      cancelReason: _stringValue(json['cancel_reason']),
      createdAt: _dateValue(json['created_at']) ?? DateTime.now().toUtc(),
    );
  }

  @override
  List<Object?> get props => [id, status, amount, source, updatedKey];

  String get updatedKey =>
      '${balanceAppliedAt?.millisecondsSinceEpoch}-'
      '${balanceReversedAt?.millisecondsSinceEpoch}-'
      '${status.dbValue}-'
      '${source.dbValue}';
}

class ChequeDashboardStats extends Equatable {
  const ChequeDashboardStats({
    this.awaitingCollection = 0,
    this.dueToday = 0,
    this.pendingApproval = 0,
    this.collected = 0,
    this.deposited = 0,
    this.cleared = 0,
    this.bounced = 0,
    this.cancelled = 0,
    this.collectedPendingClearanceAmount = 0,
  });

  final int awaitingCollection;
  final int dueToday;
  final int pendingApproval;
  final int collected;
  final int deposited;
  final int cleared;
  final int bounced;
  final int cancelled;
  final num collectedPendingClearanceAmount;

  factory ChequeDashboardStats.fromJson(Map<String, dynamic> json) {
    return ChequeDashboardStats(
      awaitingCollection: _numValue(json['awaiting_collection']).toInt(),
      dueToday: _numValue(json['due_today']).toInt(),
      pendingApproval: _numValue(json['pending_approval']).toInt(),
      collected: _numValue(json['collected']).toInt(),
      deposited: _numValue(json['deposited']).toInt(),
      cleared: _numValue(json['cleared']).toInt(),
      bounced: _numValue(json['bounced']).toInt(),
      cancelled: _numValue(json['cancelled']).toInt(),
      collectedPendingClearanceAmount:
          _numValue(json['collected_pending_clearance_amount']),
    );
  }

  @override
  List<Object?> get props => [
        awaitingCollection,
        dueToday,
        pendingApproval,
        collected,
        deposited,
        cleared,
        bounced,
        cancelled,
        collectedPendingClearanceAmount,
      ];
}

class CreateChequeInput {
  const CreateChequeInput({
    required this.customerId,
    required this.amount,
    required this.bankName,
    required this.chequeNumber,
    required this.holderName,
    required this.chequeDate,
    this.collectionDate,
    this.photoPath,
    this.notes,
    this.allocations = const [],
    this.visitId,
    this.markCollected = false,
  });

  final String customerId;
  final num amount;
  final String bankName;
  final String chequeNumber;
  final String holderName;
  final DateTime chequeDate;
  final DateTime? collectionDate;
  final String? photoPath;
  final String? notes;
  final List<PaymentAllocationInput> allocations;
  final String? visitId;
  final bool markCollected;
}

class CollectChequeInput {
  const CollectChequeInput({
    required this.chequeId,
    required this.collectionDate,
    this.allocations = const [],
    this.photoPath,
    this.notes,
  });

  final String chequeId;
  final DateTime collectionDate;
  final List<PaymentAllocationInput> allocations;
  final String? photoPath;
  final String? notes;
}

/// Pre-Sello cheque import — tracking only, never creates a payment.
class CreateExistingChequeInput {
  const CreateExistingChequeInput({
    required this.customerId,
    required this.amount,
    required this.bankName,
    required this.chequeNumber,
    required this.holderName,
    required this.chequeDate,
    required this.status,
    this.collectionDate,
    this.depositDate,
    this.clearanceDate,
    this.photoPath,
    this.notes,
  });

  final String customerId;
  final num amount;
  final String bankName;
  final String chequeNumber;
  final String holderName;
  final DateTime chequeDate;
  final ChequeStatus status;
  final DateTime? collectionDate;
  final DateTime? depositDate;
  final DateTime? clearanceDate;
  final String? photoPath;
  final String? notes;
}
