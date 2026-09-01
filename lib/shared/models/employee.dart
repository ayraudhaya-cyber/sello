import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/employment_status.dart';

/// Domain employee from `public.employees`.
///
/// Used by session bootstrap and shared identity lookups. Prefer
/// [EmployeeSummary] for directory / profile workspaces.
class Employee extends Equatable {
  const Employee({
    required this.id,
    required this.companyId,
    required this.roleId,
    required this.email,
    required this.fullName,
    this.branchId,
    this.userId,
    this.phone,
    this.avatarUrl,
    this.employeeCode,
    this.employmentStatus = EmploymentStatus.active,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String roleId;
  final String email;
  final String fullName;
  final String? branchId;
  final String? userId;
  final String? phone;
  final String? avatarUrl;
  final String? employeeCode;
  final EmploymentStatus employmentStatus;
  final bool isActive;

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      roleId: json['role_id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      branchId: json['branch_id'] as String?,
      userId: json['user_id'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      employeeCode: json['employee_code'] as String?,
      employmentStatus:
          EmploymentStatus.fromCode(json['employment_status'] as String?),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        roleId,
        email,
        fullName,
        branchId,
        userId,
        phone,
        avatarUrl,
        employeeCode,
        employmentStatus,
        isActive,
      ];
}
