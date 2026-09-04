import 'package:flutter/widgets.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/setup/owner_setup_policy.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/user_role.dart';

/// Centralized redirect / guard decisions for GoRouter.
abstract final class RouteGuards {
  /// Returns a redirect location, or null to allow navigation.
  static String? resolve({
    required AuthSessionState auth,
    required String location,
  }) {
    final isSplash = location == RoutePaths.splash;
    final isLogin = location == RoutePaths.login;
    final isOnboarding = location == RoutePaths.onboarding;
    final isDocument = location == RoutePaths.orderDocument ||
        location.startsWith('${RoutePaths.orderDocument}/');
    final isPublic = isSplash || isLogin || isOnboarding || isDocument;

    // Session restoration — preserve the browser URL during bootstrap so a
    // refresh on /hub/settings (etc.) does not bounce through splash → home.
    if (auth.isBootstrapping) {
      return null;
    }

    // Auth / provisioning in flight — keep user on the public entry screen.
    // If a workspace session is already loaded (e.g. Owner setup → reloadSession),
    // stay put so we do not flash /login before hydration finishes.
    if (auth.isAuthenticating) {
      if (isLogin || isOnboarding || isDocument) return null;
      if (auth.session != null) return null;
      return RoutePaths.login;
    }

    if (auth.isPasswordRecovery) {
      if (isDocument) return null;
      return isLogin ? null : RoutePaths.login;
    }

    // Provisioned users always go home — never back to onboarding.
    if (auth.isAuthenticated) {
      final session = auth.session!;
      final home = homeFor(session.appRole);
      if (isDocument) return null;
      final setupRedirect = OwnerSetupPolicy.redirect(
        requiresSetup: session.needsOwnerSetup,
        location: location,
        home: home,
      );
      if (setupRedirect != null) return setupRedirect;
      if (isPublic) return home;
      if (!_workspaceMayAccess(session.appRole, location)) {
        return home;
      }
      if (!_moduleMayAccess(session, location)) {
        return home;
      }
      return null;
    }

    // Email just verified — keep them on login with success feedback.
    if (auth.emailJustVerified) {
      if (isLogin || isDocument) return null;
      return RoutePaths.login;
    }

    // Waiting for the user to verify their email after signup.
    if (auth.awaitingEmailConfirmation) {
      if (isOnboarding || isLogin || isDocument) return null;
      return RoutePaths.onboarding;
    }

    // Auth user without employee / pending provision — finish onboarding.
    if (auth.requiresOnboarding) {
      if (isOnboarding || isDocument) return null;
      return RoutePaths.onboarding;
    }

    if (!auth.isAuthenticated) {
      if (isLogin || isOnboarding || isDocument) return null;
      return RoutePaths.login;
    }

    return null;
  }

  static String homeFor(UserRole role) =>
      role.usesHub ? RoutePaths.hubDashboard : RoutePaths.selloDashboard;

  static bool _workspaceMayAccess(UserRole role, String location) {
    final onSello = location.startsWith(RoutePaths.sello);
    final onHub = location.startsWith(RoutePaths.hub);
    if (role.usesSello && onHub) return false;
    if (role.usesHub && onSello) return false;
    return true;
  }

  /// Module ACL — users cannot deep-link into modules they cannot view.
  static bool _moduleMayAccess(AppSession session, String location) {
    final permissions = PermissionService(session: session);
    return permissions.canAccessRoute(location);
  }
}

/// Breadcrumb helper from route location.
abstract final class RouteTitles {
  static const Map<String, String> _titles = {
    RoutePaths.selloDashboard: 'Home',
    RoutePaths.selloCustomers: 'Customers',
    RoutePaths.selloProducts: 'Products',
    RoutePaths.selloInventory: 'Inventory',
    RoutePaths.selloOrders: 'Orders',
    RoutePaths.selloVisit: 'Visit',
    RoutePaths.selloProfile: 'Profile',
    RoutePaths.hubDashboard: 'Dashboard',
    RoutePaths.hubReports: 'Reports',
    RoutePaths.hubOrders: 'Orders',
    RoutePaths.hubInventory: 'Inventory',
    RoutePaths.hubProducts: 'Products',
    RoutePaths.hubSuppliers: 'Suppliers',
    RoutePaths.hubCustomers: 'Customers',
    RoutePaths.hubPayments: 'Payments',
    RoutePaths.hubSchedule: 'Schedule',
    RoutePaths.hubVisits: 'Visits',
    RoutePaths.hubEmployees: 'Team',
    RoutePaths.hubAttendance: 'Attendance',
    RoutePaths.hubAnalytics: 'Reports',
    RoutePaths.hubSettings: 'Settings',
  };

  static String titleFor(String location) =>
      _titles[location] ?? _fallback(location);

  static String _fallback(String location) {
    if (location.isEmpty) return 'Sello';
    final segment = location.split('/').where((s) => s.isNotEmpty).last;
    if (segment.isEmpty) return 'Sello';
    return '${segment[0].toUpperCase()}${segment.substring(1)}';
  }

  static List<BreadcrumbData> breadcrumbsFor(String location) {
    final isHub = location.startsWith(RoutePaths.hub);
    final root = isHub ? 'Sello Hub' : 'Sello Go';
    final rootPath = isHub ? RoutePaths.hubDashboard : RoutePaths.selloDashboard;
    final title = titleFor(location);

    if (location == rootPath) {
      return [BreadcrumbData(label: root, path: rootPath)];
    }

    return [
      BreadcrumbData(label: root, path: rootPath),
      BreadcrumbData(label: title, path: location),
    ];
  }
}

@immutable
class BreadcrumbData {
  const BreadcrumbData({required this.label, this.path});

  final String label;
  final String? path;
}
