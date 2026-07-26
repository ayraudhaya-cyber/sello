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

/// Sello (sales) adaptive shell — phone bottom nav, tablet/desktop rail.
class SelloShell extends ConsumerWidget {
  const SelloShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const destinations = <SelloNavDestination>[
    SelloNavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      location: RoutePaths.selloDashboard,
    ),
    SelloNavDestination(
      label: 'Customers',
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      location: RoutePaths.selloCustomers,
    ),
    SelloNavDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      location: RoutePaths.selloProducts,
    ),
    SelloNavDestination(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      location: RoutePaths.selloOrders,
    ),
    SelloNavDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      location: RoutePaths.selloProfile,
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
        mobile: (_) => _MobileSelloShell(
          navigationShell: navigationShell,
          index: index,
          onSelect: _onSelect,
        ),
        tablet: (_) => _RailSelloShell(
          navigationShell: navigationShell,
          index: index,
          onSelect: _onSelect,
          extended: context.screenWidth >= 840,
        ),
        desktop: (_) => _RailSelloShell(
          navigationShell: navigationShell,
          index: index,
          onSelect: _onSelect,
          extended: true,
        ),
      ),
    );
  }
}

class _MobileSelloShell extends StatelessWidget {
  const _MobileSelloShell({
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
        title: const SelloBrandMark(compact: false, size: 32),
        actions: const [
          GlobalSearchControl(),
          NotificationBellButton(),
          UserProfileMenu(compact: true),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: [
          for (final d in SelloShell.destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _RailSelloShell extends StatelessWidget {
  const _RailSelloShell({
    required this.navigationShell,
    required this.index,
    required this.onSelect,
    required this.extended,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: onSelect,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.md,
                bottom: AppSpacing.lg,
              ),
              child: SelloBrandMark(compact: !extended, size: extended ? 36 : 32),
            ),
            destinations: [
              for (final d in SelloShell.destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
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
