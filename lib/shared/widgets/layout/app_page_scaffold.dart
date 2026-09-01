import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/devtools/dev_experience.dart';
import 'package:sello/shared/widgets/chrome/quick_actions_button.dart';
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
    this.floatingActionButtonLocation,
    this.showBreadcrumbs = true,
    this.showHeader = true,
    this.padding,
    this.maxWidth,
    this.breadcrumbs,
    this.headerSpacing = AppSpacing.section,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool showBreadcrumbs;
  final bool showHeader;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;
  final List<BreadcrumbData>? breadcrumbs;

  /// Gap between the page header and [body].
  final double headerSpacing;

  /// When false, the page does not scroll as a whole so a child can pin a
  /// side nav and scroll only its content pane.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final crumbs = breadcrumbs ?? RouteTitles.breadcrumbsFor(location);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.canvas,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.canvasGlow),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.canvasAccent),
              ),
            ),
            AnimatedSwitcher(
              duration: AppDurations.fast,
              switchInCurve: AppCurves.standard,
              child: SelloPageContainer(
                key: ValueKey(location),
                maxWidth: maxWidth,
                padding: padding,
                scrollable: scrollable,
                child: Column(
                  mainAxisSize:
                      scrollable ? MainAxisSize.min : MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showHeader) ...[
                      if (showBreadcrumbs && !context.isMobile) ...[
                        SelloBreadcrumbs(items: crumbs),
                        const SizedBox(height: AppSpacing.xs),
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
                      SizedBox(height: headerSpacing),
                    ],
                    if (scrollable) body else Expanded(child: body),
                  ],
                ),
              ),
            ),
          ],
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
    this.showQuickActions = false,
    this.leading,
  });

  final String? title;
  final bool showSearch;
  final bool showQuickActions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.topBarHeight,
      padding: EdgeInsets.symmetric(
        horizontal: context.isMobile ? AppSpacing.md : AppSpacing.pageDesktop,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.outlineSubtle),
        ),
      ),
      child: Row(
        children: [
          ?leading,
          if (title != null) ...[
            Text(
              title!,
              style: context.texts.titleSmall?.copyWith(
                color: context.selloColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          if (showSearch && !context.isMobile)
            const GlobalSearchControl(expanded: true)
          else if (showSearch)
            const GlobalSearchControl(),
          const Spacer(),
          if (!kReleaseMode) const DevExperienceToolbarButton(),
          if (showQuickActions) ...[
            QuickActionsButton(compact: context.isMobile),
            const SizedBox(width: AppSpacing.sm),
          ],
          const NotificationBellButton(),
          const SizedBox(width: AppSpacing.xxs),
          const _TopBarSeparator(),
          const SizedBox(width: AppSpacing.xxs),
          UserProfileMenu(compact: context.isMobile),
        ],
      ),
    );
  }
}

/// Hairline divider that groups top-bar utilities without adding weight.
class _TopBarSeparator extends StatelessWidget {
  const _TopBarSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      color: AppColors.outlineSubtle,
    );
  }
}
