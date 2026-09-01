import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/iam/iam_providers.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/widgets/branding/branded_logo.dart';
import 'package:sello/shared/widgets/branding/branded_shell_app_bar.dart';
import 'package:sello/shared/widgets/chrome/shell_chrome.dart';
import 'package:sello/shared/widgets/layout/app_page_scaffold.dart';
import 'package:sello/shared/widgets/navigation/sello_navigation.dart';

/// Sello (sales) adaptive shell — phone bottom nav, tablet/desktop rail.
///
/// Destinations are filtered by [PermissionService].
class SelloShell extends ConsumerWidget {
  const SelloShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const catalog = <SelloNavDestination>[
    SelloNavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      location: RoutePaths.selloDashboard,
      branchIndex: 0,
    ),
    SelloNavDestination(
      label: 'Customers',
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      location: RoutePaths.selloCustomers,
      branchIndex: 1,
    ),
    SelloNavDestination(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      location: RoutePaths.selloProducts,
      branchIndex: 2,
    ),
    SelloNavDestination(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      location: RoutePaths.selloOrders,
      branchIndex: 3,
    ),
    SelloNavDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      location: RoutePaths.selloProfile,
      branchIndex: 4,
    ),
  ];

  static List<SelloNavDestination> get destinations => catalog;

  static List<SelloNavDestination> destinationsFor(
    PermissionService? permissions,
  ) {
    if (permissions == null) return catalog;
    return [
      for (final dest in catalog)
        if (permissions.canAccessRoute(dest.location)) dest,
    ];
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
    final items = destinationsFor(ref.watch(permissionServiceProvider));

    return AnimatedSwitcher(
      duration: AppDurations.normal,
      switchInCurve: AppCurves.standard,
      child: ResponsiveBuilder(
        key: ValueKey(context.windowSize),
        mobile: (_) => _MobileSelloShell(
          navigationShell: navigationShell,
          index: index,
          destinations: items,
          onSelect: _onSelect,
        ),
        tablet: (_) => _RailSelloShell(
          navigationShell: navigationShell,
          index: index,
          destinations: items,
          onSelect: _onSelect,
          extended: context.screenWidth >= 840,
        ),
        desktop: (_) => _RailSelloShell(
          navigationShell: navigationShell,
          index: index,
          destinations: items,
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
    required this.destinations,
    required this.onSelect,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final List<SelloNavDestination> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final visibleSelected = destinations.indexWhere(
      (d) => (d.branchIndex ?? 0) == index,
    );

    final onHome = index == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: onHome
          ? null
          : BrandedShellAppBar(
              actions: const [
                NotificationBellButton(),
                UserProfileMenu(compact: true),
                SizedBox(width: AppSpacing.xs),
              ],
            ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: visibleSelected < 0 ? 0 : visibleSelected,
        onDestinationSelected: (i) {
          onSelect(destinations[i].branchIndex ?? i);
        },
        destinations: [
          for (final d in destinations)
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

class _RailSelloShell extends ConsumerWidget {
  const _RailSelloShell({
    required this.navigationShell,
    required this.index,
    required this.destinations,
    required this.onSelect,
    required this.extended,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final List<SelloNavDestination> destinations;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleSelected = destinations.indexWhere(
      (d) => (d.branchIndex ?? 0) == index,
    );
    final branding = ref.watch(brandingProvider);
    final darkLogo =
        branding.hasCustomLogo || branding.hasCustomNavBackground;
    final mark = SelloBrandMark(
      compact: !extended,
      size: extended ? 36 : 32,
      light: darkLogo,
    );

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: visibleSelected < 0 ? 0 : visibleSelected,
            onDestinationSelected: (i) {
              onSelect(destinations[i].branchIndex ?? i);
            },
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.md,
                bottom: AppSpacing.lg,
              ),
              child: darkLogo
                  ? BrandedDarkSurface(
                      borderRadius: AppRadius.panelAll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: mark,
                    )
                  : mark,
            ),
            destinations: [
              for (final d in destinations)
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
                const ShellTopBar(showSearch: true, showQuickActions: true),
                Expanded(child: navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
