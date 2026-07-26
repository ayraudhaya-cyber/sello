import 'package:flutter/widgets.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/core/router/route_paths.dart';

/// Centralized redirect / guard decisions for GoRouter.
abstract final class RouteGuards {
  /// Returns a redirect location, or null to allow navigation.
  static String? resolve({
    required AuthSessionState auth,
    required String location,
  }) {
    final isSplash = location == RoutePaths.splash;
    final isLogin = location == RoutePaths.login;
    final isPublic = isSplash || isLogin;

    if (auth.isBootstrapping) {
      // Hold on splash while restoring session.
      return isSplash ? null : RoutePaths.splash;
    }

    if (!auth.isAuthenticated) {
      if (isLogin) return null;
      if (isSplash) return RoutePaths.login;
      return RoutePaths.login;
    }

    final session = auth.session!;
    final home = homeFor(session.role);

    if (isPublic) return home;

    if (!_roleMayAccess(session.role, location)) {
      return home;
    }

    return null;
  }

  static String homeFor(UserRole role) =>
      role.usesHub ? RoutePaths.hubDashboard : RoutePaths.selloDashboard;

  static bool _roleMayAccess(UserRole role, String location) {
    final onSello = location.startsWith(RoutePaths.sello);
    final onHub = location.startsWith(RoutePaths.hub);
    if (role.usesSello && onHub) return false;
    if (role.usesHub && onSello) return false;
    return true;
  }

  static bool isHubLocation(String location) =>
      location.startsWith(RoutePaths.hub);

  static bool isSelloLocation(String location) =>
      location.startsWith(RoutePaths.sello);
}

/// Breadcrumb helper from route location.
abstract final class RouteTitles {
  static const Map<String, String> _titles = {
    RoutePaths.selloDashboard: 'Home',
    RoutePaths.selloCustomers: 'Customers',
    RoutePaths.selloProducts: 'Products',
    RoutePaths.selloInventory: 'Inventory',
    RoutePaths.selloOrders: 'Orders',
    RoutePaths.selloProfile: 'Profile',
    RoutePaths.hubDashboard: 'Dashboard',
    RoutePaths.hubCustomers: 'Customers',
    RoutePaths.hubProducts: 'Products',
    RoutePaths.hubInventory: 'Inventory',
    RoutePaths.hubEmployees: 'Employees',
    RoutePaths.hubReports: 'Reports',
    RoutePaths.hubAnalytics: 'Analytics',
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
    final root = isHub ? 'Sello Hub' : 'Sello';
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
