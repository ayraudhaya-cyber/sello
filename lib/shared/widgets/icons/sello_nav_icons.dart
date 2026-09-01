import 'package:flutter/material.dart';

/// Thin stroke glyphs for Hub sidebar — lighter than Material Icons.
enum SelloNavGlyph {
  dashboard,
  reports,
  orders,
  inventory,
  products,
  customers,
  payments,
  schedule,
  employees,
  attendance,
}

class SelloNavIcon extends StatelessWidget {
  const SelloNavIcon({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 17,
    this.selected = false,
  });

  final SelloNavGlyph glyph;
  final Color color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _NavIconPainter(
        glyph: glyph,
        color: color,
        // Slightly thinner than HTML's ~1.9–2.1 at 17px.
        strokeWidth: selected ? 1.55 : 1.4,
      ),
    );
  }
}

class _NavIconPainter extends CustomPainter {
  const _NavIconPainter({
    required this.glyph,
    required this.color,
    required this.strokeWidth,
  });

  final SelloNavGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final s = size.width / 24;
    canvas.scale(s);

    switch (glyph) {
      case SelloNavGlyph.dashboard:
        _dashboard(canvas, paint);
      case SelloNavGlyph.reports:
        _reports(canvas, paint);
      case SelloNavGlyph.orders:
        _orders(canvas, paint);
      case SelloNavGlyph.inventory:
        _box(canvas, paint);
      case SelloNavGlyph.products:
        _tag(canvas, paint);
      case SelloNavGlyph.customers:
        _person(canvas, paint);
      case SelloNavGlyph.payments:
        _card(canvas, paint);
      case SelloNavGlyph.schedule:
        _calendar(canvas, paint);
      case SelloNavGlyph.employees:
        _people(canvas, paint);
      case SelloNavGlyph.attendance:
        _clock(canvas, paint);
    }
  }

  void _dashboard(Canvas c, Paint p) {
    // Four simple tiles — no heavy grid fill.
    final r = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.5, 3.5, 7, 7),
      const Radius.circular(1.5),
    );
    c.drawRRect(r, p);
    c.drawRRect(r.shift(const Offset(10, 0)), p);
    c.drawRRect(r.shift(const Offset(0, 10)), p);
    c.drawRRect(r.shift(const Offset(10, 10)), p);
  }

  void _reports(Canvas c, Paint p) {
    // Minimal trend chart.
    c.drawLine(const Offset(4, 19), const Offset(4, 5), p);
    c.drawLine(const Offset(4, 19), const Offset(20, 19), p);
    final path = Path()
      ..moveTo(7, 14)
      ..lineTo(11, 10)
      ..lineTo(14, 12)
      ..lineTo(19, 6);
    c.drawPath(path, p);
  }

  void _orders(Canvas c, Paint p) {
    // Simple cart outline.
    c.drawCircle(const Offset(9, 20), 1.1, p);
    c.drawCircle(const Offset(17, 20), 1.1, p);
    final path = Path()
      ..moveTo(3.5, 4)
      ..lineTo(5.5, 4)
      ..lineTo(7.2, 15)
      ..lineTo(17.5, 15)
      ..lineTo(19.5, 7.5)
      ..lineTo(6.5, 7.5);
    c.drawPath(path, p);
  }

  void _box(Canvas c, Paint p) {
    // Open box — lid as a single line.
    final body = Path()
      ..moveTo(4, 9)
      ..lineTo(4, 19)
      ..lineTo(20, 19)
      ..lineTo(20, 9)
      ..lineTo(12, 5)
      ..close();
    c.drawPath(body, p);
    c.drawLine(const Offset(4, 9), const Offset(20, 9), p);
    c.drawLine(const Offset(12, 5), const Offset(12, 9), p);
  }

  void _tag(Canvas c, Paint p) {
    // Price-tag shape for products.
    final path = Path()
      ..moveTo(3.5, 11)
      ..lineTo(12, 3.5)
      ..lineTo(20.5, 12)
      ..lineTo(12, 20.5)
      ..close();
    c.drawPath(path, p);
    c.drawCircle(const Offset(8.2, 8.2), 1.15, p);
  }

  void _person(Canvas c, Paint p) {
    c.drawCircle(const Offset(12, 8), 3.2, p);
    final body = Path()
      ..moveTo(5.5, 19.5)
      ..cubicTo(5.5, 15.2, 8.2, 13, 12, 13)
      ..cubicTo(15.8, 13, 18.5, 15.2, 18.5, 19.5);
    c.drawPath(body, p);
  }

  void _card(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 6, 18, 12),
        const Radius.circular(2),
      ),
      p,
    );
    c.drawLine(const Offset(3, 10.5), const Offset(21, 10.5), p);
  }

  void _calendar(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 5, 16, 15),
        const Radius.circular(2),
      ),
      p,
    );
    c.drawLine(const Offset(4, 10), const Offset(20, 10), p);
    c.drawLine(const Offset(9, 3.5), const Offset(9, 6.5), p);
    c.drawLine(const Offset(15, 3.5), const Offset(15, 6.5), p);
  }

  void _people(Canvas c, Paint p) {
    // Two figures, front + back offset.
    c.drawCircle(const Offset(9, 8), 2.8, p);
    final front = Path()
      ..moveTo(3.5, 19)
      ..cubicTo(3.5, 15.2, 5.8, 13.2, 9, 13.2)
      ..cubicTo(12.2, 13.2, 14.5, 15.2, 14.5, 19);
    c.drawPath(front, p);

    c.drawCircle(const Offset(16.5, 8.5), 2.4, p);
    final back = Path()
      ..moveTo(14.8, 19)
      ..cubicTo(15.2, 16, 16.2, 14.2, 18.2, 13.8)
      ..cubicTo(20.4, 14.2, 21.2, 16.2, 21.2, 19);
    c.drawPath(back, p);
  }

  void _clock(Canvas c, Paint p) {
    c.drawCircle(const Offset(12, 12), 8, p);
    c.drawLine(const Offset(12, 8), const Offset(12, 12.5), p);
    c.drawLine(const Offset(12, 12.5), const Offset(15.5, 14.5), p);
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
