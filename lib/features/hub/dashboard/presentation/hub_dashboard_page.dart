import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/intelligence/application/intelligence_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/intelligence_insight.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Owner / manager Hub dashboard — pixel-matched to `sello-dashboard.html`.
class HubDashboardPage extends ConsumerStatefulWidget {
  const HubDashboardPage({super.key});

  @override
  ConsumerState<HubDashboardPage> createState() => _HubDashboardPageState();
}

class _HubDashboardPageState extends ConsumerState<HubDashboardPage> {
  String _range = 'month';
  String _metric = 'revenue';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final name = session?.displayName.split(' ').first ?? 'there';
    final branch = session?.branchName ?? 'Colombo Branch';
    final date = DateFormat('EEE, d MMM yyyy').format(DateTime.now());
    final gap = AppSpacing.gap;
    final stackHero = context.screenWidth < 1180;
    final stackPairs = context.screenWidth < 860;
    final kpiCols = context.responsiveValue(mobile: 2, tablet: 3, desktop: 5);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final performance = _PerformanceCard(
      range: _range,
      metric: _metric,
      onRange: (v) => setState(() => _range = v),
      onMetric: (v) => setState(() => _metric = v),
    );
    const actions = _ActionCenterCard();

    return AppPageScaffold(
      title: '',
      showHeader: false,
      showBreadcrumbs: false,
      maxWidth: AppSpacing.contentMax,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WelcomeRow(
            greeting: greeting,
            name: name,
            branch: branch,
            date: date,
          ),
          SizedBox(height: gap),
          _KpiGrid(columns: kpiCols, gap: gap),
          SizedBox(height: gap),
          if (stackHero)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                performance,
                SizedBox(height: gap),
                actions,
              ],
            )
          else
            SelloEqualHeightRow(
              flexes: const [68, 32],
              children: [
                performance,
                actions,
              ],
            ),
          SizedBox(height: gap),
          if (stackPairs) ...[
            const _ActivityCard(),
            SizedBox(height: gap),
            const _InventoryHealthCard(),
          ] else
            const SelloEqualHeightRow(
              children: [
                _ActivityCard(),
                _InventoryHealthCard(),
              ],
            ),
          SizedBox(height: gap),
          if (stackPairs) ...[
            const _TopCustomersCard(),
            SizedBox(height: gap),
            const _BestSellersCard(),
          ] else
            const SelloEqualHeightRow(
              children: [
                _TopCustomersCard(),
                _BestSellersCard(),
              ],
            ),
          SizedBox(height: gap),
          const _InsightsSection(),
        ],
      ),
    );
  }
}

// ─── Welcome ───────────────────────────────────────────────────────────────

class _WelcomeRow extends StatelessWidget {
  const _WelcomeRow({
    required this.greeting,
    required this.name,
    required this.branch,
    required this.date,
  });

  final String greeting;
  final String name;
  final String branch;
  final String date;

  @override
  Widget build(BuildContext context) {
    final titleSize = context.isMobile ? 28.0 : 32.0;
    final title = Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: titleSize,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.03 * titleSize,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
        children: [
          TextSpan(text: '$greeting, $name '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _WavingHand(fontSize: titleSize * 0.78),
            ),
          ),
        ],
      ),
    );

    final sub = Text(
      "Here's what's happening in your business today.",
      style: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 14,
        height: 1.6,
        color: AppColors.textTertiary,
      ),
    );

    final chips = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetaChip(icon: Icons.location_on_outlined, label: branch),
        _MetaChip(icon: Icons.calendar_today_outlined, label: date),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 14),
      child: context.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 4),
                sub,
                const SizedBox(height: 18),
                chips,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: sub,
                      ),
                    ],
                  ),
                ),
                chips,
              ],
            ),
    );
  }
}

/// Matches `.welcome-title .wave` in `references/sello-dashboard.html`.
class _WavingHand extends StatefulWidget {
  const _WavingHand({required this.fontSize});

  final double fontSize;

  @override
  State<_WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<_WavingHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// HTML keyframes: 0° → 14° → -8° → 12° → 0°
  double _angleFor(double t) {
    double seg(double a, double b, double local) =>
        a + (b - a) * Curves.easeInOut.transform(local.clamp(0.0, 1.0));

    if (t < 0.15) return seg(0, 14, t / 0.15);
    if (t < 0.30) return seg(14, -8, (t - 0.15) / 0.15);
    if (t < 0.45) return seg(-8, 12, (t - 0.30) / 0.15);
    if (t < 0.60) return seg(12, 0, (t - 0.45) / 0.15);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _angleFor(_controller.value) * math.pi / 180;
        return Transform.rotate(
          angle: angle,
          alignment: const Alignment(0.4, 0.4), // ~70% 70% origin
          child: child,
        );
      },
      child: Text(
        '👋',
        style: TextStyle(
          fontSize: widget.fontSize,
          height: 1,
        ),
      ),
    );
  }
}

class _MetaChip extends StatefulWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_MetaChip> createState() => _MetaChipState();
}

class _MetaChipState extends State<_MetaChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _hovered ? -2.0 : 0.0),
        duration: const Duration(milliseconds: 220),
        curve: const Cubic(0.22, 0.61, 0.36, 1),
        builder: (context, dy, child) {
          return Transform.translate(offset: Offset(0, dy), child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? Colors.white : Colors.white.withValues(alpha: 0.86),
            borderRadius: AppRadius.controlAll,
            border: Border.all(
              color: _hovered ? context.brandMid : AppColors.outline,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: const Color(0xFF6710AA).withValues(alpha: 0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : AppShadows.level1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: context.brandAccent),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── KPIs ──────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.columns, required this.gap});

  final int columns;
  final double gap;

  static final _items = <_KpiSpec>[
    _KpiSpec(
      label: 'Revenue (MTD)',
      value: 'Rs 4.82M',
      trend: '12.4%',
      up: true,
      icon: Icons.payments_outlined,
      spark: const [0.35, 0.42, 0.38, 0.55, 0.50, 0.72, 0.68, 0.85],
      route: null,
    ),
    _KpiSpec(
      label: 'Orders',
      value: '1,248',
      trend: '6.1%',
      up: true,
      icon: Icons.shopping_cart_outlined,
      tone: AppColors.ops,
      spark: const [0.40, 0.35, 0.52, 0.48, 0.65, 0.60, 0.78, 0.72],
      route: RoutePaths.hubOrders,
    ),
    _KpiSpec(
      label: 'Active Customers',
      value: '386',
      trend: '3.8%',
      up: true,
      icon: Icons.groups_outlined,
      tone: AppColors.success,
      spark: const [0.45, 0.48, 0.42, 0.58, 0.55, 0.68, 0.62, 0.80],
      route: RoutePaths.hubCustomers,
    ),
    _KpiSpec(
      label: 'Outstanding Collections',
      value: 'Rs 612K',
      trend: '2.1%',
      up: false,
      icon: Icons.credit_card_outlined,
      tone: AppColors.finance,
      spark: const [0.75, 0.70, 0.72, 0.58, 0.60, 0.48, 0.50, 0.40],
      route: RoutePaths.hubPayments,
    ),
    _KpiSpec(
      label: 'Low Stock Alerts',
      value: '9 items',
      trend: '4 new',
      up: false,
      icon: Icons.warning_amber_rounded,
      tone: AppColors.attention,
      spark: const [0.30, 0.35, 0.32, 0.45, 0.42, 0.58, 0.55, 0.70],
      route: RoutePaths.hubInventory,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = columns.clamp(1, 5);
        final itemWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in _items)
              SizedBox(
                width: itemWidth,
                child: SelloStatCard(
                  label: item.label,
                  value: item.value,
                  icon: item.icon,
                  tone: item.tone,
                  trendLabel: item.trend,
                  trendPositive: item.up,
                  sparkPoints: item.spark,
                  onTap: item.route == null
                      ? null
                      : () => context.go(item.route!),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KpiSpec {
  const _KpiSpec({
    required this.label,
    required this.value,
    required this.trend,
    required this.up,
    required this.icon,
    this.tone,
    required this.spark,
    required this.route,
  });

  final String label;
  final String value;
  final String trend;
  final bool up;
  final IconData icon;
  final Color? tone;
  final List<double> spark;
  final String? route;
}

// ─── Performance ───────────────────────────────────────────────────────────

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.range,
    required this.metric,
    required this.onRange,
    required this.onMetric,
  });

  final String range;
  final String metric;
  final ValueChanged<String> onRange;
  final ValueChanged<String> onMetric;

  @override
  Widget build(BuildContext context) {
    final figure = switch (metric) {
      'orders' => ('1,248', '6.1% vs last month', AppColors.ops),
      'collections' => ('Rs 612K', '2.1% vs last month', AppColors.finance),
      _ => ('Rs 4.82M', '12.4% vs last month', context.brandAccent),
    };

    return SelloCard(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Equal-height / bounded parents: fill and grow the chart.
          // Unbounded (stacked / first measure pass): fixed chart height.
          final expandChart = constraints.hasBoundedHeight &&
              constraints.maxHeight < double.infinity;

          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BUSINESS PERFORMANCE',
                          style: AppTypography.heroEyebrow,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              figure.$1,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 34,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.03 * 34,
                                height: 1,
                                color: AppColors.textPrimary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successContainer,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.north_east_rounded,
                                    size: 10,
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    figure.$2,
                                    style: TextStyle(
                                      fontFamily: AppTypography.fontFamily,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Segmented(
                    values: const ['today', 'week', 'month', 'year'],
                    labels: const ['Today', 'Week', 'Month', 'Year'],
                    selected: range,
                    onChanged: onRange,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: 'Revenue',
                    color: context.brandAccent,
                    selected: metric == 'revenue',
                    onTap: () => onMetric('revenue'),
                  ),
                  _MetricChip(
                    label: 'Orders',
                    color: AppColors.ops,
                    selected: metric == 'orders',
                    onTap: () => onMetric('orders'),
                  ),
                  _MetricChip(
                    label: 'Collections',
                    color: AppColors.finance,
                    selected: metric == 'collections',
                    onTap: () => onMetric('collections'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (expandChart)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _AnimatedPerformanceChart(
                          color: figure.$3,
                          seed: Object.hash(metric, range),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final label in ['W1', 'W2', 'W3', 'W4', 'W5'])
                            Text(
                              label,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textFaint,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: _AnimatedPerformanceChart(
                    color: figure.$3,
                    seed: Object.hash(metric, range),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final label in ['W1', 'W2', 'W3', 'W4', 'W5'])
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textFaint,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );

          return expandChart ? SizedBox.expand(child: column) : column;
        },
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xE6F3EFFC),
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.outlineSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < values.length; i++)
            _SegmentedTab(
              label: labels[i],
              selected: selected == values[i],
              onTap: () => onChanged(values[i]),
            ),
        ],
      ),
    );
  }
}

class _SegmentedTab extends StatefulWidget {
  const _SegmentedTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SegmentedTab> createState() => _SegmentedTabState();
}

class _SegmentedTabState extends State<_SegmentedTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final showHover = _hovered && !selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : showHover
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected ? AppShadows.level1 : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              widget.label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.brandIndigo
                    : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HoverFill(
      selected: selected,
      selectedColor: context.brandAccentContainer.withValues(alpha: 0.55),
      hoverColor: context.brandAccent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected
                ? context.brandMid.withValues(alpha: 0.7)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: context.brandAccent.withValues(alpha: 0.10),
                          blurRadius: 0,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.textSecondary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Instant hover fill — no fade, so only one item is highlighted at a time.
class _HoverFill extends StatefulWidget {
  const _HoverFill({
    required this.child,
    required this.onTap,
    required this.borderRadius,
    this.selected = false,
    this.selectedColor,
    this.hoverColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final bool selected;
  final Color? selectedColor;
  final Color? hoverColor;

  @override
  State<_HoverFill> createState() => _HoverFillState();
}

class _HoverFillState extends State<_HoverFill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.selected
        ? (widget.selectedColor ?? Colors.transparent)
        : (_hovered
            ? (widget.hoverColor ?? AppColors.veil)
            : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Draws the performance line with a smooth left→right intro on filter change.
class _AnimatedPerformanceChart extends StatefulWidget {
  const _AnimatedPerformanceChart({
    required this.color,
    required this.seed,
  });

  final Color color;
  final int seed;

  @override
  State<_AnimatedPerformanceChart> createState() =>
      _AnimatedPerformanceChartState();
}

class _AnimatedPerformanceChartState extends State<_AnimatedPerformanceChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.22, 0.61, 0.36, 1),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedPerformanceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed || oldWidget.color != widget.color) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        return CustomPaint(
          painter: _ChartPainter(
            color: widget.color,
            seed: widget.seed,
            progress: _progress.value,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.color,
    required this.seed,
    this.progress = 1,
  });

  final Color color;
  final int seed;
  final double progress;

  /// Soft halo under the last-point marker (HTML `--dot-halo`).
  Color get _halo => color.withValues(alpha: 0.14);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 4.0;
    final plot =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

    final gridPaint = Paint()
      ..color = const Color(0xFFF0ECFA)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final t = i / 3;
      final y = plot.top + t * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final t = progress.clamp(0.0, 1.0);
    if (t <= 0.001) return;

    final rnd = math.Random(seed);
    final raw =
        List<double>.generate(12, (_) => 0.25 + rnd.nextDouble() * 0.55);
    raw[raw.length - 1] = 0.18 + rnd.nextDouble() * 0.22;

    final pts = <Offset>[
      for (var i = 0; i < raw.length; i++)
        Offset(
          plot.left + plot.width * i / (raw.length - 1),
          plot.top + plot.height * raw[i],
        ),
    ];

    final fullPath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      fullPath.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    fullPath.lineTo(pts.last.dx, pts.last.dy);

    // Reveal the stroke left → right.
    final metrics = fullPath.computeMetrics().toList();
    final totalLen = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var remaining = totalLen * t;
    final drawn = Path();
    Offset? tip;
    for (final metric in metrics) {
      if (remaining <= 0) break;
      final take = math.min(metric.length, remaining);
      drawn.addPath(metric.extractPath(0, take), Offset.zero);
      tip = metric.getTangentForOffset(take)?.position;
      remaining -= take;
    }

    final topY = pts.map((p) => p.dy).reduce(math.min);
    final fillProgress = Curves.easeOut.transform(t);
    final fill = Path.from(drawn)
      ..lineTo((tip ?? pts.last).dx, plot.bottom)
      ..lineTo(pts.first.dx, plot.bottom)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28 * fillProgress),
            color.withValues(alpha: 0.08 * fillProgress),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromLTRB(plot.left, topY, plot.right, plot.bottom),
        ),
    );

    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // End marker blooms in near the finish of the draw.
    if (t > 0.86) {
      final bloom = Curves.easeOutCubic.transform(((t - 0.86) / 0.14).clamp(0.0, 1.0));
      final last = tip ?? pts.last;
      canvas.drawCircle(
        last,
        9 * bloom,
        Paint()..color = _halo.withValues(alpha: 0.14 * bloom),
      );
      canvas.drawCircle(
        last,
        7 * bloom,
        Paint()..color = Colors.white.withValues(alpha: bloom),
      );
      canvas.drawCircle(
        last,
        4.5 * bloom,
        Paint()..color = color.withValues(alpha: bloom),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.color != color ||
      oldDelegate.progress != progress;
}

// ─── Action Center (Sello Intelligence) ────────────────────────────────────

class _ActionCenterCard extends ConsumerWidget {
  const _ActionCenterCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intel = ref.watch(hubIntelligenceProvider);
    final role = ref.watch(currentSessionProvider)?.appRole ?? UserRole.owner;

    return intel.when(
      data: (snap) {
        final items = snap.insights;
        if (items.isEmpty) {
          return SelloDashboardCard(
            title: 'Sello Intelligence',
            countBadge: '0',
            action: SelloViewAllLink(
              onTap: () => context.go(RoutePaths.hubReports),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nothing needs your attention right now. Sello is keeping an '
                'eye on sales, stock, visits, and payments.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }

        return SelloDashboardCard(
          title: 'Sello Intelligence',
          countBadge: '${items.length}',
          action: SelloViewAllLink(
            onTap: () => context.go(RoutePaths.hubReports),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _ActionRow(
                  title: items[i].title,
                  subtitle: items[i].message,
                  cta: items[i].actionLabel,
                  tone: _toneFor(items[i].category),
                  soft: _softFor(items[i].category),
                  icon: _iconFor(items[i].category),
                  onTap: () => context.go(items[i].routeFor(role)),
                  showDivider: i < items.length - 1,
                ),
            ],
          ),
        );
      },
      loading: () => const SelloDashboardCard(
        title: 'Sello Intelligence',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (_, _) => SelloDashboardCard(
        title: 'Sello Intelligence',
        action: SelloViewAllLink(
          onTap: () => ref.invalidate(hubIntelligenceProvider),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Couldn\'t load these tips right now. Tap View all to try again '
            'from Reports.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  static Color _toneFor(IntelligenceCategory category) => switch (category) {
        IntelligenceCategory.inventory => AppColors.finance,
        IntelligenceCategory.payments => AppColors.attention,
        IntelligenceCategory.schedules ||
        IntelligenceCategory.customerVisits =>
          AppColors.ops,
        IntelligenceCategory.orders => AppColors.primary,
        IntelligenceCategory.customers => AppColors.attention,
        IntelligenceCategory.sales ||
        IntelligenceCategory.forecasts ||
        IntelligenceCategory.recommendations =>
          AppColors.primary,
        IntelligenceCategory.salesRepresentatives => AppColors.ops,
      };

  static Color _softFor(IntelligenceCategory category) => switch (category) {
        IntelligenceCategory.inventory => AppColors.financeSoft,
        IntelligenceCategory.payments => AppColors.attentionSoft,
        IntelligenceCategory.schedules ||
        IntelligenceCategory.customerVisits =>
          AppColors.opsSoft,
        IntelligenceCategory.orders => AppColors.primaryContainer,
        IntelligenceCategory.customers => AppColors.attentionSoft,
        IntelligenceCategory.sales ||
        IntelligenceCategory.forecasts ||
        IntelligenceCategory.recommendations =>
          AppColors.primaryContainer,
        IntelligenceCategory.salesRepresentatives => AppColors.opsSoft,
      };

  static IconData _iconFor(IntelligenceCategory category) => switch (category) {
        IntelligenceCategory.inventory => Icons.inventory_2_outlined,
        IntelligenceCategory.payments => Icons.account_balance_wallet_outlined,
        IntelligenceCategory.schedules => Icons.event_busy_outlined,
        IntelligenceCategory.customerVisits => Icons.place_outlined,
        IntelligenceCategory.orders => Icons.receipt_long_outlined,
        IntelligenceCategory.customers => Icons.person_outline_rounded,
        IntelligenceCategory.sales => Icons.trending_up_rounded,
        IntelligenceCategory.salesRepresentatives => Icons.groups_outlined,
        IntelligenceCategory.forecasts => Icons.auto_graph_outlined,
        IntelligenceCategory.recommendations => Icons.auto_awesome_outlined,
      };
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.tone,
    required this.soft,
    required this.icon,
    required this.onTap,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final String cta;
  final Color tone;
  final Color soft;
  final IconData icon;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _ctaHovered = false;

  @override
  Widget build(BuildContext context) {
    return SelloListRow(
      showDivider: widget.showDivider,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 16, color: widget.tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.01 * 13.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            onEnter: (_) => setState(() => _ctaHovered = true),
            onExit: (_) => setState(() => _ctaHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _ctaHovered
                      ? context.brandAccent
                      : context.brandAccentContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.cta,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _ctaHovered ? Colors.white : context.brandAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Activity ──────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'New order #SL-4821 created',
        'Perera Hardware · Rs 28,400',
        '08:41',
        AppColors.ops,
        AppColors.opsSoft,
        Icons.upload_outlined,
      ),
      (
        'Payment received',
        'Rs 112,000 from Nimal Traders',
        '08:22',
        AppColors.success,
        AppColors.successContainer,
        Icons.credit_card_outlined,
      ),
      (
        'Inventory updated',
        '32 units of "Steel Hinges 4in" added',
        '07:58',
        AppColors.inventory,
        AppColors.inventorySoft,
        Icons.inventory_2_outlined,
      ),
      (
        'Customer credit reviewed',
        'Sunrise Traders · limit adjusted',
        '07:30',
        context.brandAccent,
        context.brandAccentContainer,
        Icons.person_outline,
      ),
    ];

    return SelloDashboardCard(
      title: 'Business Activity',
      action: SelloViewAllLink(onTap: () => context.go(RoutePaths.hubOrders)),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 33,
                        height: 33,
                        decoration: BoxDecoration(
                          color: items[i].$5,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.white,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          items[i].$6,
                          size: 14,
                          color: items[i].$4,
                        ),
                      ),
                      if (i < items.length - 1)
                        Expanded(
                          child: Container(
                            width: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: AppColors.outline,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i < items.length - 1 ? 20 : 0,
                        top: 2,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  items[i].$1,
                                  style: TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  items[i].$2,
                                  style: TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            items[i].$3,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 10.5,
                              color: AppColors.textFaint,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Inventory ─────────────────────────────────────────────────────────────

final _hubInventoryHealthProvider =
    FutureProvider.autoDispose<InventoryDashboardStats>((ref) async {
  final branchId = ref.watch(currentSessionProvider)?.branch?.id;
  return ref
      .read(inventoryRepositoryProvider)
      .fetchDashboardStats(branchId: branchId);
});

class _InventoryHealthCard extends ConsumerWidget {
  const _InventoryHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_hubInventoryHealthProvider);
    final stats = async.valueOrNull;
    final attention = (stats?.lowStock ?? 0) + (stats?.outOfStock ?? 0);
    final rows = [
      (
        'Total Products',
        '${stats?.totalItems ?? '—'}',
        AppColors.inventory,
        AppColors.inventorySoft,
        Icons.check_rounded,
      ),
      (
        'Low Stock',
        '${stats?.lowStock ?? '—'}',
        AppColors.finance,
        AppColors.financeSoft,
        Icons.inventory_2_outlined,
      ),
      (
        'Out of Stock',
        '${stats?.outOfStock ?? '—'}',
        AppColors.attention,
        AppColors.attentionSoft,
        Icons.error_outline,
      ),
      (
        'Updated (7d)',
        '${stats?.recentlyUpdated ?? '—'}',
        AppColors.ops,
        AppColors.opsSoft,
        Icons.update_rounded,
      ),
    ];

    final healthyRatio = stats == null || stats.totalItems == 0
        ? 0.82
        : ((stats.totalItems - stats.lowStock - stats.outOfStock) /
                stats.totalItems)
            .clamp(0.0, 1.0);

    return SelloCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      onTap: () => context.go(RoutePaths.hubInventory),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Inventory Health',
                  style: AppTypography.sectionTitle,
                ),
              ),
              if (async.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 420;
              final list = Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: row.$4,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(row.$5, size: 13, color: row.$3),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              row.$1,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            row.$2,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: row.$3 == AppColors.inventory
                                  ? AppColors.textPrimary
                                  : row.$3,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );

              if (narrow) {
                return Column(
                  children: [
                    _InventoryGauge(ratio: healthyRatio),
                    const SizedBox(height: 16),
                    list,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _InventoryGauge(ratio: healthyRatio),
                  const SizedBox(width: 36),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: SizedBox(
                      height: _InventoryGauge.gaugeHeight,
                      child: list,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.outlineSubtle),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
              children: [
                TextSpan(
                  text: attention == 0
                      ? 'Inventory looks healthy. '
                      : attention == 1
                          ? '1 product needs attention. '
                          : '$attention products need attention. ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const TextSpan(
                  text: 'Open Inventory to adjust stock or review movements.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InventoryGauge extends StatelessWidget {
  const _InventoryGauge({this.ratio = 0.80});

  final double ratio;

  static const double gaugeHeight = 214;
  static const double _w = 224;
  static const double _gaugeH = gaugeHeight;
  /// Must match [_GaugePainter] arc center (`height * 0.52`).
  static const double _arcCenterY = _gaugeH * 0.52;
  static const double _pctSize = 44;

  @override
  Widget build(BuildContext context) {
    final pct = (ratio * 100).round();
    return SizedBox(
      width: _w,
      height: _gaugeH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GaugePainter(progress: ratio),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: _arcCenterY - _pctSize / 2,
            height: _pctSize,
            child: Center(
              child: Text(
                '$pct%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: _pctSize,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.03 * _pctSize,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.52);
    final radius = size.width * 0.42;
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = const Color(0xFFEEF1F8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawArc(
      rect,
      start,
      sweep * progress,
      false,
      Paint()
        ..shader = AppGradients.gauge.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─── Ranked lists ──────────────────────────────────────────────────────────

class _TopCustomersCard extends StatelessWidget {
  const _TopCustomersCard();

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('1', 'PH', 'Perera Hardware', 'Last purchase: today', 'Rs 482K',
          'Outstanding Rs 0', false, const Color(0xFF8B72F5),
          const Color(0xFF4B32C3)),
      ('2', 'NT', 'Nimal Traders', 'Last purchase: yesterday', 'Rs 361K',
          'Outstanding Rs 12K', true, const Color(0xFFD9A244),
          const Color(0xFFB97A18)),
      ('3', 'CF', 'Colombo Fresh Mart', 'Last purchase: 2 days ago', 'Rs 298K',
          'Outstanding Rs 0', false, const Color(0xFF22B183),
          const Color(0xFF137C54)),
      ('4', 'SG', 'Sunrise Traders', 'Last purchase: 3 days ago', 'Rs 214K',
          'Outstanding Rs 42K', true, const Color(0xFFE5686C),
          const Color(0xFFB23438)),
      ('5', 'RS', 'Ranaweera Stores', 'Last purchase: 4 days ago', 'Rs 176K',
          'Outstanding Rs 0', false, const Color(0xFF6C4FF2),
          const Color(0xFF2C1D7A)),
    ];

    return SelloDashboardCard(
      title: 'Top Customers',
      action:
          SelloViewAllLink(onTap: () => context.go(RoutePaths.hubCustomers)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _RankCustomerRow(
              rank: rows[i].$1,
              initials: rows[i].$2,
              name: rows[i].$3,
              subtitle: rows[i].$4,
              amount: rows[i].$5,
              outstanding: rows[i].$6,
              owed: rows[i].$7,
              avatarFrom: rows[i].$8,
              avatarTo: rows[i].$9,
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RankCustomerRow extends StatelessWidget {
  const _RankCustomerRow({
    required this.rank,
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.amount,
    required this.outstanding,
    required this.owed,
    required this.avatarFrom,
    required this.avatarTo,
    this.showDivider = true,
  });

  final String rank;
  final String initials;
  final String name;
  final String subtitle;
  final String amount;
  final String outstanding;
  final bool owed;
  final Color avatarFrom;
  final Color avatarTo;
  final bool showDivider;

  Color get _medalBg {
    return switch (rank) {
      '1' => const Color(0xFFF6D56A),
      '2' => const Color(0xFFE8ECF2),
      '3' => const Color(0xFFF0D4B8),
      _ => AppColors.surfaceMuted,
    };
  }

  Color get _medalFg {
    return switch (rank) {
      '1' => const Color(0xFF5C4200),
      '2' => const Color(0xFF3F4652),
      '3' => const Color(0xFF7A5535),
      _ => AppColors.textFaint,
    };
  }

  @override
  Widget build(BuildContext context) {
    final rankN = int.parse(rank);
    return SelloListRow(
      showDivider: showDivider,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: rankN <= 3
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _medalBg,
                        Color.lerp(_medalBg, Colors.black, 0.12)!,
                      ],
                    )
                  : null,
              color: rankN > 3 ? _medalBg : null,
              borderRadius: BorderRadius.circular(7),
              border: rankN > 3
                  ? Border.all(color: AppColors.outlineSubtle)
                  : null,
            ),
            child: Text(
              rank,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: _medalFg,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [avatarFrom, avatarTo],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                outstanding,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 10,
                  color: owed ? AppColors.finance : AppColors.textFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BestSellersCard extends StatelessWidget {
  const _BestSellersCard();

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('1', '🔩', 'Steel Hinges 4in', '842 units sold', context.brandAccent,
          const [0.2, 0.35, 0.3, 0.55, 0.5, 0.85]),
      ('2', '🧴', 'Industrial Cleaner 5L', '611 units sold', AppColors.success,
          const [0.55, 0.45, 0.65, 0.5, 0.75, 0.6]),
      ('3', '🔧', 'Adjustable Wrench Set', '498 units sold', AppColors.finance,
          const [0.4, 0.35, 0.55, 0.45, 0.6, 0.55]),
      ('4', '🪛', 'Precision Screwdriver Kit', '402 units sold',
          AppColors.attention, const [0.7, 0.55, 0.6, 0.4, 0.45, 0.3]),
    ];

    return SelloDashboardCard(
      title: 'Best Sellers',
      action:
          SelloViewAllLink(onTap: () => context.go(RoutePaths.hubProducts)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _BestSellerRow(
              rank: rows[i].$1,
              emoji: rows[i].$2,
              name: rows[i].$3,
              subtitle: rows[i].$4,
              sparkColor: rows[i].$5,
              spark: rows[i].$6,
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _BestSellerRow extends StatelessWidget {
  const _BestSellerRow({
    required this.rank,
    required this.emoji,
    required this.name,
    required this.subtitle,
    required this.sparkColor,
    required this.spark,
    this.showDivider = true,
  });

  final String rank;
  final String emoji;
  final String name;
  final String subtitle;
  final Color sparkColor;
  final List<double> spark;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return SelloListRow(
      showDivider: showDivider,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.outlineSubtle),
            ),
            child: Text(
              rank,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.outlineSubtle),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 58,
            height: 24,
            child: CustomPaint(
              painter: _MiniTrendPainter(
                points: spark,
                color: sparkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTrendPainter extends CustomPainter {
  _MiniTrendPainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * (1 - points[i].clamp(0.05, 0.95));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniTrendPainter oldDelegate) => true;
}

// ─── Insights ──────────────────────────────────────────────────────────────

class _InsightsSection extends StatelessWidget {
  const _InsightsSection();

  @override
  Widget build(BuildContext context) {
    final stack = context.screenWidth < 1280;

    final head = Row(
      children: [
        Text(
          'Business Insights',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.02 * 18,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        SelloViewAllLink(label: 'Ask Jarvis', onTap: () {}),
      ],
    );

    final hero = _InsightCard(
      badge: 'Growth',
      badgeIcon: Icons.north_east_rounded,
      tone: context.brandAccent,
      soft: context.brandAccentContainer,
      body:
          'Revenue is up 12% compared to last month, led by stronger sales at the Colombo branch.',
      cta: 'View revenue breakdown',
      onTap: () => context.go(RoutePaths.hubReports),
      large: true,
    );

    final cards = [
      _InsightCard(
        badge: 'Pattern',
        badgeIcon: Icons.add_circle_outline,
        tone: AppColors.ops,
        soft: AppColors.opsSoft,
        body:
            'Customers who buy Steel Hinges 4in also purchase Industrial Cleaner 5L 61% of the time.',
        cta: 'Bundle these products',
        onTap: () => context.go(RoutePaths.hubProducts),
      ),
      _InsightCard(
        badge: 'Watch',
        badgeIcon: Icons.warning_amber_rounded,
        tone: AppColors.finance,
        soft: AppColors.financeSoft,
        body:
            'Supplier deliveries for hardware stock are running 2 days behind schedule this week.',
        cta: 'Track deliveries',
        onTap: () => context.go(RoutePaths.hubSchedule),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        const SizedBox(height: 18),
        if (stack)
          Column(
            children: [
              hero,
              const SizedBox(height: AppSpacing.gap),
              cards[0],
              const SizedBox(height: AppSpacing.gap),
              cards[1],
            ],
          )
        else
          // HTML: grid-template-columns: 1.32fr 1fr 1fr
          SelloEqualHeightRow(
            flexes: const [132, 100, 100],
            children: [hero, cards[0], cards[1]],
          ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.badge,
    required this.badgeIcon,
    required this.tone,
    required this.soft,
    required this.body,
    required this.cta,
    required this.onTap,
    this.large = false,
  });

  final String badge;
  final IconData badgeIcon;
  final Color tone;
  final Color soft;
  final String body;
  final String cta;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      borderRadius: BorderRadius.circular(
        large ? AppRadius.xl : AppRadius.card,
      ),
      padding: EdgeInsets.all(large ? 26 : 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stretch = constraints.hasBoundedHeight &&
              constraints.maxHeight < double.infinity;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: tone),
                    const SizedBox(width: 6),
                    Text(
                      badge,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: tone,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                body,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (stretch) const Spacer() else const SizedBox(height: 16),
              SelloViewAllLink(label: cta, onTap: onTap),
            ],
          );
        },
      ),
    );
  }
}
