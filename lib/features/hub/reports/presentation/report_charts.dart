import 'package:flutter/material.dart';
import 'package:sello/core/responsive/responsive_layout.dart';
import 'package:sello/core/theme/theme.dart';
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

        return SizedBox(
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
