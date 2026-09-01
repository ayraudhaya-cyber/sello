import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/devtools/dev_experience.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/shared/widgets/branding/branded_shell_app_bar.dart';
import 'package:sello/shared/widgets/chrome/shell_chrome.dart';
import 'package:sello/shared/widgets/icons/sello_nav_icons.dart';
import 'package:sello/shared/widgets/layout/app_page_scaffold.dart';
import 'package:sello/shared/widgets/navigation/sello_navigation.dart';

/// Sello Hub adaptive shell — drawer on phone, dark sidebar on larger.
///
/// Navigation destinations are filtered by [PermissionService] so users never
/// see modules they cannot access.
class HubShell extends ConsumerWidget {
  const HubShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Full catalog in StatefulShell branch order — do not reorder without
  /// updating [appRouterProvider] branches.
  static const catalog = <SelloNavSection>[
    SelloNavSection(
      label: 'Overview',
      destinations: [
        SelloNavDestination(
          label: 'Dashboard',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_outlined,
          glyph: SelloNavGlyph.dashboard,
          location: RoutePaths.hubDashboard,
          branchIndex: 0,
        ),
        SelloNavDestination(
          label: 'Reports',
          icon: Icons.show_chart_outlined,
          selectedIcon: Icons.show_chart_outlined,
          glyph: SelloNavGlyph.reports,
          location: RoutePaths.hubReports,
          branchIndex: 1,
        ),
      ],
    ),
    SelloNavSection(
      label: 'Operate',
      destinations: [
        SelloNavDestination(
          label: 'Orders',
          icon: Icons.shopping_cart_outlined,
          selectedIcon: Icons.shopping_cart_outlined,
          glyph: SelloNavGlyph.orders,
          location: RoutePaths.hubOrders,
          branchIndex: 2,
        ),
        SelloNavDestination(
          label: 'Inventory',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_outlined,
          glyph: SelloNavGlyph.inventory,
          location: RoutePaths.hubInventory,
          branchIndex: 3,
        ),
        SelloNavDestination(
          label: 'Products',
          icon: Icons.sell_outlined,
          selectedIcon: Icons.sell_outlined,
          glyph: SelloNavGlyph.products,
          location: RoutePaths.hubProducts,
          branchIndex: 4,
        ),
        SelloNavDestination(
          label: 'Suppliers',
          icon: Icons.local_shipping_outlined,
          selectedIcon: Icons.local_shipping_outlined,
          location: RoutePaths.hubSuppliers,
          branchIndex: 5,
        ),
        SelloNavDestination(
          label: 'Customers',
          icon: Icons.person_outline,
          selectedIcon: Icons.person_outline,
          glyph: SelloNavGlyph.customers,
          location: RoutePaths.hubCustomers,
          branchIndex: 6,
        ),
        SelloNavDestination(
          label: 'Payments',
          icon: Icons.credit_card_outlined,
          selectedIcon: Icons.credit_card_outlined,
          glyph: SelloNavGlyph.payments,
          location: RoutePaths.hubPayments,
          branchIndex: 7,
        ),
        SelloNavDestination(
          label: 'Schedule',
          icon: Icons.calendar_today_outlined,
          selectedIcon: Icons.calendar_today_outlined,
          glyph: SelloNavGlyph.schedule,
          location: RoutePaths.hubSchedule,
          branchIndex: 8,
        ),
        SelloNavDestination(
          label: 'Visits',
          icon: Icons.place_outlined,
          selectedIcon: Icons.place_outlined,
          location: RoutePaths.hubVisits,
          branchIndex: 9,
        ),
      ],
    ),
    SelloNavSection(
      label: 'Team',
      destinations: [
        SelloNavDestination(
          label: 'Team',
          icon: Icons.people_outline,
          selectedIcon: Icons.people_outline,
          glyph: SelloNavGlyph.employees,
          location: RoutePaths.hubEmployees,
          branchIndex: 10,
        ),
        SelloNavDestination(
          label: 'Attendance',
          icon: Icons.schedule_outlined,
          selectedIcon: Icons.schedule_outlined,
          glyph: SelloNavGlyph.attendance,
          location: RoutePaths.hubAttendance,
          branchIndex: 11,
        ),
      ],
    ),
    SelloNavSection(
      label: 'System',
      destinations: [
        SelloNavDestination(
          label: 'Settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_outlined,
          location: RoutePaths.hubSettings,
          branchIndex: 12,
        ),
      ],
    ),
  ];

  /// Back-compat — unfiltered catalog (devtools / tests).
  static List<SelloNavSection> get sections => catalog;

  static List<SelloNavDestination> get destinations => [
        for (final s in catalog) ...s.destinations,
      ];

  static List<SelloNavSection> sectionsFor(PermissionService? permissions) {
    if (permissions == null) return catalog;
    return [
      for (final section in catalog)
        SelloNavSection(
          label: section.label,
          destinations: [
            for (final dest in section.destinations)
              if (permissions.canAccessRoute(dest.location)) dest,
          ],
        ),
    ].where((s) => s.destinations.isNotEmpty).toList();
  }

  void _onSelect(int branchIndex) {
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    final navSections = sectionsFor(ref.watch(permissionServiceProvider));

    return AnimatedSwitcher(
      duration: AppDurations.normal,
      switchInCurve: AppCurves.standard,
      child: ResponsiveBuilder(
        key: ValueKey(context.windowSize),
        mobile: (_) => _MobileHubShell(
          navigationShell: navigationShell,
          index: index,
          sections: navSections,
          onSelect: _onSelect,
        ),
        tablet: (_) => _SidebarHubShell(
          navigationShell: navigationShell,
          index: index,
          sections: navSections,
          onSelect: _onSelect,
          sidebarWidth: AppSpacing.sidebarWidthCompact,
        ),
        desktop: (_) => _SidebarHubShell(
          navigationShell: navigationShell,
          index: index,
          sections: navSections,
          onSelect: _onSelect,
          sidebarWidth: AppSpacing.sidebarWidth,
        ),
      ),
    );
  }
}

class _MobileHubShell extends StatelessWidget {
  const _MobileHubShell({
    required this.navigationShell,
    required this.index,
    required this.sections,
    required this.onSelect,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final List<SelloNavSection> sections;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BrandedShellAppBar(
        hub: true,
        actions: [
          if (!kReleaseMode) const DevExperienceToolbarButton(),
          const GlobalSearchControl(),
          const NotificationBellButton(),
          const UserProfileMenu(compact: true),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.transparent,
        child: SelloSideNav(
          width: double.infinity,
          sections: sections,
          selectedIndex: index,
          onDestinationSelected: (i) {
            Navigator.of(context).pop();
            onSelect(i);
          },
        ),
      ),
      body: navigationShell,
    );
  }
}

class _SidebarHubShell extends StatelessWidget {
  const _SidebarHubShell({
    required this.navigationShell,
    required this.index,
    required this.sections,
    required this.onSelect,
    required this.sidebarWidth,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final List<SelloNavSection> sections;
  final ValueChanged<int> onSelect;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SelloSideNav(
            width: sidebarWidth,
            sections: sections,
            selectedIndex: index,
            onDestinationSelected: onSelect,
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.background,
              child: Column(
                children: [
                  const ShellTopBar(showSearch: true, showQuickActions: true),
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
