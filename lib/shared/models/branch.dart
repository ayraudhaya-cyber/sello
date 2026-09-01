import 'package:equatable/equatable.dart';

/// Domain branch from `public.branches`.
class Branch extends Equatable {
  const Branch({
    required this.id,
    required this.companyId,
    required this.name,
    required this.code,
    this.phone,
    this.email,
    this.managerName,
    this.addressLine1,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String name;
  final String code;
  final String? phone;
  final String? email;
  final String? managerName;
  final String? addressLine1;
  final bool isActive;

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      managerName: json['manager_name'] as String?,
      addressLine1: json['address_line1'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props =>
      [
        id,
        companyId,
        name,
        code,
        phone,
        email,
        managerName,
        addressLine1,
        isActive,
      ];
}
