import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/cards/sello_card.dart';
import 'package:sello/shared/widgets/states/sello_empty_state.dart';

/// Consistent page header for feature screens.
///
/// Hierarchy is purely typographic: an optional uppercase eyebrow, a tight
/// display-weight title, and a measured subtitle in secondary text.
class SelloSectionHeader extends StatelessWidget {
  const SelloSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
    this.inlineAction = false,
    this.leading,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? action;

  /// Placed before the title (e.g. a back button on pushed pages).
  final Widget? leading;

  /// Keep [action] on the title row even on narrow screens. Use with compact
  /// actions (icon buttons, one small button) so the header saves height.
  final bool inlineAction;

  @override
  Widget build(BuildContext context) {
    final titleStyle = context.isMobile
        ? context.texts.headlineMedium
        : context.texts.headlineLarge;

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!.toUpperCase(), style: AppTypography.eyebrow),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(title, style: titleStyle?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              subtitle!,
              style: context.texts.bodyMedium?.copyWith(
                color: context.selloColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
    final heading = leading == null
        ? titleColumn
        : Row(
            children: [
              leading!,
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: titleColumn),
            ],
          );

    if (action == null) return heading;

    if (inlineAction) {
      return Row(
        crossAxisAlignment: subtitle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          const SizedBox(width: AppSpacing.sm),
          action!,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            !constraints.maxWidth.isFinite ||
            constraints.maxWidth < ResponsiveLayout.formFieldMinWidth * 2;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: AppSpacing.sm),
              action!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        );
      },
    );
  }
}

/// Secondary page-header action (refresh, shortcuts). Icon-only with a
/// tooltip on phones so it fits beside the title; labelled on wider screens.
class SelloHeaderAction extends StatelessWidget {
  const SelloHeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? AppColors.textSecondary : AppColors.textDisabled;
    final iconOnly = context.isMobile;
    return Tooltip(
      message: label,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlAll,
          side: const BorderSide(color: AppColors.outlineStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: iconOnly ? 44 : 40,
            width: iconOnly ? 44 : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: color),
                  if (!iconOnly) ...[
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Constrains page content and applies responsive padding.
class SelloPageContainer extends StatelessWidget {
  const SelloPageContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.scrollable = true,
    this.onRefresh,
    this.onNearEnd,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;

  /// Enables pull-to-refresh when [scrollable].
  final Future<void> Function()? onRefresh;

  /// Called when the user scrolls close to the bottom (load more).
  final VoidCallback? onNearEnd;

  @override
  Widget build(BuildContext context) {
    final gutter = context.pagePadding;
    final vertical = context.isMobile ? AppSpacing.lg : AppSpacing.xl;

    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? context.contentMaxWidth,
        ),
        child: Padding(
          // Extra bottom padding keeps the last card clear of the viewport
          // edge when a page scrolls.
          padding:
              padding ??
              EdgeInsets.fromLTRB(
                gutter,
                vertical,
                gutter,
                vertical + AppSpacing.lg,
              ),
          child: child,
        ),
      ),
    );

    if (!scrollable) return content;

    Widget scroll = SingleChildScrollView(
      physics: onRefresh == null
          ? const BouncingScrollPhysics()
          : const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
      child: content,
    );

    final nearEnd = onNearEnd;
    if (nearEnd != null) {
      scroll = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final metrics = notification.metrics;
          if (notification is ScrollUpdateNotification &&
              metrics.axis == Axis.vertical &&
              metrics.extentAfter < 480) {
            nearEnd();
          }
          return false;
        },
        child: scroll,
      );
    }

    final refresh = onRefresh;
    if (refresh != null) {
      scroll = RefreshIndicator(onRefresh: refresh, child: scroll);
    }
    return scroll;
  }
}

/// Responsive app bar that stays light and minimal.
class SelloAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelloAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.bottom,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      bottom: bottom,
    );
  }
}

/// Coming-soon placeholder used while business modules are not implemented.
class SelloPlaceholderPage extends StatelessWidget {
  const SelloPlaceholderPage({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.construction_rounded,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SelloPageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelloSectionHeader(title: title, subtitle: description),
          const SizedBox(height: AppSpacing.xl),
          SelloCard(
            child: SelloEmptyState(
              title: 'Module foundation ready',
              message:
                  'Business features for this area will be implemented in a later phase.',
              icon: icon,
            ),
          ),
        ],
      ),
    );
  }
}
