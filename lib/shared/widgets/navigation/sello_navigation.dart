import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/widgets/branding/branded_logo.dart';
import 'package:sello/shared/widgets/icons/sello_nav_icons.dart';

class SelloNavDestination {
  const SelloNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.location,
    this.glyph,
    this.badge,
    this.branchIndex,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  /// Thin stroke icon for Hub sidebar; falls back to [icon] when null.
  final SelloNavGlyph? glyph;
  final String location;
  final String? badge;

  /// StatefulShell branch index — required when nav is permission-filtered.
  final int? branchIndex;
}

class SelloNavSection {
  const SelloNavSection({
    required this.label,
    required this.destinations,
  });

  final String label;
  final List<SelloNavDestination> destinations;
}

/// Official Sello mark + wordmark, or the client brand logo when configured.
class SelloBrandMark extends ConsumerWidget {
  const SelloBrandMark({
    super.key,
    this.compact = false,
    this.hub = false,
    this.size,
    this.light = false,
  });

  final bool compact;
  final bool hub;
  final double? size;
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logoSize = size ?? (compact ? 32.0 : 36.0);
    final branding = ref.watch(brandingProvider);

    if (branding.hasCustomLogo) {
      final sidebar = hub && !compact && size == null;
      return Align(
        alignment: Alignment.centerLeft,
        child: BrandedLogo(
          size: compact ? 26 : (sidebar ? 36 : (size ?? 36)),
          maxWidth: compact ? 88 : (sidebar ? 208 : 180),
          branding: branding,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandedLogo(
          size: logoSize,
          shadows: light ? null : AppShadows.level1,
        ),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Sello',
            style: context.texts.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.02 * 21,
              fontSize: 21,
              color: light ? AppColors.navInkStrong : AppColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Dark Hub sidebar with sectioned destinations (HTML nav rail).
class SelloSideNav extends StatelessWidget {
  const SelloSideNav({
    super.key,
    required this.sections,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.footer,
    this.width = AppSpacing.sidebarWidth,
    this.dark = true,
  });

  final List<SelloNavSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? footer;
  final double width;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var flatIndex = 0;
    for (final section in sections) {
      children.add(
        Padding(
          padding: EdgeInsets.fromLTRB(
            dark ? 28 : AppSpacing.sm,
            20,
            AppSpacing.sm,
            8,
          ),
          child: Text(
            section.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.11 * 10.5,
              color: dark ? AppColors.navInkFaint : AppColors.textFaint,
            ),
          ),
        ),
      );
      for (final item in section.destinations) {
        final index = item.branchIndex ?? flatIndex;
        flatIndex++;
        final selected = index == selectedIndex;
        children.add(
          _SideNavItem(
            label: item.label,
            icon: selected ? item.selectedIcon : item.icon,
            glyph: item.glyph,
            selected: selected,
            badge: item.badge,
            dark: dark,
            onTap: () => onDestinationSelected(index),
          ),
        );
      }
    }

    return AnimatedContainer(
      duration: AppDurations.fast,
      width: width,
      decoration: BoxDecoration(
        gradient: dark ? context.selloColors.navRail : null,
        color: dark ? null : AppColors.surface,
        border: dark
            ? const Border(
                right: BorderSide(color: Color(0x0DFFFFFF)),
              )
            : const Border(right: BorderSide(color: AppColors.outline)),
      ),
      child: Stack(
        children: [
          if (dark)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.navRailGlow),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.mdPlus,
                ),
                child: SelloBrandMark(hub: true, light: dark),
              ),
              Expanded(
                child: ListView(
                  // Left gutter is owned by each item (indicator + 16px inset)
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.md),
                  children: children,
                ),
              ),
              if (footer != null) ...[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: footer,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatefulWidget {
  const _SideNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.dark,
    this.glyph,
    this.badge,
  });

  final String label;
  final IconData icon;
  final SelloNavGlyph? glyph;
  final bool selected;
  final VoidCallback onTap;
  final bool dark;
  final String? badge;

  @override
  State<_SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<_SideNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final dark = widget.dark;
    final hovered = _hovered && !selected;

    // HTML: active = nav-active fill; hover (inactive only) = nav-hover + translateX(2)
    final background = selected
        ? (dark ? AppColors.navActive : context.selloColors.surfaceSelected)
        : hovered
            ? (dark ? AppColors.navHover : AppColors.veil)
            : Colors.transparent;

    final ink = selected
        ? (dark ? AppColors.navInkStrong : AppColors.textPrimary)
        : (dark ? AppColors.navInk : context.selloColors.textSecondary);

    // HTML: active icon = nav-accent at full opacity; idle icons ~0.7
    final accent = context.brandAccent;
    final iconColor = selected
        ? (dark ? Color.lerp(accent, Colors.white, 0.42)! : accent)
        : (dark
            ? AppColors.navInk.withValues(alpha: 0.72)
            : context.selloColors.textSecondary);

    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (widget.glyph != null)
              SelloNavIcon(
                glyph: widget.glyph!,
                color: iconColor,
                selected: selected,
              )
            else
              Icon(widget.icon, size: 17, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
            ),
            if (widget.badge != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0x38E8686D)
                      : AppColors.attentionSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  widget.badge!,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: dark
                        ? const Color(0xFFFFB4B7)
                        : AppColors.attention,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // HTML ::before sits in the 16px left gutter (left: -16px on the item).
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedOpacity(
                    duration: AppDurations.fast,
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: dark ? iconColor : accent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  // Hover nudge only when not selected (HTML transform)
                  tween: Tween(begin: 0, end: hovered ? 2.0 : 0.0),
                  duration: const Duration(milliseconds: 200),
                  curve: const Cubic(0.22, 0.61, 0.36, 1),
                  builder: (context, dx, child) {
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: pill,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
