import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/router/router_refresh.dart';
import 'package:sello/features/hub/dashboard/presentation/hub_dashboard_page.dart';
import 'package:sello/features/hub/settings/presentation/hub_settings_page.dart';
import 'package:sello/features/hub/shell/hub_shell.dart';
import 'package:sello/features/mobile/authentication/presentation/login_page.dart';
import 'package:sello/features/mobile/dashboard/presentation/sello_dashboard_page.dart';
import 'package:sello/features/mobile/profile/presentation/sello_profile_page.dart';
import 'package:sello/features/mobile/shell/sello_shell.dart';
import 'package:sello/features/system/presentation/system_pages.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      return RouteGuards.resolve(
        auth: ref.read(authSessionProvider),
        location: state.matchedLocation,
      );
    },
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return SelloShell(navigationShell: navigationShell);
        },
        branches: [
          _branch(
            RoutePaths.selloDashboard,
            const SelloDashboardPage(),
          ),
          _branch(
            RoutePaths.selloCustomers,
            const FeaturePlaceholderScaffold(
              title: 'Customers',
              description: 'Manage customers in the field.',
              icon: Icons.people_rounded,
            ),
          ),
          _branch(
            RoutePaths.selloProducts,
            const FeaturePlaceholderScaffold(
              title: 'Products',
              description: 'Browse the product catalog.',
              icon: Icons.inventory_2_rounded,
            ),
          ),
          _branch(
            RoutePaths.selloOrders,
            const FeaturePlaceholderScaffold(
              title: 'Orders',
              description: 'Create and submit sales orders.',
              icon: Icons.receipt_long_rounded,
            ),
          ),
          _branch(
            RoutePaths.selloProfile,
            const SelloProfilePage(),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HubShell(navigationShell: navigationShell);
        },
        branches: [
          _branch(
            RoutePaths.hubDashboard,
            const HubDashboardPage(),
          ),
          _branch(
            RoutePaths.hubCustomers,
            const FeaturePlaceholderScaffold(
              title: 'Customers',
              description: 'Customer administration for your business.',
              icon: Icons.people_rounded,
            ),
          ),
          _branch(
            RoutePaths.hubProducts,
            const FeaturePlaceholderScaffold(
              title: 'Products',
              description: 'Product management console.',
              icon: Icons.inventory_2_rounded,
            ),
          ),
          _branch(
            RoutePaths.hubInventory,
            const FeaturePlaceholderScaffold(
              title: 'Inventory',
              description: 'Stock levels across branches.',
              icon: Icons.warehouse_rounded,
            ),
          ),
          _branch(
            RoutePaths.hubEmployees,
            const FeaturePlaceholderScaffold(
              title: 'Employees',
              description: 'Team and role management.',
              icon: Icons.badge_rounded,
            ),
          ),
          _branch(
            RoutePaths.hubReports,
            const FeaturePlaceholderScaffold(
              title: 'Reports',
              description: 'Operational reports.',
              icon: Icons.description_rounded,
            ),
          ),
          _branch(
            RoutePaths.hubAnalytics,
            const FeaturePlaceholderScaffold(
              title: 'Analytics',
              description: 'Sales insights and trends.',
              icon: Icons.insights_rounded,
            ),
          ),
          _branch(
            RoutePaths.hubSettings,
            const HubSettingsPage(),
          ),
        ],
      ),
    ],
  );
});

StatefulShellBranch _branch(String path, Widget child) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: child,
        ),
      ),
    ],
  );
}
