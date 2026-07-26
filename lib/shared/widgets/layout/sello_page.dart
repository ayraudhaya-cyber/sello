import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/widgets/cards/sello_card.dart';
import 'package:sello/shared/widgets/states/sello_empty_state.dart';

/// Consistent page header for feature screens.
class SelloSectionHeader extends StatelessWidget {
  const SelloSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.texts.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle!,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.selloColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
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
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? context.contentMaxWidth,
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.all(context.pagePadding),
          child: child,
        ),
      ),
    );

    if (!scrollable) return content;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: content,
    );
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
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

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
            elevation: SelloCardElevation.soft,
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
