import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

/// Hides [child] when the session lacks [action] on [module].
///
/// Prefer this over scattered role checks in feature UIs.
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.module,
    required this.child,
    this.action = PermissionAction.view,
    this.fallback,
  });

  final AppModule module;
  final PermissionAction action;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    if (permissions == null || !permissions.allows(module, action)) {
      return fallback ?? const SizedBox.shrink();
    }
    return child;
  }
}
