import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One family of miniature glass sculptures for the marketing feature icons.
///
/// Each mark is built from separate polygonal faces. Light comes from the
/// upper left, so top and left planes stay white and right and lower planes
/// fall through silver into translucent grey.
enum V2GlassIconKind {
  customers,
  payments,
  invoice,
  notifications,
  reporting,
  team,
  dashboard,
  phone,
  stock,
}

/// Cropped glass artwork for the six Core of Sello cards. Black pixels are
/// meant to drop out under [BlendMode.hardLight].
const v2GlassIconAssets = <V2GlassIconKind, String>{
  V2GlassIconKind.customers: 'assets/brand/sello_glass_customers.png',
  V2GlassIconKind.payments: 'assets/brand/sello_glass_payments.png',
  V2GlassIconKind.invoice: 'assets/brand/sello_glass_invoice.png',
  V2GlassIconKind.notifications: 'assets/brand/sello_glass_notifications.png',
  V2GlassIconKind.reporting: 'assets/brand/sello_glass_reporting.png',
  V2GlassIconKind.team: 'assets/brand/sello_glass_team.png',
};

/// Draws the glass artwork with hard light, using the image's own alpha so
/// transparent pixels leave the card untouched.
class V2HardLightIcon extends StatefulWidget {
  const V2HardLightIcon({super.key, required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  State<V2HardLightIcon> createState() => _V2HardLightIconState();
}

class _V2HardLightIconState extends State<V2HardLightIcon> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener(_onImage);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant V2HardLightIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) _resolve();
  }

  void _resolve() {
    final next = AssetImage(
      widget.asset,
    ).resolve(createLocalImageConfiguration(context));
    if (next.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = next;
    next.addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    setState(() => _info = info);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _HardLightIconPainter(_info?.image),
    );
  }
}

class _HardLightIconPainter extends CustomPainter {
  const _HardLightIconPainter(this.image);

  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.hardLight
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _HardLightIconPainter oldDelegate) =>
      oldDelegate.image != image;
}

class V2SoftFeatureIcon extends StatelessWidget {
  const V2SoftFeatureIcon({super.key, required this.kind, required this.size});

  final V2GlassIconKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SoftFeaturePainter(kind),
    );
  }
}

class _SoftFeaturePainter extends CustomPainter {
  const _SoftFeaturePainter(this.kind);

  final V2GlassIconKind kind;

  static const _white = Color(0xFFFFFFFF);
  static const _back = Color(0xFFF0E9FF);
  static const _ink = Color(0xFFC9B8FF);
  static const _inkDeep = Color(0xFFB7A4F6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    switch (kind) {
      case V2GlassIconKind.customers:
        _customers(canvas, s);
      case V2GlassIconKind.payments:
        _payments(canvas, s);
      case V2GlassIconKind.invoice:
        _invoice(canvas, s);
      case V2GlassIconKind.notifications:
        _notifications(canvas, s);
      case V2GlassIconKind.reporting:
        _reporting(canvas, s);
      case V2GlassIconKind.team:
        _team(canvas, s);
      case V2GlassIconKind.dashboard:
      case V2GlassIconKind.phone:
      case V2GlassIconKind.stock:
        break;
    }
  }

  void _shadow(Canvas canvas, RRect rect, double s) {
    canvas.drawRRect(
      rect.shift(Offset(0, s * 3)),
      Paint()
        ..color = const Color(0x33C9B8FF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 3.2),
    );
  }

  RRect _box(double x, double y, double w, double h, double r, double s) {
    return RRect.fromRectAndRadius(
      Rect.fromLTWH(x * s, y * s, w * s, h * s),
      Radius.circular(r * s),
    );
  }

  void _reporting(Canvas canvas, double s) {
    final back = _box(8, 30, 64, 46, 12, s);
    canvas.drawRRect(back, Paint()..color = _back);
    final front = _box(24, 14, 58, 60, 14, s);
    _shadow(canvas, front, s);
    canvas.drawRRect(front, Paint()..color = _white);
    final chart = Path()
      ..moveTo(36 * s, 56 * s)
      ..cubicTo(44 * s, 54 * s, 48 * s, 40 * s, 56 * s, 42 * s)
      ..cubicTo(62 * s, 44 * s, 66 * s, 30 * s, 74 * s, 26 * s);
    canvas.drawPath(
      chart,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * s
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(78 * s, 64 * s), 8 * s, Paint()..color = _ink);
    canvas.drawCircle(
      Offset(78 * s, 64 * s),
      3.4 * s,
      Paint()
        ..color = _white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s,
    );
  }

  void _payments(Canvas canvas, double s) {
    canvas.drawRRect(_box(10, 22, 58, 40, 12, s), Paint()..color = _back);
    final front = _box(18, 28, 64, 48, 14, s);
    _shadow(canvas, front, s);
    canvas.drawRRect(front, Paint()..color = _white);
    canvas.drawRRect(
      _box(28, 40, 28, 5, 3, s),
      Paint()..color = _ink,
    );
    canvas.drawRRect(
      _box(28, 50, 18, 5, 3, s),
      Paint()..color = _ink.withValues(alpha: 0.72),
    );
    canvas.drawCircle(Offset(70 * s, 64 * s), 9 * s, Paint()..color = _inkDeep);
    canvas.drawCircle(
      Offset(70 * s, 64 * s),
      4 * s,
      Paint()
        ..color = _white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s,
    );
  }

  void _invoice(Canvas canvas, double s) {
    canvas.drawRRect(_box(12, 20, 56, 62, 12, s), Paint()..color = _back);
    final front = _box(22, 12, 58, 70, 12, s);
    _shadow(canvas, front, s);
    canvas.drawRRect(front, Paint()..color = _white);
    for (final y in [28.0, 40.0, 52.0]) {
      canvas.drawRRect(
        _box(32, y, y == 52 ? 22 : 34, 5, 3, s),
        Paint()..color = _ink.withValues(alpha: y == 40 ? 0.7 : 1),
      );
    }
  }

  void _person(Canvas canvas, double s, double x, double y, double scale, Color color) {
    canvas.drawCircle(Offset(x * s, y * s), 7 * scale * s, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x * s, (y + 16 * scale) * s),
          width: 22 * scale * s,
          height: 14 * scale * s,
        ),
        Radius.circular(8 * scale * s),
      ),
      Paint()..color = color,
    );
  }

  void _customers(Canvas canvas, double s) {
    final plate = _box(10, 16, 80, 68, 18, s);
    _shadow(canvas, plate, s);
    canvas.drawRRect(plate, Paint()..color = _white);
    _person(canvas, s, 38, 40, 1, _ink.withValues(alpha: 0.62));
    _person(canvas, s, 58, 44, 1.15, _ink);
  }

  void _notifications(Canvas canvas, double s) {
    final bubble = _box(12, 14, 72, 48, 16, s);
    _shadow(canvas, bubble, s);
    canvas.drawRRect(bubble, Paint()..color = _white);
    final tail = Path()
      ..moveTo(28 * s, 58 * s)
      ..lineTo(26 * s, 78 * s)
      ..lineTo(46 * s, 58 * s)
      ..close();
    canvas.drawPath(tail, Paint()..color = _white);
    canvas.drawRRect(
      _box(24, 28, 36, 5, 3, s),
      Paint()..color = _ink,
    );
    canvas.drawRRect(
      _box(24, 40, 22, 5, 3, s),
      Paint()..color = _ink.withValues(alpha: 0.68),
    );
  }

  void _team(Canvas canvas, double s) {
    canvas.drawRRect(_box(8, 28, 52, 40, 12, s), Paint()..color = _inkDeep);
    final card = _box(28, 16, 58, 62, 14, s);
    _shadow(canvas, card, s);
    canvas.drawRRect(card, Paint()..color = _white);
    for (final row in [30.0, 44.0, 58.0]) {
      canvas.drawCircle(
        Offset(42 * s, (row + 2) * s),
        3.2 * s,
        Paint()..color = _ink,
      );
      canvas.drawRRect(
        _box(50, row, 24, 5, 3, s),
        Paint()..color = _ink.withValues(alpha: row == 44 ? 0.68 : 1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoftFeaturePainter oldDelegate) =>
      oldDelegate.kind != kind;
}

class V2GlassIcon extends StatelessWidget {
  const V2GlassIcon({super.key, required this.kind, required this.size});

  final V2GlassIconKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlassSculpturePainter(kind),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Face {
  const _Face(this.points, this.light, this.shade, {this.opacity = 0.92});

  /// Points in a 0–100 square.
  final List<Offset> points;
  final Color light;
  final Color shade;
  final double opacity;
}

class _GlassSculpturePainter extends CustomPainter {
  const _GlassSculpturePainter(this.kind);

  final V2GlassIconKind kind;

  static const _white = Color(0xFFFFFFFF);
  static const _mist = Color(0xFFE6E6EE);
  static const _silver = Color(0xFFC4C4D0);
  static const _steel = Color(0xFF8E8E9C);
  static const _slate = Color(0xFF5C5C6A);

  @override
  void paint(Canvas canvas, Size size) {
    final faces = switch (kind) {
      V2GlassIconKind.customers => _customers,
      V2GlassIconKind.payments => _payments,
      V2GlassIconKind.invoice => _invoice,
      V2GlassIconKind.notifications => _notifications,
      V2GlassIconKind.reporting => _reporting,
      V2GlassIconKind.team => _team,
      V2GlassIconKind.dashboard => _dashboard,
      V2GlassIconKind.phone => _phone,
      V2GlassIconKind.stock => _stock,
    };
    for (final face in faces) {
      _paintFace(canvas, size, face);
    }
  }

  bool get _lavender => switch (kind) {
    V2GlassIconKind.dashboard ||
    V2GlassIconKind.phone ||
    V2GlassIconKind.stock => false,
    _ => true,
  };

  Color _lavenderTone(Color color) {
    final luminance = color.computeLuminance();
    const highlight = Color(0xFFF8F3FF);
    const lit = Color(0xFFE6D0FF);
    const mid = Color(0xFFC890FF);
    const shade = Color(0xFFB06EF8);
    const deep = Color(0xFF8E56F0);
    if (luminance > 0.86) return highlight;
    if (luminance > 0.62) return lit;
    if (luminance > 0.32) return mid;
    if (luminance > 0.16) return shade;
    return deep;
  }

  void _paintFace(Canvas canvas, Size size, _Face face) {
    final path = Path()..addPolygon(
      [
        for (final point in face.points)
          Offset(point.dx / 100 * size.width, point.dy / 100 * size.height),
      ],
      true,
    );
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;
    final light = _lavender ? _lavenderTone(face.light) : face.light;
    final shade = _lavender ? _lavenderTone(face.shade) : face.shade;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            light.withValues(alpha: face.opacity),
            shade.withValues(alpha: face.opacity * 0.94),
          ],
        ).createShader(bounds),
    );
  }

  static const _customers = [
    _Face([
      Offset(38, 20),
      Offset(50, 6),
      Offset(50, 24),
    ], _white, _mist),
    _Face([
      Offset(50, 6),
      Offset(64, 20),
      Offset(50, 24),
    ], _mist, _silver, opacity: 0.78),
    _Face([
      Offset(38, 20),
      Offset(50, 24),
      Offset(48, 40),
      Offset(34, 32),
    ], _mist, _silver, opacity: 0.9),
    _Face([
      Offset(50, 24),
      Offset(64, 20),
      Offset(66, 34),
      Offset(52, 40),
    ], _silver, _steel, opacity: 0.72),
    _Face([
      Offset(30, 46),
      Offset(50, 40),
      Offset(70, 48),
      Offset(50, 54),
    ], _white, _mist),
    _Face([
      Offset(30, 46),
      Offset(50, 54),
      Offset(48, 86),
      Offset(28, 76),
    ], _mist, _silver, opacity: 0.9),
    _Face([
      Offset(50, 54),
      Offset(70, 48),
      Offset(72, 76),
      Offset(52, 86),
    ], _silver, _slate, opacity: 0.62),
  ];

  static const _payments = [
    _Face([
      Offset(16, 34),
      Offset(28, 22),
      Offset(84, 30),
      Offset(72, 42),
    ], _white, _mist),
    _Face([
      Offset(16, 34),
      Offset(46, 38),
      Offset(48, 76),
      Offset(18, 70),
    ], _white, _mist, opacity: 0.94),
    _Face([
      Offset(46, 38),
      Offset(72, 42),
      Offset(74, 80),
      Offset(48, 76),
    ], _silver, _steel, opacity: 0.7),
    _Face([
      Offset(72, 42),
      Offset(84, 30),
      Offset(86, 68),
      Offset(74, 80),
    ], _steel, _slate, opacity: 0.58),
    _Face([
      Offset(26, 50),
      Offset(40, 52),
      Offset(38, 60),
      Offset(24, 58),
    ], _white, _mist, opacity: 0.85),
  ];

  static const _invoice = [
    _Face([
      Offset(32, 24),
      Offset(70, 24),
      Offset(70, 82),
      Offset(32, 82),
    ], _silver, _steel, opacity: 0.38),
    _Face([
      Offset(20, 14),
      Offset(48, 14),
      Offset(48, 88),
      Offset(20, 88),
    ], _white, _mist, opacity: 0.94),
    _Face([
      Offset(48, 14),
      Offset(60, 14),
      Offset(60, 28),
      Offset(74, 42),
      Offset(74, 88),
      Offset(48, 88),
    ], _mist, _silver, opacity: 0.78),
    _Face([
      Offset(60, 14),
      Offset(74, 14),
      Offset(74, 28),
    ], _white, _mist),
    _Face([
      Offset(60, 14),
      Offset(74, 28),
      Offset(60, 28),
    ], _steel, _slate, opacity: 0.5),
    _Face([
      Offset(28, 36),
      Offset(58, 36),
      Offset(58, 40),
      Offset(28, 40),
    ], _white, _mist, opacity: 0.7),
    _Face([
      Offset(28, 48),
      Offset(50, 48),
      Offset(50, 52),
      Offset(28, 52),
    ], _mist, _silver, opacity: 0.55),
  ];

  static const _notifications = [
    _Face([
      Offset(18, 34),
      Offset(50, 16),
      Offset(50, 48),
    ], _white, _mist),
    _Face([
      Offset(50, 16),
      Offset(82, 32),
      Offset(50, 48),
    ], _mist, _silver, opacity: 0.76),
    _Face([
      Offset(18, 34),
      Offset(50, 48),
      Offset(48, 66),
      Offset(18, 58),
    ], _mist, _silver, opacity: 0.86),
    _Face([
      Offset(50, 48),
      Offset(82, 32),
      Offset(80, 58),
      Offset(52, 66),
    ], _silver, _slate, opacity: 0.6),
    _Face([
      Offset(36, 64),
      Offset(30, 86),
      Offset(48, 66),
    ], _steel, _slate, opacity: 0.55),
    _Face([
      Offset(36, 64),
      Offset(48, 66),
      Offset(46, 78),
    ], _white, _mist, opacity: 0.8),
  ];

  static final _reporting = [
    ..._bar(64, 20),
    ..._bar(40, 36),
    ..._bar(16, 52),
  ];

  static List<_Face> _bar(double x, double top) {
    const width = 16.0;
    const bottom = 84.0;
    const depth = 8.0;
    return [
      _Face([
        Offset(x, top),
        Offset(x + depth, top - depth),
        Offset(x + width + depth, top - depth),
        Offset(x + width, top),
      ], _white, _mist),
      _Face([
        Offset(x + width, top),
        Offset(x + width + depth, top - depth),
        Offset(x + width + depth, bottom - depth),
        Offset(x + width, bottom),
      ], _steel, _slate, opacity: 0.58),
      _Face([
        Offset(x, top),
        Offset(x + width, top),
        Offset(x + width, bottom),
        Offset(x, bottom),
      ], _mist, _silver, opacity: 0.9),
    ];
  }

  static final _team = [
    ..._figure(12, 22, 0.38, 0.42),
    ..._figure(52, 20, 0.38, 0.48),
    ..._figure(28, 30, 0.5, 0.96),
  ];

  static List<_Face> _figure(double ox, double oy, double scale, double alpha) {
    Offset p(double x, double y) => Offset(ox + x * scale, oy + y * scale);
    return [
      _Face([
        p(38, 18),
        p(50, 4),
        p(50, 22),
      ], _white, _mist, opacity: alpha),
      _Face([
        p(50, 4),
        p(64, 18),
        p(50, 22),
      ], _mist, _silver, opacity: alpha * 0.75),
      _Face([
        p(36, 20),
        p(50, 22),
        p(48, 36),
        p(32, 30),
      ], _mist, _silver, opacity: alpha * 0.88),
      _Face([
        p(50, 22),
        p(66, 18),
        p(68, 32),
        p(52, 36),
      ], _silver, _steel, opacity: alpha * 0.65),
      _Face([
        p(28, 40),
        p(50, 34),
        p(72, 42),
        p(50, 48),
      ], _white, _mist, opacity: alpha),
      _Face([
        p(28, 40),
        p(50, 48),
        p(48, 86),
        p(26, 74),
      ], _mist, _silver, opacity: alpha * 0.9),
      _Face([
        p(50, 48),
        p(72, 42),
        p(74, 74),
        p(52, 86),
      ], _silver, _slate, opacity: alpha * 0.6),
    ];
  }

  static const _dashboard = [
    _Face([
      Offset(16, 34),
      Offset(26, 22),
      Offset(84, 26),
      Offset(74, 38),
    ], _white, _mist),
    _Face([
      Offset(74, 38),
      Offset(84, 26),
      Offset(86, 70),
      Offset(76, 82),
    ], _steel, _slate, opacity: 0.55),
    _Face([
      Offset(14, 36),
      Offset(46, 38),
      Offset(48, 80),
      Offset(16, 78),
    ], _white, _mist, opacity: 0.95),
    _Face([
      Offset(46, 38),
      Offset(76, 36),
      Offset(78, 78),
      Offset(48, 80),
    ], _mist, _silver, opacity: 0.72),
    _Face([
      Offset(44, 48),
      Offset(58, 58),
      Offset(44, 68),
    ], _white, _mist),
    _Face([
      Offset(44, 48),
      Offset(30, 58),
      Offset(44, 68),
    ], _silver, _steel, opacity: 0.7),
    _Face([
      Offset(22, 46),
      Offset(32, 46),
      Offset(32, 52),
      Offset(22, 52),
    ], _white, _mist, opacity: 0.85),
  ];

  static const _phone = [
    _Face([
      Offset(30, 20),
      Offset(50, 8),
      Offset(70, 20),
      Offset(50, 26),
    ], _white, _mist),
    _Face([
      Offset(18, 26),
      Offset(50, 18),
      Offset(82, 28),
      Offset(50, 36),
    ], _white, _silver, opacity: 0.92),
    _Face([
      Offset(36, 24),
      Offset(50, 26),
      Offset(48, 42),
      Offset(32, 36),
    ], _mist, _silver, opacity: 0.88),
    _Face([
      Offset(50, 26),
      Offset(66, 22),
      Offset(68, 38),
      Offset(52, 42),
    ], _silver, _steel, opacity: 0.68),
    _Face([
      Offset(28, 46),
      Offset(50, 40),
      Offset(72, 48),
      Offset(50, 54),
    ], _white, _mist),
    _Face([
      Offset(28, 46),
      Offset(50, 54),
      Offset(48, 88),
      Offset(26, 76),
    ], _mist, _silver, opacity: 0.9),
    _Face([
      Offset(50, 54),
      Offset(72, 48),
      Offset(74, 76),
      Offset(52, 88),
    ], _silver, _slate, opacity: 0.6),
  ];

  static const _stock = [
    _Face([
      Offset(12, 34),
      Offset(30, 24),
      Offset(48, 34),
      Offset(30, 44),
    ], _white, _mist, opacity: 0.4),
    _Face([
      Offset(12, 34),
      Offset(30, 44),
      Offset(30, 66),
      Offset(12, 56),
    ], _mist, _silver, opacity: 0.32),
    _Face([
      Offset(30, 44),
      Offset(48, 34),
      Offset(48, 56),
      Offset(30, 66),
    ], _silver, _steel, opacity: 0.28),
    _Face([
      Offset(26, 40),
      Offset(50, 26),
      Offset(80, 40),
      Offset(56, 54),
    ], _white, _mist),
    _Face([
      Offset(26, 40),
      Offset(56, 54),
      Offset(56, 86),
      Offset(26, 72),
    ], _mist, _silver, opacity: 0.9),
    _Face([
      Offset(56, 54),
      Offset(80, 40),
      Offset(80, 72),
      Offset(56, 86),
    ], _steel, _slate, opacity: 0.58),
    _Face([
      Offset(40, 36),
      Offset(56, 32),
      Offset(68, 42),
      Offset(52, 46),
    ], _white, _mist, opacity: 0.8),
  ];

  @override
  bool shouldRepaint(covariant _GlassSculpturePainter oldDelegate) =>
      oldDelegate.kind != kind;
}
