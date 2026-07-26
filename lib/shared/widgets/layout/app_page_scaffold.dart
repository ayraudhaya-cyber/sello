import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/chrome/sello_breadcrumbs.dart';
import 'package:sello/shared/widgets/chrome/shell_chrome.dart';
import 'package:sello/shared/widgets/layout/sello_page.dart';

/// Shared page scaffold used by feature modules inside either shell.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.floatingActionButton,
    this.showBreadcrumbs = true,
    this.showHeader = true,
    this.padding,
    this.maxWidth,
    this.breadcrumbs,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBreadcrumbs;
  final bool showHeader;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;
  final List<BreadcrumbData>? breadcrumbs;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final crumbs = breadcrumbs ?? RouteTitles.breadcrumbsFor(location);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: floatingActionButton,
      body: AnimatedSwitcher(
        duration: AppDurations.fast,
        switchInCurve: AppCurves.standard,
        child: SelloPageContainer(
          key: ValueKey(location),
          maxWidth: maxWidth,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHeader) ...[
                if (showBreadcrumbs && !context.isMobile) ...[
                  SelloBreadcrumbs(items: crumbs),
                  const SizedBox(height: AppSpacing.sm),
                ],
                SelloSectionHeader(
                  title: title,
                  subtitle: subtitle,
                  action: actions == null
                      ? null
                      : Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: actions!,
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              body,
            ],
          ),
        ),
      ),
    );
  }
}

/// Top utility bar for Hub desktop/tablet (search, notifications, profile).
class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    super.key,
    this.title,
    this.showSearch = true,
    this.leading,
  });

  final String? title;
  final bool showSearch;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          ?leading,
          if (title != null) ...[
            Text(title!, style: context.texts.titleMedium),
            const SizedBox(width: AppSpacing.md),
          ],
          if (showSearch && context.isDesktop)
            const GlobalSearchControl(expanded: true)
          else if (showSearch)
            const GlobalSearchControl(),
          const Spacer(),
          const NotificationBellButton(),
          const SizedBox(width: AppSpacing.xxs),
          UserProfileMenu(compact: context.isMobile),
        ],
      ),
    );
  }
}
