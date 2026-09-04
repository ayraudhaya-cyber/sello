import 'package:flutter/material.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/responsive/app_breakpoints.dart';
import 'package:sello/core/theme/theme.dart';

enum SelloCardElevation { flat, soft, raised }

/// Soft rounded container for icons — HTML `.kpi-icon` / `.action-sev`.
class SelloIconBadge extends StatelessWidget {
  const SelloIconBadge({
    super.key,
    required this.icon,
    this.size = 36,
    this.iconSize = 16,
    this.color,
    this.backgroundColor,
    this.radius = 11,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? backgroundColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.brandAccent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: accent),
    );
  }
}

/// Surface card — flat by default; HTML hover = −2px lift + purple shadow.
///
/// Lift uses [Transform.translate] so layout size stays stable inside scroll
/// views (AnimatedContainer Matrix4 transforms caused blank-page asserts).
class SelloCard extends StatefulWidget {
  const SelloCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevation = SelloCardElevation.flat,
    this.color,
    this.borderColor,
    this.enableHoverLift = true,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final SelloCardElevation elevation;
  final Color? color;
  final Color? borderColor;
  final bool enableHoverLift;
  final BorderRadius? borderRadius;

  @override
  State<SelloCard> createState() => _SelloCardState();
}

class _SelloCardState extends State<SelloCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppRadius.cardAll;
    final baseShadows = switch (widget.elevation) {
      SelloCardElevation.flat => AppShadows.none,
      SelloCardElevation.soft => AppShadows.level1,
      SelloCardElevation.raised => AppShadows.level2,
    };
    final hovered = widget.enableHoverLift && _hovered;
    final shadows = hovered ? AppShadows.hover : baseShadows;

    // Expand to fill when a parent [SelloEqualHeightRow] assigns a shared height.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fill = constraints.hasBoundedHeight &&
            constraints.maxHeight < double.infinity;

        final painted = AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: const Cubic(0.22, 0.61, 0.36, 1),
          width: double.infinity,
          height: fill ? constraints.maxHeight : null,
          alignment: Alignment.topLeft,
          padding:
              widget.padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: widget.color ?? AppColors.surface,
            borderRadius: radius,
            border: widget.borderColor != null
                ? Border.all(color: widget.borderColor!)
                : null,
            boxShadow: shadows,
          ),
          child: widget.child,
        );

        // Shadow-only hover — no Transform.translate (that shifts hit targets
        // and leaves nested list/chip hovers stuck on Flutter web).
        final interactive = MouseRegion(
          onEnter: widget.enableHoverLift || widget.onTap != null
              ? (_) => _setHovered(true)
              : null,
          onExit: widget.enableHoverLift || widget.onTap != null
              ? (_) => _setHovered(false)
              : null,
          child: painted,
        );

        if (widget.onTap == null) return interactive;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: context.brandAccent.withValues(alpha: 0.05),
            borderRadius: radius,
            child: interactive,
          ),
        );
      },
    );
  }
}

/// HTML `.kpi-card` — icon+trend top, uppercase label, value, sparkline.
class SelloStatCard extends StatelessWidget {
  const SelloStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trendLabel,
    this.trendPositive,
    this.hint,
    this.onTap,
    this.tone,
    this.sparkPoints,
    this.compact = false,
    this.emphasized = false,
    this.quiet = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? trendLabel;
  final bool? trendPositive;
  /// Supporting line under the value (e.g. "Active catalog").
  final String? hint;
  final VoidCallback? onTap;
  final Color? tone;
  final List<double>? sparkPoints;

  /// Tighter padding for dense mobile workspaces.
  final bool compact;

  /// Slightly stronger surface treatment for a primary KPI.
  final bool emphasized;

  /// Supporting metric — softer chrome, secondary as plain text (no pill).
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final accent = tone ?? context.brandAccent;
    final soft = Color.lerp(
      Colors.white,
      accent,
      emphasized
          ? 0.12
          : quiet
              ? 0.05
              : 0.08,
    )!;
    final up = trendPositive == true;
    final down = trendPositive == false;
    final trendColor = quiet
        ? AppColors.textTertiary
        : up
            ? AppColors.success
            : down
                ? AppColors.attention
                : AppColors.textTertiary;
    final padding = compact
        ? EdgeInsets.fromLTRB(12, quiet ? 10 : 12, 12, quiet ? 8 : 10)
        : const EdgeInsets.fromLTRB(20, 20, 20, 14);
    final showTrendPill = trendLabel != null && !quiet;

    return SelloCard(
      elevation: SelloCardElevation.flat,
      enableHoverLift: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      padding: padding,
      color: emphasized ? soft.withValues(alpha: 0.55) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null)
                SelloIconBadge(
                  icon: icon!,
                  size: compact ? (quiet ? 28 : 30) : 36,
                  iconSize: compact ? (quiet ? 13 : 14) : 16,
                  color: quiet ? AppColors.textTertiary : accent,
                  backgroundColor: soft,
                  radius: 10,
                ),
              const Spacer(),
              if (showTrendPill)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.outlineSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trendPositive != null) ...[
                            Icon(
                              up
                                  ? Icons.north_east_rounded
                                  : Icons.south_east_rounded,
                              size: 10,
                              color: trendColor,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              trendLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: compact ? 10.5 : 11.5,
                                fontWeight: FontWeight.w600,
                                color: trendColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? (quiet ? 6 : 8) : 18),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05 * 10.5,
              color: AppColors.textFaint,
            ),
          ),
          SizedBox(height: compact ? 2 : 8),
          Text(
            value,
            style: emphasized
                ? AppTypography.metric.copyWith(fontSize: 26)
                : quiet
                    ? AppTypography.metric.copyWith(fontSize: 22)
                    : AppTypography.metric,
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (quiet && trendLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              trendLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (sparkPoints != null && sparkPoints!.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              width: double.infinity,
              child: CustomPaint(
                painter: _KpiSparkPainter(
                  points: sparkPoints!,
                  color: accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiSparkPainter extends CustomPainter {
  _KpiSparkPainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minV = points.reduce((a, b) => a < b ? a : b);
    final maxV = points.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : maxV - minV;

    Offset pt(int i) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * (1 - (points[i] - minV) / range);
      return Offset(x, y.clamp(1.0, size.height - 1));
    }

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _KpiSparkPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

/// Responsive grid of [SelloStatCard]s — one row when possible, equal widths.
///
/// Column count tracks the number of cards (up to [maxColumns]) so 3 cards
/// fill the row instead of leaving empty space, and 5 cards stay on one line
/// on desktop.
class SelloStatCardGrid extends StatelessWidget {
  const SelloStatCardGrid({
    super.key,
    required this.children,
    this.gap = AppSpacing.md,
    this.maxColumns = 5,
  });

  final List<Widget> children;
  final double gap;

  /// Maximum columns on large screens (e.g. 6 for Reports, 5 for domain lists).
  final int maxColumns;

  int _columnsForWidth(double width, int childCount) {
    final cap = maxColumns.clamp(1, 12);
    final wanted = childCount.clamp(1, cap);
    if (width < AppBreakpoints.mobile) {
      return width < 400 ? 1 : 2.clamp(1, wanted);
    }
    if (width < AppBreakpoints.tablet) {
      return 3.clamp(1, wanted);
    }
    return wanted;
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = _columnsForWidth(width, children.length);
        final itemWidth = (width - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

/// Dashboard section card with title and optional action.
class SelloDashboardCard extends StatelessWidget {
  const SelloDashboardCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.padding,
    this.countBadge,
    this.quietHeader = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final EdgeInsetsGeometry? padding;
  final String? countBadge;

  /// Softer section label — guides the eye without competing with content.
  final bool quietHeader;

  @override
  Widget build(BuildContext context) {
    final titleStyle = quietHeader
        ? AppTypography.sectionTitle.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          )
        : AppTypography.sectionTitle;

    return SelloCard(
      elevation: SelloCardElevation.flat,
      enableHoverLift: true,
      borderRadius: BorderRadius.circular(AppRadius.card),
      // 24px sides — keeps section titles aligned across the dashboard.
      padding: padding ?? const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(title, style: titleStyle),
              if (countBadge != null) ...[
                const SizedBox(width: 8),
                Text(
                  countBadge!,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const Spacer(),
              ?action,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          SizedBox(height: quietHeader ? 12 : 18),
          child,
        ],
      ),
    );
  }
}

/// Compact “View all →” text link — HTML `.link-btn`.
class SelloViewAllLink extends StatefulWidget {
  const SelloViewAllLink({
    super.key,
    this.label = 'View all',
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  State<SelloViewAllLink> createState() => _SelloViewAllLinkState();
}

class _SelloViewAllLinkState extends State<SelloViewAllLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _hovered
                      ? AppColors.brandIndigo
                      : AppColors.textSecondary,
                ),
              ),
              AnimatedContainer(
                duration: AppDurations.fast,
                width: _hovered ? 8 : 4,
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _hovered
                    ? AppColors.brandIndigo
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
