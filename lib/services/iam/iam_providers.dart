import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/iam/audit_service.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

/// Session-scoped permission profile — single source for UI + repositories.
final permissionProfileProvider = Provider<RolePermissionProfile?>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  return RolePermissionProfile.forRoleCode(session.role.code);
});

final permissionServiceProvider = Provider<PermissionService?>((ref) {
  final profile = ref.watch(permissionProfileProvider);
  if (profile == null) return null;
  return PermissionService(profile: profile);
});

final auditServiceProvider = Provider<AuditService>(
  (ref) => AuditService(),
);
