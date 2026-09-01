import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sello/core/theme/theme.dart';

/// Simple ink signature pad — future: name, timestamp, GPS co-evidence.
class SelloSignaturePad extends StatefulWidget {
  const SelloSignaturePad({
    super.key,
    required this.onSigned,
  });

  final VoidCallback onSigned;

  @override
  State<SelloSignaturePad> createState() => SelloSignaturePadState();
}

class SelloSignaturePadState extends State<SelloSignaturePad> {
  final _points = <Offset?>[];
  final _boundaryKey = GlobalKey();

  void clear() => setState(() => _points.clear());

  bool get hasInk => _points.any((p) => p != null);

  Future<ui.Image?> captureImage() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    return boundary.toImage(pixelRatio: 2);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlinePanel),
        ),
        child: GestureDetector(
          onPanStart: (details) {
            setState(() => _points.add(details.localPosition));
            widget.onSigned();
          },
          onPanUpdate: (details) {
            setState(() => _points.add(details.localPosition));
          },
          onPanEnd: (_) => setState(() => _points.add(null)),
          child: CustomPaint(
            painter: _SignaturePainter(_points),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textPrimary
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
