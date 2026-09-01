import 'package:sello/shared/models/customer_type.dart';

class CustomerUpsertInput {
  const CustomerUpsertInput({
    this.customerId,
    required this.name,
    required this.customerType,
    required this.creditAllowed,
    required this.creditLimit,
    required this.openingBalance,
    this.code,
    this.companyName,
    this.phone,
    this.whatsapp,
    this.email,
    this.addressLine1,
    this.city,
    this.taxNumber,
    this.notes,
    this.isActive = true,
  });

  final String? customerId;
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
  final bool isActive;
}
