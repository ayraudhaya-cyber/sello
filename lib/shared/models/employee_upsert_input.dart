import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/employment_status.dart';

/// Create / update payload for Hub team member editor.
class EmployeeUpsertInput extends Equatable {
  const EmployeeUpsertInput({
    this.id,
    required this.fullName,
    required this.email,
    required this.roleId,
    required this.employmentStatus,
    this.phone,
    this.employeeCode,
    this.nic,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.department,
    this.joinedAt,
    this.branchId,
    this.salesTerritory,
    this.notes,
    this.clearAvatar = false,
    this.avatarBytes,
  });

  final String? id;
  final String fullName;
  final String email;
  final String roleId;
  final EmploymentStatus employmentStatus;
  final String? phone;
  final String? employeeCode;
  final String? nic;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? department;
  final DateTime? joinedAt;
  final String? branchId;
  final String? salesTerritory;
  final String? notes;
  final bool clearAvatar;
  final Uint8List? avatarBytes;

  bool get isCreate => id == null;

  @override
  List<Object?> get props => [
        id,
        fullName,
        email,
        roleId,
        employmentStatus,
        phone,
        employeeCode,
        nic,
        address,
        emergencyContactName,
        emergencyContactPhone,
        department,
        joinedAt,
        branchId,
        salesTerritory,
        notes,
        clearAvatar,
        avatarBytes,
      ];
}
