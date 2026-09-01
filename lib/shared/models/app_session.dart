import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lifecycle of authentication for splash / route guards.
enum AuthStatus {
  /// Cold start — session restore in progress.
  unknown,

  /// No valid session.
  unauthenticated,

  /// Sign-in request in flight.
  authenticating,

  /// Signed in with a resolved application session.
  authenticated,
}

/// Application session built after Supabase Auth + employee context load.
///
/// Consumed app-wide via Riverpod — do not re-query Supabase for this data
/// on every screen.
class AppSession extends Equatable {
  const AppSession({
    required this.authUser,
    required this.employee,
    required this.company,
    required this.role,
    this.branch,
    this.ownerSetupCompleted = true,
  });

  final User authUser;
  final Employee employee;
  final Company company;
  final Branch? branch;
  final Role role;

  /// Company-level first-time Owner setup. True for existing tenants.
  final bool ownerSetupCompleted;

  UserRole get appRole => UserRole.fromCode(role.code);

  String get userId => authUser.id;
  String get email => employee.email;
  String get displayName => employee.fullName;
  String? get avatarUrl => employee.avatarUrl;
  String get companyName => company.name;
  String? get branchName => branch?.name;

  bool get usesHub => appRole.usesHub;
  bool get usesSello => appRole.usesSello;

  bool get needsOwnerSetup =>
      appRole == UserRole.owner && !ownerSetupCompleted;

  /// IAM profile for this identity — prefer [permissionServiceProvider] in UI.
  RolePermissionProfile get permissionProfile =>
      RolePermissionProfile.forRoleCode(role.code);

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  List<Object?> get props =>
      [authUser.id, employee, company, branch, role, ownerSetupCompleted];
}
