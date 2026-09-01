import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/router/router_refresh.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/documents/presentation/order_document_page.dart';
import 'package:sello/features/hub/customers/presentation/hub_customers_page.dart';
import 'package:sello/features/hub/dashboard/presentation/hub_dashboard_page.dart';
import 'package:sello/features/hub/employees/presentation/hub_employees_page.dart';
import 'package:sello/features/hub/inventory/presentation/hub_inventory_page.dart';
import 'package:sello/features/hub/orders/presentation/hub_orders_page.dart';
import 'package:sello/features/hub/payments/presentation/hub_payments_page.dart';
import 'package:sello/features/hub/products/presentation/hub_products_page.dart';
import 'package:sello/features/hub/reports/presentation/hub_reports_page.dart';
import 'package:sello/features/hub/schedule/presentation/hub_schedule_page.dart';
import 'package:sello/features/hub/visits/presentation/hub_visits_page.dart';
import 'package:sello/features/hub/settings/presentation/hub_settings_page.dart';
import 'package:sello/features/hub/shared/hub_feature_page.dart';
import 'package:sello/features/hub/shell/hub_shell.dart';
import 'package:sello/features/hub/suppliers/presentation/hub_suppliers_page.dart';
import 'package:sello/features/mobile/authentication/presentation/login_page.dart';
import 'package:sello/features/mobile/customers/presentation/sello_customers_page.dart';
import 'package:sello/features/mobile/dashboard/presentation/sello_dashboard_page.dart';
import 'package:sello/features/mobile/orders/presentation/sello_orders_page.dart';
import 'package:sello/features/mobile/products/presentation/sello_products_page.dart';
import 'package:sello/features/mobile/profile/presentation/sello_profile_page.dart';
import 'package:sello/features/mobile/shell/sello_shell.dart';
import 'package:sello/features/hub/setup/presentation/owner_setup_page.dart';
import 'package:sello/features/onboarding/presentation/business_onboarding_page.dart';
import 'package:sello/features/system/presentation/system_pages.dart';
import 'package:sello/features/visits/presentation/customer_visit_workspace_page.dart';
import 'package:sello/services/session/session_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (location == RoutePaths.hubAnalytics) {
        return RoutePaths.hubReports;
      }
      return RouteGuards.resolve(
        auth: ref.read(authSessionProvider),
        location: location,
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
      GoRoute(
        path: RoutePaths.onboarding,
        name: 'onboarding',
        builder: (context, state) => const BusinessOnboardingPage(),
      ),
      GoRoute(
        path: RoutePaths.ownerSetup,
        name: 'ownerSetup',
        builder: (context, state) => const OwnerSetupPage(),
      ),
      GoRoute(
        path: '${RoutePaths.orderDocument}/:token',
        name: 'orderDocument',
        builder: (context, state) => OrderDocumentPage(
          token: state.pathParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: RoutePaths.selloVisit,
        name: 'selloVisit',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return CustomerVisitWorkspacePage(
            customerId: q['customer'],
            scheduledVisitId: q['scheduled'],
            customerName: q['name'],
            walkIn: q['walkin'] == '1' || q['walkin'] == 'true',
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return SelloShell(navigationShell: navigationShell);
        },
        branches: [
          _branch(RoutePaths.selloDashboard, const SelloDashboardPage()),
          _branch(RoutePaths.selloCustomers, const SelloCustomersPage()),
          _branch(RoutePaths.selloProducts, const SelloProductsPage()),
          _branch(RoutePaths.selloOrders, const SelloOrdersPage()),
          _branch(RoutePaths.selloProfile, const SelloProfilePage()),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HubShell(navigationShell: navigationShell);
        },
        branches: [
          // Overview
          _branch(RoutePaths.hubDashboard, const HubDashboardPage()),
          _branch(RoutePaths.hubReports, const HubReportsPage()),
          // Operate
          _branch(RoutePaths.hubOrders, const HubOrdersPage()),
          _branch(RoutePaths.hubInventory, const HubInventoryPage()),
          _branch(RoutePaths.hubProducts, const HubProductsPage()),
          _branch(RoutePaths.hubSuppliers, const HubSuppliersPage()),
          _branch(RoutePaths.hubCustomers, const HubCustomersPage()),
          _branch(RoutePaths.hubPayments, const HubPaymentsPage()),
          _branch(RoutePaths.hubSchedule, const HubSchedulePage()),
          _branch(RoutePaths.hubVisits, const HubVisitsPage()),
          // Team
          _branch(RoutePaths.hubEmployees, const HubEmployeesPage()),
          _branch(
            RoutePaths.hubAttendance,
            const HubFeaturePage(
              title: 'Attendance',
              description: 'Daily check-ins and field presence.',
              icon: Icons.fact_check_rounded,
              tone: AppColors.success,
              rows: [
                HubFeatureRow(
                  title: 'Checked in today',
                  subtitle: 'Sales reps on route',
                  trailing: '8 / 10',
                  icon: Icons.how_to_reg_outlined,
                  tone: AppColors.success,
                ),
                HubFeatureRow(
                  title: 'Late / missing',
                  subtitle: 'Needs follow-up',
                  trailing: '2',
                  icon: Icons.schedule_outlined,
                  tone: AppColors.attention,
                ),
              ],
            ),
          ),
          _branch(RoutePaths.hubSettings, const HubSettingsPage()),
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
