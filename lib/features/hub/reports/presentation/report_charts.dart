import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive_layout.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Lightweight bar chart — no chart package dependency.
class ReportBarChart extends StatefulWidget {
  const ReportBarChart({
    super.key,
    required this.points,
    this.height,
    this.currencySymbol,
  });

  final List<ReportTrendPoint> points;
  final double? height;
  final String? currencySymbol;

  @override
  State<ReportBarChart> createState() => _ReportBarChartState();
}

class _ReportBarChartState extends State<ReportBarChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            widget.height ?? ResponsiveLayout.chartHeight(constraints.maxWidth);
        final points = widget.points;
        if (points.isEmpty) {
          return SizedBox(
            height: height,
            child: const Center(
              child: Text(
                'No sales in this period yet.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: LayoutBuilder(
                builder: (context, inner) {
                  final size = Size(inner.maxWidth, height);
                  final bars = _barRects(size, points);
                  final hover = _hover;
                  return MouseRegion(
                    onExit: (_) {
                      if (_hover != null) setState(() => _hover = null);
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: size,
                          painter: _BarPainter(
                            points: points,
                            color: AppColors.ops,
                            highlighted: hover,
                          ),
                        ),
                        for (var i = 0; i < bars.length; i++)
                          Positioned(
                            left: i == 0
                                ? 0
                                : (bars[i - 1].right + bars[i].left) / 2,
                            width:
                                (i == bars.length - 1
                                    ? size.width
                                    : (bars[i].right + bars[i + 1].left) / 2) -
                                (i == 0
                                    ? 0
                                    : (bars[i - 1].right + bars[i].left) / 2),
                            top: 0,
                            bottom: 0,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.precise,
                              onEnter: (_) => setState(() => _hover = i),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        if (hover != null && hover < points.length)
                          _TrendTooltip(
                            point: points[hover],
                            bar: bars[hover],
                            chartWidth: size.width,
                            currencySymbol: widget.currencySymbol,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, inner) {
                return _TrendAxis(
                  width: inner.maxWidth,
                  plotHeight: height,
                  points: points,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _TrendTooltip extends StatelessWidget {
  const _TrendTooltip({
    required this.point,
    required this.bar,
    required this.chartWidth,
    required this.currencySymbol,
  });

  final ReportTrendPoint point;
  final Rect bar;
  final double chartWidth;
  final String? currencySymbol;

  @override
  Widget build(BuildContext context) {
    const width = 156.0;
    final left = (bar.center.dx - width / 2).clamp(
      0.0,
      (chartWidth - width).clamp(0.0, double.infinity),
    );
    final above = bar.top - 58;
    final top = above >= 4 ? above : 4.0;
    final orderLabel = point.orders == 1 ? '1 order' : '${point.orders} orders';

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.outlinePanel),
            boxShadow: AppShadows.panel,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  SelloFormatters.date(point.day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  SelloFormatters.currency(point.sales, symbol: currencySymbol),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  orderLabel,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<Rect> _barRects(Size size, List<ReportTrendPoint> points) {
  final maxSales = points.fold<num>(0, (m, p) => p.sales > m ? p.sales : m);
  final barCount = points.length;
  if (barCount == 0) return const [];

  final gap = size.width / (barCount * 3.2);
  final barWidth = (size.width - gap * (barCount + 1)) / barCount;
  return [
    for (var i = 0; i < barCount; i++)
      () {
        final value = points[i].sales;
        final h = maxSales <= 0 ? 0.0 : (value / maxSales) * (size.height - 8);
        final x = gap + i * (barWidth + gap);
        return Rect.fromLTWH(x, size.height - h - 1, barWidth, h);
      }(),
  ];
}

class _TrendAxis extends StatelessWidget {
  const _TrendAxis({
    required this.width,
    required this.plotHeight,
    required this.points,
  });

  final double width;
  final double plotHeight;
  final List<ReportTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (!width.isFinite || width <= 0 || points.isEmpty) {
      return const SizedBox(height: 16);
    }
    final bars = _barRects(Size(width, plotHeight), points);
    final indexes = _axisIndexes(points.length, width);
    return SizedBox(
      height: 16,
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final index in indexes)
            Positioned(
              left: (bars[index].center.dx - 28).clamp(0.0, math.max(0, width - 56)),
              width: 56,
              top: 0,
              child: Text(
                _axisLabel(points[index].day, points.length),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _axisLabel(DateTime day, int count) {
  final local = day.toLocal();
  if (count <= 8) return '${_weekdays[local.weekday - 1]} ${local.day}';
  if (count <= 16) return '${local.day} ${_months[local.month - 1]}';
  return '${local.day}';
}

List<int> _axisIndexes(int count, double width) {
  if (count <= 0) return const [];
  const minGap = 56.0;
  final maxLabels = math.max(2, (width / minGap).floor());
  if (count <= maxLabels) return [for (var i = 0; i < count; i++) i];
  final step = (count - 1) / (maxLabels - 1);
  final indexes = <int>{};
  for (var i = 0; i < maxLabels; i++) {
    indexes.add((i * step).round().clamp(0, count - 1));
  }
  final sorted = indexes.toList()..sort();
  return sorted;
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.points, required this.color, this.highlighted});

  final List<ReportTrendPoint> points;
  final Color color;
  final int? highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = _barRects(size, points);
    final baseline = Paint()
      ..color = AppColors.outlinePanel
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    for (var i = 0; i < bars.length; i++) {
      final paint = Paint()
        ..color = color.withValues(alpha: i == highlighted ? 1 : 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(bars[i], const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.highlighted != highlighted;
}

/// Horizontal comparison bars for ranked values.
class ReportComparisonBars extends StatelessWidget {
  const ReportComparisonBars({
    super.key,
    required this.items,
    required this.valueLabel,
    this.maxItems = 5,
  });

  final List<ReportNamedValue> items;
  final String Function(ReportNamedValue item) valueLabel;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(maxItems).toList();
    if (visible.isEmpty) {
      return const Text(
        'No data for this period.',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      );
    }

    final maxValue = visible.fold<num>(0, (m, i) => i.value > m ? i.value : m);

    return Column(
      children: [
        for (final item in visible) ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxValue <= 0
                        ? 0
                        : (item.value / maxValue).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceMuted,
                    color: context.brandAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      valueLabel(item),
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Order-status slices for the Reports donut.
///
/// Open, completed, and cancelled are the only segments. Payment state is
/// not an order status and is intentionally absent.
class OrderStatusDonutData {
  const OrderStatusDonutData({
    required this.open,
    required this.completed,
    required this.cancelled,
  });

  factory OrderStatusDonutData.fromCounts(OrderCounts counts) {
    return OrderStatusDonutData(
      open: counts.draft,
      completed: counts.completed,
      cancelled: counts.cancelled,
    );
  }

  final int open;
  final int completed;
  final int cancelled;

  int get total => open + completed + cancelled;

  bool get isEmpty => total <= 0;
}

class OrderStatusDonut extends StatelessWidget {
  const OrderStatusDonut({super.key, required this.data});

  final OrderStatusDonutData data;

  static const _size = 148.0;

  @override
  Widget build(BuildContext context) {
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusLegendRow(
          color: AppColors.success,
          label: 'Completed',
          count: data.completed,
        ),
        const SizedBox(height: 8),
        _StatusLegendRow(
          color: AppColors.warning,
          label: 'Open',
          count: data.open,
        ),
        const SizedBox(height: 8),
        _StatusLegendRow(
          color: AppColors.error,
          label: 'Cancelled',
          count: data.cancelled,
        ),
      ],
    );

    final donut = SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        painter: _OrderStatusDonutPainter(data: data),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${data.total}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Orders',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 280;
        if (stacked) {
          return Column(
            children: [
              donut,
              const SizedBox(height: 14),
              legend,
            ],
          );
        }
        return Row(
          children: [
            donut,
            const SizedBox(width: 16),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _StatusLegendRow extends StatelessWidget {
  const _StatusLegendRow({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _OrderStatusDonutPainter extends CustomPainter {
  const _OrderStatusDonutPainter({required this.data});

  final OrderStatusDonutData data;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.butt
      ..color = AppColors.outline;
    canvas.drawCircle(center, radius, track);
    if (data.total <= 0) return;

    final slices = <(int, Color)>[
      (data.completed, AppColors.success),
      (data.open, AppColors.warning),
      (data.cancelled, AppColors.error),
    ];
    var start = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.butt;
    for (final slice in slices) {
      if (slice.$1 <= 0) continue;
      final sweep = (slice.$1 / data.total) * math.pi * 2;
      paint.color = slice.$2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _OrderStatusDonutPainter oldDelegate) {
    return oldDelegate.data.open != data.open ||
        oldDelegate.data.completed != data.completed ||
        oldDelegate.data.cancelled != data.cancelled;
  }
}
