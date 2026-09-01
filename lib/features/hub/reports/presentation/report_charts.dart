import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/report_models.dart';

/// Lightweight bar chart — no chart package dependency.
class ReportBarChart extends StatelessWidget {
  const ReportBarChart({
    super.key,
    required this.points,
    this.height = 160,
  });

  final List<ReportTrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
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
      child: CustomPaint(
        painter: _BarPainter(points: points, color: AppColors.ops),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.points, required this.color});

  final List<ReportTrendPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final maxSales = points.fold<num>(0, (m, p) => p.sales > m ? p.sales : m);
    final barCount = points.length;
    if (barCount == 0) return;

    final gap = size.width / (barCount * 3.2);
    final barWidth = (size.width - gap * (barCount + 1)) / barCount;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final baseline = Paint()
      ..color = AppColors.outlinePanel
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    for (var i = 0; i < barCount; i++) {
      final value = points[i].sales;
      final h = maxSales <= 0
          ? 0.0
          : (value / maxSales) * (size.height - 8);
      final x = gap + i * (barWidth + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h - 1, barWidth, h),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) =>
      oldDelegate.points != points;
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
                    value: maxValue <= 0 ? 0 : (item.value / maxValue).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceMuted,
                    color: context.brandAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 88,
                child: Text(
                  valueLabel(item),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
