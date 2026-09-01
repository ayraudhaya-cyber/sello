import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/customer_type.dart';

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

/// List / workspace summary for a customer.
class CustomerSummary extends Equatable {
  const CustomerSummary({
    required this.id,
    required this.companyId,
    required this.name,
    required this.customerType,
    required this.creditAllowed,
    required this.creditLimit,
    required this.openingBalance,
    required this.outstandingBalance,
    required this.walletBalance,
    required this.isActive,
    this.branchId,
    this.code,
    this.companyName,
    this.phone,
    this.whatsapp,
    this.email,
    this.addressLine1,
    this.city,
    this.taxNumber,
    this.notes,
    this.lastPurchaseAt,
    this.lastVisitAt,
    this.nextVisitAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? branchId;
  final String name;
  final String? code;
  final String? companyName;
  final CustomerType customerType;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? addressLine1;
  final String? city;
  final String? taxNumber;
  final String? notes;
  final bool creditAllowed;
  final num creditLimit;
  final num openingBalance;

  /// Stored as `current_balance` — outstanding receivable.
  final num outstandingBalance;
  final num walletBalance;
  final bool isActive;
  final DateTime? lastPurchaseAt;

  /// Last completed visit (synced from `scheduled_visits`).
  final DateTime? lastVisitAt;

  /// Next scheduled visit date (synced from `scheduled_visits`).
  final DateTime? nextVisitAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CustomerSummary.fromJson(Map<String, dynamic> json) {
    return CustomerSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String?,
      name: json['name'] as String? ?? '',
      code: _stringValue(json['code']),
      companyName: _stringValue(json['company_name']),
      customerType: CustomerType.fromDb(json['customer_type'] as String?),
      phone: _stringValue(json['phone']),
      whatsapp: _stringValue(json['whatsapp']),
      email: _stringValue(json['email']),
      addressLine1: _stringValue(json['address_line1']),
      city: _stringValue(json['city']),
      taxNumber: _stringValue(json['tax_number']),
      notes: _stringValue(json['notes']),
      creditAllowed: json['credit_allowed'] as bool? ?? false,
      creditLimit: _numValue(json['credit_limit']),
      openingBalance: _numValue(json['opening_balance']),
      outstandingBalance: _numValue(json['current_balance']),
      walletBalance: _numValue(json['wallet_balance']),
      isActive: json['is_active'] as bool? ?? true,
      lastPurchaseAt: _dateValue(json['last_purchase_at']),
      lastVisitAt: _dateValue(json['last_visit_at']),
      nextVisitAt: _dateValue(json['next_visit_at']),
      createdAt: _dateValue(json['created_at']),
      updatedAt: _dateValue(json['updated_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        branchId,
        name,
        code,
        companyName,
        customerType,
        phone,
        whatsapp,
        email,
        addressLine1,
        city,
        taxNumber,
        notes,
        creditAllowed,
        creditLimit,
        openingBalance,
        outstandingBalance,
        walletBalance,
        isActive,
        lastPurchaseAt,
        lastVisitAt,
        nextVisitAt,
        createdAt,
        updatedAt,
      ];
}
