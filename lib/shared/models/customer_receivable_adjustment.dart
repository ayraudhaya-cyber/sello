import 'package:equatable/equatable.dart';

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

/// One opening-balance adjustment shown on the customer financial summary.
class CustomerReceivableAdjustment extends Equatable {
  const CustomerReceivableAdjustment({
    required this.id,
    required this.adjustmentNumber,
    required this.amount,
    required this.recognizedAt,
    required this.remaining,
    this.notes,
    this.referenceNumber,
  });

  final String id;
  final String adjustmentNumber;
  final num amount;
  final DateTime recognizedAt;
  final num remaining;
  final String? notes;

  /// Pre-Sello invoice / reference. Not a Sello order number.
  final String? referenceNumber;

  factory CustomerReceivableAdjustment.fromJson(
    Map<String, dynamic> json, {
    num remaining = 0,
  }) {
    return CustomerReceivableAdjustment(
      id: json['id'] as String,
      adjustmentNumber: _stringValue(json['adjustment_number']) ?? '',
      amount: _numValue(json['amount']),
      recognizedAt: _dateValue(json['recognized_at']) ?? DateTime.now().toUtc(),
      remaining: remaining,
      notes: _stringValue(json['notes']),
      referenceNumber: _stringValue(json['reference_number']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        adjustmentNumber,
        amount,
        recognizedAt,
        remaining,
        notes,
        referenceNumber,
      ];
}
