class SupplierUpsertInput {
  const SupplierUpsertInput({
    this.supplierId,
    required this.name,
    required this.creditLimit,
    required this.openingBalance,
    this.code,
    this.contactName,
    this.phone,
    this.whatsapp,
    this.email,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.taxNumber,
    this.category,
    this.paymentTerms,
    this.bankName,
    this.bankAccount,
    this.notes,
    this.leadTimeDays,
    this.isActive = true,
  });

  final String? supplierId;
  final String name;
  final String? code;
  final String? contactName;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? taxNumber;
  final String? category;
  final String? paymentTerms;
  final String? bankName;
  final String? bankAccount;
  final String? notes;
  final num creditLimit;
  final num openingBalance;
  final int? leadTimeDays;
  final bool isActive;

  bool get isCreate => supplierId == null;
}
