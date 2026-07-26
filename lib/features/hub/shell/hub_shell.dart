import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/chrome/shell_chrome.dart';
import 'package:sello/shared/widgets/layout/app_page_scaffold.dart';
import 'package:sello/shared/widgets/navigation/sello_navigation.dart';

/// Sello Hub adaptive shell — drawer on phone, permanent sidebar on larger.
class HubShell extends ConsumerWidget {
  const HubShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const destinations = <SelloNavDestination>[
    SelloNavDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      location: RoutePaths.hubDashboard,
    ),
    SelloNavDestination(
      label: 'Customers',
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      location: RoutePaths.hubCustomers,
    ),
    SelloNavDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      location: RoutePaths.hubProducts,
    ),
    SelloNavDestination(
      label: 'Inventory',
      icon: Icons.warehouse_outlined,
      selectedIcon: Icons.warehouse_rounded,
      location: RoutePaths.hubInventory,
    ),
    SelloNavDestination(
      label: 'Employees',
      icon: Icons.badge_outlined,
      selectedIcon: Icons.badge_rounded,
      location: RoutePaths.hubEmployees,
    ),
    SelloNavDestination(
      label: 'Reports',
      icon: Icons.description_outlined,
      selectedIcon: Icons.description_rounded,
      location: RoutePaths.hubReports,
    ),
    SelloNavDestination(
      label: 'Analytics',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      location: RoutePaths.hubAnalytics,
    ),
    SelloNavDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      location: RoutePaths.hubSettings,
    ),
  ];

  void _onSelect(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;

    return AnimatedSwitcher(
      duration: AppDurations.normal,
      switchInCurve: AppCurves.standard,
      child: ResponsiveBuilder(
        key: ValueKey(context.windowSize),
        mobile: (_) => _MobileHubShell(
          navigationShell: navigationShell,
          index: index,
          onSelect: _onSelect,
        ),
        tablet: (_) => _SidebarHubShell(
          navigationShell: navigationShell,
          index: index,
          onSelect: _onSelect,
          sidebarWidth: AppSpacing.sidebarWidthCompact,
        ),
        desktop: (_) => _SidebarHubShell(
          navigationShell: navigationShell,
          index: index,
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
    required this.onSelect,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SelloBrandMark(hub: true, size: 32),
        actions: const [
          GlobalSearchControl(),
          NotificationBellButton(),
          UserProfileMenu(compact: true),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: SelloSideNav(
            width: double.infinity,
            destinations: HubShell.destinations,
            selectedIndex: index,
            onDestinationSelected: (i) {
              Navigator.of(context).pop();
              onSelect(i);
            },
          ),
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
    required this.onSelect,
    required this.sidebarWidth,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final ValueChanged<int> onSelect;
  final double sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SelloSideNav(
            width: sidebarWidth,
            destinations: HubShell.destinations,
            selectedIndex: index,
            onDestinationSelected: onSelect,
          ),
          Expanded(
            child: Column(
              children: [
                const ShellTopBar(showSearch: true),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
