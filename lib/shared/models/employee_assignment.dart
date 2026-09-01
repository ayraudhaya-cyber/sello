import 'package:equatable/equatable.dart';

/// Soft assignment of an employee to a work target (customer, territory, …).
class EmployeeAssignment extends Equatable {
  const EmployeeAssignment({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.assignmentType,
    this.targetId,
    this.targetLabel,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String employeeId;
  final EmployeeAssignmentType assignmentType;
  final String? targetId;
  final String? targetLabel;
  final DateTime? createdAt;

  factory EmployeeAssignment.fromJson(Map<String, dynamic> json) {
    return EmployeeAssignment(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      employeeId: json['employee_id'] as String,
      assignmentType:
          EmployeeAssignmentType.fromDb(json['assignment_type'] as String?),
      targetId: json['target_id'] as String?,
      targetLabel: (json['target_label'] as String?)?.trim().isEmpty == true
          ? null
          : (json['target_label'] as String?)?.trim(),
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props =>
      [id, companyId, employeeId, assignmentType, targetId, targetLabel];
}

enum EmployeeAssignmentType {
  customer,
  territory,
  route,
  productCategory;

  String get dbValue => switch (this) {
        EmployeeAssignmentType.customer => 'customer',
        EmployeeAssignmentType.territory => 'territory',
        EmployeeAssignmentType.route => 'route',
        EmployeeAssignmentType.productCategory => 'product_category',
      };

  String get label => switch (this) {
        EmployeeAssignmentType.customer => 'Customer',
        EmployeeAssignmentType.territory => 'Territory',
        EmployeeAssignmentType.route => 'Route',
        EmployeeAssignmentType.productCategory => 'Product category',
      };

  static EmployeeAssignmentType fromDb(String? value) {
    return switch (value) {
      'territory' => EmployeeAssignmentType.territory,
      'route' => EmployeeAssignmentType.route,
      'product_category' => EmployeeAssignmentType.productCategory,
      _ => EmployeeAssignmentType.customer,
    };
  }
}
