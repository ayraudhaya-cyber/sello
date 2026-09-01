import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

/// Directory row for Hub Employees and future Sales identity lookups.
class EmployeeSummary extends Equatable {
  const EmployeeSummary({
    required this.id,
    required this.companyId,
    required this.roleId,
    required this.email,
    required this.fullName,
    required this.employmentStatus,
    required this.isActive,
    required this.role,
    this.branchId,
    this.branchName,
    this.userId,
    this.phone,
    this.avatarUrl,
    this.avatarStoragePath,
    this.employeeCode,
    this.nic,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.department,
    this.joinedAt,
    this.lastActiveAt,
    this.salesTerritory,
    this.notes,
    this.assignedCustomerCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String roleId;
  final String email;
  final String fullName;
  final EmploymentStatus employmentStatus;
  final bool isActive;
  final Role role;
  final String? branchId;
  final String? branchName;
  final String? userId;
  final String? phone;

  /// Signed URL for UI (resolved by repository).
  final String? avatarUrl;

  /// Storage object path stored in `employees.avatar_url`.
  final String? avatarStoragePath;
  final String? employeeCode;
  final String? nic;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? department;
  final DateTime? joinedAt;
  final DateTime? lastActiveAt;
  final String? salesTerritory;
  final String? notes;
  final int assignedCustomerCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasLogin => userId != null && userId!.isNotEmpty;

  RolePermissionProfile get permissionProfile =>
      RolePermissionProfile.forRoleCode(role.code);

  String get displayEmployeeId =>
      (employeeCode != null && employeeCode!.trim().isNotEmpty)
          ? employeeCode!.trim()
          : id.substring(0, 8).toUpperCase();

  bool get isSalesRep => role.code == 'sales_representative';
  bool get isManager => role.code == 'manager';
  bool get isOwner => role.code == 'owner';

  EmployeeSummary copyWith({
    String? avatarUrl,
    int? assignedCustomerCount,
  }) {
    return EmployeeSummary(
      id: id,
      companyId: companyId,
      roleId: roleId,
      email: email,
      fullName: fullName,
      employmentStatus: employmentStatus,
      isActive: isActive,
      role: role,
      branchId: branchId,
      branchName: branchName,
      userId: userId,
      phone: phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarStoragePath: avatarStoragePath,
      employeeCode: employeeCode,
      nic: nic,
      address: address,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      department: department,
      joinedAt: joinedAt,
      lastActiveAt: lastActiveAt,
      salesTerritory: salesTerritory,
      notes: notes,
      assignedCustomerCount:
          assignedCustomerCount ?? this.assignedCustomerCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory EmployeeSummary.fromJson(Map<String, dynamic> json) {
    final roleJson = json['roles'];
    final Role role;
    if (roleJson is Map<String, dynamic>) {
      role = Role.fromJson(roleJson);
    } else {
      role = Role(
        id: json['role_id'] as String,
        code: 'unknown',
        name: 'Unknown',
      );
    }

    String? branchName;
    final branchJson = json['branches'];
    if (branchJson is Map<String, dynamic>) {
      branchName = branchJson['name'] as String?;
    }

    final rawAvatar = json['avatar_url'] as String?;
    final looksLikePath = rawAvatar != null &&
        rawAvatar.isNotEmpty &&
        !rawAvatar.startsWith('http');

    return EmployeeSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      roleId: json['role_id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      employmentStatus:
          EmploymentStatus.fromCode(json['employment_status'] as String?),
      isActive: json['is_active'] as bool? ?? true,
      role: role,
      branchId: json['branch_id'] as String?,
      branchName: branchName,
      userId: json['user_id'] as String?,
      phone: json['phone'] as String?,
      avatarStoragePath: looksLikePath ? rawAvatar : null,
      avatarUrl: looksLikePath ? null : rawAvatar,
      employeeCode: json['employee_code'] as String?,
      nic: json['nic'] as String?,
      address: json['address'] as String?,
      emergencyContactName: json['emergency_contact_name'] as String?,
      emergencyContactPhone: json['emergency_contact_phone'] as String?,
      department: json['department'] as String?,
      joinedAt: _parseDate(json['joined_at']),
      lastActiveAt: _parseDateTime(json['last_active_at']),
      salesTerritory: json['sales_territory'] as String?,
      notes: json['notes'] as String?,
      assignedCustomerCount:
          (json['assigned_customer_count'] as num?)?.toInt() ?? 0,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        roleId,
        email,
        fullName,
        employmentStatus,
        isActive,
        role,
        branchId,
        branchName,
        userId,
        phone,
        avatarUrl,
        avatarStoragePath,
        employeeCode,
        nic,
        address,
        emergencyContactName,
        emergencyContactPhone,
        department,
        joinedAt,
        lastActiveAt,
        salesTerritory,
        notes,
        assignedCustomerCount,
        createdAt,
        updatedAt,
      ];
}

/// Hub dashboard metrics for the people directory.
class EmployeeDashboardStats extends Equatable {
  const EmployeeDashboardStats({
    this.total = 0,
    this.active = 0,
    this.salesRepresentatives = 0,
    this.managers = 0,
    this.inactive = 0,
  });

  final int total;
  final int active;
  final int salesRepresentatives;
  final int managers;
  final int inactive;

  @override
  List<Object?> get props =>
      [total, active, salesRepresentatives, managers, inactive];
}
