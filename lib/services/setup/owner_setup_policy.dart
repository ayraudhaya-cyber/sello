import 'package:sello/core/router/route_paths.dart';
import 'package:sello/shared/models/user_role.dart';

/// First-time Owner workspace setup — separate from public signup `/onboarding`.
abstract final class OwnerSetupPolicy {
  static bool requiresSetup({
    required UserRole role,
    required bool ownerSetupCompleted,
  }) {
    return role == UserRole.owner && !ownerSetupCompleted;
  }

  /// Redirect for an authenticated session, or null to keep [location].
  static String? redirect({
    required bool requiresSetup,
    required String location,
    required String home,
  }) {
    final onSetup = location == RoutePaths.ownerSetup;
    if (requiresSetup) {
      return onSetup ? null : RoutePaths.ownerSetup;
    }
    if (onSetup) return home;
    return null;
  }
}
