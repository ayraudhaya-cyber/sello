import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/marketing/presentation/marketing_v2_glass_icons.dart';
import 'package:sello/features/marketing/presentation/marketing_v2_previews.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dark Vaulta-style marketing experience at `/v2`.
class MarketingV2Page extends StatefulWidget {
  const MarketingV2Page({super.key});

  @override
  State<MarketingV2Page> createState() => _MarketingV2PageState();
}

class _MarketingV2PageState extends State<MarketingV2Page> {
  final _scroll = ScrollController();
  final _featuresKey = GlobalKey();
  final _faqKey = GlobalKey();
  final _contactKey = GlobalKey();
  bool _menuOpen = false;

  static const _email = 'sello@cashro.pro';
  static const _phoneLabel = '+94 76 564 4465';
  static const _phoneUri = 'tel:+94765644465';
  static const _canvas = Color(0xFF090212);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _signIn() => context.go(RoutePaths.login);

  void _getStarted() => context.go(RoutePaths.onboarding);

  void _toTop() {
    setState(() => _menuOpen = false);
    if (!_scroll.hasClients) return;
    final motion = !MediaQuery.disableAnimationsOf(context);
    _scroll.animateTo(
      0,
      duration: motion ? AppDurations.slow : Duration.zero,
      curve: AppCurves.standard,
    );
  }

  void _scrollTo(GlobalKey key) {
    setState(() => _menuOpen = false);
    final target = key.currentContext;
    if (target == null) return;
    final motion = !MediaQuery.disableAnimationsOf(context);
    Scrollable.ensureVisible(
      target,
      duration: motion ? AppDurations.slow : Duration.zero,
      curve: AppCurves.standard,
      alignment: 0.02,
    );
  }

  Future<void> _open(String uri) async {
    await launchUrl(Uri.parse(uri));
  }

  void _showContact() {
    setState(() => _menuOpen = false);
    final motion = !MediaQuery.disableAnimationsOf(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close contact',
      barrierColor: Colors.transparent,
      transitionDuration: motion ? AppDurations.normal : Duration.zero,
      pageBuilder: (context, _, _) => _V2ContactDialog(
        email: _email,
        phoneLabel: _phoneLabel,
        phoneUri: _phoneUri,
        onOpen: _open,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: AppCurves.standard,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Title(
      title: 'Sello — Business Operations',
      color: AppColors.primary,
      child: Theme(
        data: AppTheme.light,
        child: Scaffold(
          backgroundColor: _canvas,
          body: Stack(
            children: [
              SelectionArea(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _V2Hero(onGetStarted: _getStarted, onSignIn: _signIn),
                      const _V2LogoBar(),
                      const _V2Statement(),
                      _V2Why(sectionKey: _featuresKey),
                      const _V2Audiences(),
                      const _V2Team(),
                      _V2Faq(sectionKey: _faqKey),
                      _V2Closing(
                        onGetStarted: _getStarted,
                        onTalk: () => _scrollTo(_contactKey),
                      ),
                      _V2Footer(
                        sectionKey: _contactKey,
                        onFeatures: () => _scrollTo(_featuresKey),
                        onWorkflow: () {},
                        onPricing: () {},
                        onFaq: () => _scrollTo(_faqKey),
                        onV1: _toTop,
                        onSignIn: _signIn,
                        onEmail: () => _open('mailto:$_email'),
                        onPhone: () => _open(_phoneUri),
                        onOpen: _open,
                        email: _email,
                        phoneLabel: _phoneLabel,
                      ),
                    ],
                  ),
                ),
              ),
              if (_menuOpen && MediaQuery.sizeOf(context).width < 980)
                Positioned.fill(
                  child: _V2MobileMenu(
                    key: const ValueKey('v2-menu'),
                    onFeatures: () => _scrollTo(_featuresKey),
                    onFaq: () => _scrollTo(_faqKey),
                    onPricing: () {},
                    onContact: _showContact,
                    onV1: _toTop,
                    onSignIn: _signIn,
                    onGetStarted: _getStarted,
                    email: _email,
                    phoneLabel: _phoneLabel,
                    phoneUri: _phoneUri,
                    onOpen: _open,
                  ),
                ),
              Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final inset = _v2ContentLeft(constraints.maxWidth);
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: _V2Nav(
                        menuOpen: _menuOpen,
                        onToggleMenu: () =>
                            setState(() => _menuOpen = !_menuOpen),
                        onFeatures: () => _scrollTo(_featuresKey),
                        onFaq: () => _scrollTo(_faqKey),
                        onPricing: () {},
                        onContact: _showContact,
                        onV1: _toTop,
                        onSignIn: _signIn,
                        onGetStarted: _getStarted,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _v2Max = 1480;
const double _heroFrame = 12;

/// Section headings. The hero is the only larger heading, and it stays medium.
const TextStyle _v2Heading2 = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 48,
  height: 1.12,
  fontWeight: FontWeight.w500,
  letterSpacing: -0.8,
  color: Colors.white,
);

/// Shared side inset. Wider than the hero’s old 16px edge, and wider than the
/// old 1180px column so every section shares one content edge.
double _v2Gutter(double width) {
  if (width < 640) return 20;
  if (width < 960) return 40;
  if (width < 1280) return 64;
  if (width < 1600) return 88;
  return 112;
}

/// Left edge of the shared content column, measured from the screen edge.
double _v2ContentLeft(double width) {
  final gutter = _v2Gutter(width);
  if (width - gutter * 2 <= _v2Max) return gutter;
  return (width - _v2Max) / 2;
}

class _V2Inset extends StatelessWidget {
  const _V2Inset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _v2Gutter(constraints.maxWidth),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _v2Max),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _V2Shell extends StatelessWidget {
  const _V2Shell({required this.child, this.padding, this.sectionKey});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Key? sectionKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return _V2Inset(
          child: Padding(
            key: sectionKey,
            padding:
                padding ??
                EdgeInsets.symmetric(vertical: width < 700 ? 64 : 88),
            child: child,
          ),
        );
      },
    );
  }
}

class _V2Nav extends StatelessWidget {
  const _V2Nav({
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onFeatures,
    required this.onFaq,
    required this.onPricing,
    required this.onContact,
    required this.onV1,
    required this.onSignIn,
    required this.onGetStarted,
  });

  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onFeatures;
  final VoidCallback onFaq;
  final VoidCallback onPricing;
  final VoidCallback onContact;
  final VoidCallback onV1;
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    assert(onPricing.hashCode >= 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: ColoredBox(
                color: const Color(0x8C1C1630),
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: _V2Wordmark(
                            onPressed: onV1,
                            height: wide ? 30 : 26,
                          ),
                        ),
                        if (wide) ...[
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _V2NavLink(
                                  label: 'Features',
                                  onPressed: onFeatures,
                                ),
                                const SizedBox(width: 18),
                                _V2NavLink(label: 'FAQ', onPressed: onFaq),
                                const SizedBox(width: 18),
                                _V2NavLink(
                                  label: 'Contact',
                                  onPressed: onContact,
                                ),
                              ],
                            ),
                          ),
                          _V2NavLink(label: 'Sign in', onPressed: onSignIn),
                          const SizedBox(width: 8),
                          _V2PillButton(
                            label: 'Get started',
                            onPressed: onGetStarted,
                          ),
                        ] else ...[
                          const Spacer(),
                          _V2PillButton(
                            label: 'Get started',
                            onPressed: onGetStarted,
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: menuOpen ? 'Close menu' : 'Open menu',
                            color: Colors.white,
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              minimumSize: const Size(40, 40),
                            ),
                            onPressed: onToggleMenu,
                            icon: Icon(
                              menuOpen
                                  ? Icons.close_rounded
                                  : Icons.menu_rounded,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _V2PillButton extends StatelessWidget {
  const _V2PillButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      child: Text(label),
    );
  }
}

class _V2MobileMenu extends StatelessWidget {
  const _V2MobileMenu({
    super.key,
    required this.onFeatures,
    required this.onFaq,
    required this.onPricing,
    required this.onContact,
    required this.onV1,
    required this.onSignIn,
    required this.onGetStarted,
    required this.email,
    required this.phoneLabel,
    required this.phoneUri,
    required this.onOpen,
  });

  final VoidCallback onFeatures;
  final VoidCallback onFaq;
  final VoidCallback onPricing;
  final VoidCallback onContact;
  final VoidCallback onV1;
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;
  final String email;
  final String phoneLabel;
  final String phoneUri;
  final Future<void> Function(String uri) onOpen;

  static const _address = '207 Saranankara Road, Dehiwala';
  static const _detailStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 13,
    height: 1.7,
    fontWeight: FontWeight.w400,
    color: Color(0xFFB7B0C8),
  );

  @override
  Widget build(BuildContext context) {
    assert(onPricing.hashCode >= 0 && onV1.hashCode >= 0);
    return ColoredBox(
      color: const Color(0xFF120C1E),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 96, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in [
              ('Features', onFeatures),
              ('FAQ', onFaq),
              ('Contact', onContact),
            ])
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: item.$2,
                  style: TextButton.styleFrom(
                    alignment: Alignment.center,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(item.$1),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onSignIn,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 8),
            _V2GlowButton(
              label: 'Get started',
              onPressed: onGetStarted,
              expanded: true,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => onOpen('mailto:$email'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB7B0C8),
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: _detailStyle,
              ),
              child: Text(email),
            ),
            TextButton(
              onPressed: () => onOpen(phoneUri),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB7B0C8),
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: _detailStyle,
              ),
              child: Text(phoneLabel),
            ),
            const Text(_address, textAlign: TextAlign.center, style: _detailStyle),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MenuSocialButton(
                  label: 'Facebook',
                  onPressed: () =>
                      onOpen('https://facebook.com/unitechsolutions.pro'),
                  painter: const _FacebookMarkPainter(),
                ),
                const SizedBox(width: 14),
                _MenuSocialButton(
                  label: 'Instagram',
                  onPressed: () => onOpen(
                    'https://www.instagram.com/unitech_solutions_it',
                  ),
                  painter: const _InstagramMarkPainter(),
                ),
                const SizedBox(width: 14),
                _MenuSocialButton(
                  label: 'LinkedIn',
                  onPressed: () => onOpen(
                    'https://www.linkedin.com/company/unitech-solutions-it',
                  ),
                  painter: const _LinkedInMarkPainter(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuSocialButton extends StatelessWidget {
  const _MenuSocialButton({
    required this.label,
    required this.onPressed,
    required this.painter,
  });

  final String label;
  final VoidCallback onPressed;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        fixedSize: const Size(42, 42),
        shape: const CircleBorder(),
      ),
      icon: CustomPaint(size: const Size(16, 16), painter: painter),
    );
  }
}

class _FacebookMarkPainter extends CustomPainter {
  const _FacebookMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 22);
    final path = Path()
      ..moveTo(15.2, 1.2)
      ..lineTo(11.4, 1.2)
      ..cubicTo(8.0, 1.2, 6.6, 3.2, 6.6, 6.4)
      ..lineTo(6.6, 8.6)
      ..lineTo(4.2, 8.6)
      ..lineTo(4.2, 11.6)
      ..lineTo(6.6, 11.6)
      ..lineTo(6.6, 20.6)
      ..lineTo(10.2, 20.6)
      ..lineTo(10.2, 11.6)
      ..lineTo(13.0, 11.6)
      ..lineTo(13.6, 8.6)
      ..lineTo(10.2, 8.6)
      ..lineTo(10.2, 6.8)
      ..cubicTo(10.2, 5.8, 10.5, 5.0, 11.8, 5.0)
      ..lineTo(15.2, 5.0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FacebookMarkPainter oldDelegate) => false;
}

class _InstagramMarkPainter extends CustomPainter {
  const _InstagramMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, paint);
    canvas.drawCircle(size.center(Offset.zero), size.width * 0.22, paint);
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.26),
      1.1,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _InstagramMarkPainter oldDelegate) => false;
}

class _LinkedInMarkPainter extends CustomPainter {
  const _LinkedInMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(2),
      ),
      paint,
    );
    final text = TextPainter(
      text: const TextSpan(
        text: 'in',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _LinkedInMarkPainter oldDelegate) => false;
}

class _V2NavLink extends StatelessWidget {
  const _V2NavLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFB7AEC4),
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w400,
          fontSize: 15,
        ),
      ),
      child: Text(label),
    );
  }
}

class _V2Wordmark extends StatelessWidget {
  const _V2Wordmark({required this.onPressed, required this.height});

  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        AppAssets.wordmarkOnDark,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Sello',
      ),
    );
  }
}

class _V2GlowButton extends StatelessWidget {
  const _V2GlowButton({
    required this.label,
    required this.onPressed,
    this.expanded = false,
    this.height = 46,
  });

  final String label;
  final VoidCallback onPressed;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(
            color: Color(0x887A5CFF),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: Size(expanded ? double.infinity : 48, height),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        child: Text(label),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _V2Hero extends StatelessWidget {
  const _V2Hero({required this.onGetStarted, required this.onSignIn});

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final sideBySide = width >= 960;
        final inner = (_v2ContentLeft(width) - _heroFrame).clamp(0.0, 480.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            _heroFrame,
            _heroFrame,
            _heroFrame,
            0,
          ),
          child: Builder(
            builder: (context) {
              final copy = Column(
                crossAxisAlignment: sideBySide
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Align(
                    alignment: sideBySide
                        ? Alignment.centerLeft
                        : Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: const Text(
                        'Manage. Sell. Collect. Grow.',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFF3EEFF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Semantics(
                    header: true,
                    child: Text(
                      'Everything your\nbusiness needs,\nin one place.',
                      textAlign: sideBySide
                          ? TextAlign.start
                          : TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: sideBySide ? 64 : 40,
                        height: 1.05,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      sideBySide
                          ? 'Manage orders, inventory, customers and payments,\nand your team, with a dedicated Sales Rep App.'
                          : 'Manage orders, inventory,\ncustomers and payments, and your team,\nwith a dedicated Sales Rep App.',
                      textAlign: sideBySide
                          ? TextAlign.start
                          : TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: sideBySide ? 18 : 15,
                        height: 1.5,
                        color: const Color(0xFFDDD6F2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    alignment: sideBySide
                        ? WrapAlignment.start
                        : WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: onGetStarted,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF16141F),
                          minimumSize: const Size(0, 56),
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        child: const Text('Get started'),
                      ),
                      FilledButton(
                        onPressed: onSignIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF5B3AD6),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 56),
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ],
              );

              final phone = V2HeroShowcase(
                width: sideBySide ? 320 : 270,
                compact: !sideBySide,
              );

              return ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.0, 0.15),
                      end: Alignment(1.05, -0.35),
                      colors: [
                        Color(0xFF140826),
                        Color(0xFF2A1458),
                        Color(0xFF5A36C8),
                        Color(0xFF7B5CFF),
                      ],
                      stops: [0.0, 0.34, 0.68, 1.0],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -80,
                        top: 40,
                        child: IgnorePointer(
                          child: Container(
                            width: 420,
                            height: 420,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(
                                    0xFF9A82FF,
                                  ).withValues(alpha: 0.45),
                                  const Color(0xFF9A82FF).withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 80,
                        bottom: -120,
                        child: IgnorePointer(
                          child: Container(
                            width: 340,
                            height: 340,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                                width: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          inner,
                          sideBySide ? 156 : 112,
                          inner,
                          sideBySide ? 168 : 72,
                        ),
                        child: sideBySide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(flex: 4, child: copy),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    flex: 6,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: V2HeroShowcase(width: 320),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  copy,
                                  const SizedBox(height: 56),
                                  phone,
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _V2LogoBar extends StatelessWidget {
  const _V2LogoBar();

  @override
  Widget build(BuildContext context) {
    return _V2Inset(
      child: Padding(
        padding: const EdgeInsets.only(top: 88, bottom: 28),
        child: Column(
          children: [
            const Text(
              'TRUSTED BY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 3.2,
                color: Color(0xFF8E879F),
              ),
            ),
            const SizedBox(height: 28),
            const _V2LogoMarquee(),
          ],
        ),
      ),
    );
  }
}

class _V2LogoMarquee extends StatefulWidget {
  const _V2LogoMarquee();

  @override
  State<_V2LogoMarquee> createState() => _V2LogoMarqueeState();
}

class _V2LogoMarqueeState extends State<_V2LogoMarquee>
    with SingleTickerProviderStateMixin {
  static const _logoHeight = 40.0;

  static const _logos = <Widget>[
    _StripImageLogo('assets/brand/v2_logo_unexon.png', 'Unexon'),
    _UniqeLogo(),
    _StripImageLogo(
      'assets/brand/v2_logo_namson.png',
      'Namson Lanka',
      scale: 0.84,
    ),
    _WordmarkLogo('Alder & Co'),
    _MarkWordLogo('Northlane'),
  ];

  late final AnimationController _controller;
  final _setKey = GlobalKey();
  double _setWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) return;
    final box = _setKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box != null && box.hasSize ? box.size.width : 0.0;
    final motion =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    setState(() => _setWidth = width);
    if (motion && width > 0 && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _logoSet({Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final logo in _logos) ...[logo, const SizedBox(width: 88)],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final copies = _setWidth <= 0
            ? 2
            : (constraints.maxWidth / _setWidth).ceil() + 2;
        final strip = RepaintBoundary(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < copies; i++)
                _logoSet(key: i == 0 ? _setKey : null),
            ],
          ),
        );
        return ClipRect(
          child: SizedBox(
            height: 48,
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  child: strip,
                  builder: (context, child) {
                    final dx = _setWidth <= 0
                        ? 0.0
                        : (_controller.value * _setWidth) - _setWidth;
                    return OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      child: Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      ),
                    );
                  },
                ),
                const _LogoEdgeFade(align: Alignment.centerLeft),
                const _LogoEdgeFade(align: Alignment.centerRight),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LogoEdgeFade extends StatelessWidget {
  const _LogoEdgeFade({required this.align});

  final Alignment align;

  @override
  Widget build(BuildContext context) {
    final fromLeft = align == Alignment.centerLeft;
    return Align(
      alignment: align,
      child: IgnorePointer(
        child: Container(
          width: 88,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: fromLeft
                  ? const [Color(0xFF090212), Color(0x00090212)]
                  : const [Color(0x00090212), Color(0xFF090212)],
            ),
          ),
        ),
      ),
    );
  }
}

class _V2Statement extends StatelessWidget {
  const _V2Statement();

  @override
  Widget build(BuildContext context) {
    return _V2Inset(
      child: Padding(
        padding: const EdgeInsets.only(top: 72, bottom: 32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 860;
            final heading = Text(
              'Who said running a product\nbusiness has to be scattered?',
              style: _v2Heading2,
            );
            final body = Text(
              'With Sello, orders, stock and customers stay connected.\n'
              'The office and the field share one picture of the day, from the\n'
              'first order through to the last collection.',
              textAlign: stacked ? TextAlign.start : TextAlign.right,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 18,
                height: 1.6,
                color: Color(0xFFA89FBA),
              ),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 20), body],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: heading),
                const SizedBox(width: 40),
                Expanded(flex: 5, child: body),
              ],
            );
          },
        ),
      ),
    );
  }
}

const _stripInk = Color(0xFFC4B6D2);

class _StripImageLogo extends StatelessWidget {
  const _StripImageLogo(this.asset, this.label, {this.scale = 1});

  final String asset;
  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      height: _V2LogoMarqueeState._logoHeight * scale,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: label,
    );
  }
}

class _UniqeLogo extends StatelessWidget {
  const _UniqeLogo();

  static const _style = TextStyle(
    fontFamily: 'Georgia',
    fontFamilyFallback: ['Times New Roman', 'Iowan Old Style', 'serif'],
    fontSize: 28,
    height: 1,
    fontWeight: FontWeight.w500,
    color: _stripInk,
    letterSpacing: 0.2,
  );

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Uniq', style: _style),
        SizedBox(
          width: 16,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 1,
                top: 0,
                child: CustomPaint(
                  size: Size(13, 7),
                  painter: _WaveAccentPainter(),
                ),
              ),
              Positioned(left: 0, bottom: 0, child: Text('e', style: _style)),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveAccentPainter extends CustomPainter {
  const _WaveAccentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.72)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.02,
        size.width * 0.62,
        size.height * 0.98,
        size.width,
        size.height * 0.28,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = _stripInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveAccentPainter oldDelegate) => false;
}

class _WordmarkLogo extends StatelessWidget {
  const _WordmarkLogo(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'Georgia',
        fontFamilyFallback: ['Times New Roman', 'serif'],
        fontSize: 22,
        height: 1,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
        color: _stripInk,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _MarkWordLogo extends StatelessWidget {
  const _MarkWordLogo(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CustomPaint(size: Size(18, 18), painter: _NorthlaneMarkPainter()),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.4,
            color: _stripInk,
          ),
        ),
      ],
    );
  }
}

class _NorthlaneMarkPainter extends CustomPainter {
  const _NorthlaneMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _stripInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.82)
      ..lineTo(size.width * 0.5, size.height * 0.16)
      ..lineTo(size.width * 0.82, size.height * 0.82);
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * 0.34, size.height * 0.56),
      Offset(size.width * 0.66, size.height * 0.56),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _NorthlaneMarkPainter oldDelegate) => false;
}

class _V2Why extends StatelessWidget {
  const _V2Why({required this.sectionKey});

  final Key sectionKey;

  static const _items = [
    (
      V2GlassIconKind.customers,
      Icons.group_outlined,
      'Customer Management',
      'Maintain customer profiles, contact information, and purchase history.',
    ),
    (
      V2GlassIconKind.payments,
      Icons.account_balance_wallet_outlined,
      'Payments & Collections',
      'Record payments, manage outstanding balances, and track cheque-related transactions.',
    ),
    (
      V2GlassIconKind.invoice,
      Icons.description_outlined,
      'Invoicing',
      'Create, manage, and share professional invoices.',
    ),
    (
      V2GlassIconKind.notifications,
      Icons.chat_bubble_outline,
      'Business Notifications',
      'Keep customers and your team informed through SMS and WhatsApp sharing.',
    ),
    (
      V2GlassIconKind.reporting,
      Icons.bar_chart,
      'Business Reporting',
      'Understand sales, orders, collections, and business performance through reports.',
    ),
    (
      V2GlassIconKind.team,
      Icons.groups_outlined,
      'Team Management',
      'Manage team members and assign responsibilities based on their roles.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _V2Shell(
      sectionKey: sectionKey,
      padding: const EdgeInsets.fromLTRB(0, 88, 0, 168),
      child: Column(
        children: [
          const Text(
            'CORE OF SELLO',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.4,
              color: Color(0xFFB9A6FF),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Built for the work of selling and supplying.',
            textAlign: TextAlign.center,
            style: _v2Heading2,
          ),
          const SizedBox(height: 10),
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Sello connects the activities that keep a product business moving every day.',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                height: 1.3,
                color: Color(0xFFC8C2D4),
              ),
            ),
          ),
          const SizedBox(height: 36),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 640
                  ? 2
                  : 1;
              const gap = 18.0;
              return Column(
                children: [
                  for (
                    var start = 0;
                    start < _items.length;
                    start += columns
                  ) ...[
                    if (start > 0) const SizedBox(height: gap),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var i = start;
                            i < start + columns && i < _items.length;
                            i++
                          ) ...[
                            if (i > start) const SizedBox(width: gap),
                            Expanded(
                              child: _WhyCard(
                                kind: _items[i].$1,
                                icon: _items[i].$2,
                                title: _items[i].$3,
                                body: _items[i].$4,
                                tone: i,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WhyCard extends StatefulWidget {
  const _WhyCard({
    required this.kind,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final V2GlassIconKind kind;
  final IconData icon;
  final String title;
  final String body;
  final int tone;

  @override
  State<_WhyCard> createState() => _WhyCardState();
}

class _WhyCardState extends State<_WhyCard> {
  bool _hovered = false;

  /// First card is the previous purple shifted slightly toward magenta.
  /// Last card is unchanged. The four cards between them step through that range.
  static const _gradients = [
    [Color(0xFF9E64DA), Color(0xFF8C50CC)],
    [Color(0xFF8C5ACE), Color(0xFF7945BD)],
    [Color(0xFF7B4FC3), Color(0xFF663AAD)],
    [Color(0xFF6945B7), Color(0xFF522E9E)],
    [Color(0xFF583AAC), Color(0xFF3F238E)],
    [Color(0xFF4630A0), Color(0xFF2C187F)],
  ];

  List<Color> get _colors {
    final base = _gradients[widget.tone.clamp(0, _gradients.length - 1)];
    if (!_hovered) return base;
    return [
      for (final color in base)
        Color.lerp(color, const Color(0xFF120A28), 0.16)!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.icon.codePoint > 0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _colors,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0x12000000),
                shape: BoxShape.circle,
              ),
              child: V2GlassIcon(
                kind: widget.kind,
                size: widget.kind == V2GlassIconKind.team ? 70 : 46,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              widget.title,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 18,
                height: 1.4,
                color: Color(0xFFE4DCF8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _V2Audiences extends StatelessWidget {
  const _V2Audiences();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_heroFrame, 12, _heroFrame, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _AudienceBackdropPainter()),
            ),
            _V2Inset(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _AudienceHeading(),
                    SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 640),
                      child: Text(
                        'Sello supports businesses that manage products, customer orders, inventory and collections every day.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 16,
                          height: 1.5,
                          color: Color(0xFFF3EEFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 52),
                    const _AudienceGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceBackdropPainter extends CustomPainter {
  const _AudienceBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF6E48E4),
            Color(0xFF8A62EE),
            Color(0xFFA888F6),
            Color(0xFFC4B0FF),
          ],
          stops: [0.0, 0.3, 0.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _AudienceBackdropPainter oldDelegate) => false;
}

class _AudienceHeading extends StatelessWidget {
  const _AudienceHeading();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            'One platform for businesses that sell, supply and grow.',
            textAlign: TextAlign.center,
            style: _v2Heading2.copyWith(
              color: Colors.white,
              fontSize: wide ? 48 : 34,
            ),
          ),
        );
      },
    );
  }
}

class _AudienceGrid extends StatelessWidget {
  const _AudienceGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const gap = 16.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final kind in _AudienceKind.values)
              SizedBox(
                width: width,
                child: _AudienceTile(kind: kind),
              ),
          ],
        );
      },
    );
  }
}

enum _AudienceKind { wholesale, retail, trading, product }

class _AudienceTile extends StatelessWidget {
  const _AudienceTile({required this.kind});

  final _AudienceKind kind;

  @override
  Widget build(BuildContext context) {
    final tone = _audienceTone(kind);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF8B6CF2).withValues(alpha: 0.46),
                  const Color(0xFF6A48E4).withValues(alpha: 0.34),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final height = (constraints.maxWidth * 0.86).clamp(
                      196.0,
                      268.0,
                    );
                    return SizedBox(
                      height: height,
                      child: CustomPaint(
                        painter: _AudienceArtPainter(kind),
                        child: const SizedBox.expand(),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 2, 22, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tone.title,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 18,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tone.body,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 15,
                          height: 1.45,
                          color: Color(0xFFD5CEE6),
                        ),
                      ),
                    ],
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

class _AudienceTone {
  const _AudienceTone({
    required this.title,
    required this.body,
    required this.wash,
    required this.base,
    required this.ink,
    required this.soft,
  });

  final String title;
  final String body;
  final Color wash;
  final Color base;
  final Color ink;
  final Color soft;
}

_AudienceTone _audienceTone(_AudienceKind kind) {
  return switch (kind) {
    _AudienceKind.wholesale => const _AudienceTone(
      title: 'Wholesale & Distribution',
      body: 'Manage customer orders, stock,\ndeliveries and collections.',
      wash: Color(0xFF8E70D6),
      base: Color(0xFF5840A8),
      ink: Color(0xFF4A348F),
      soft: Color(0xFFE4D8FF),
    ),
    _AudienceKind.retail => const _AudienceTone(
      title: 'Retail Businesses',
      body: 'Keep products, inventory,\ncustomers and sales organised.',
      wash: Color(0xFF8E70D6),
      base: Color(0xFF5840A8),
      ink: Color(0xFF4A348F),
      soft: Color(0xFFE4D8FF),
    ),
    _AudienceKind.trading => const _AudienceTone(
      title: 'Trading Businesses',
      body: 'Manage product catalogues,\ncustomer accounts and transactions.',
      wash: Color(0xFF8E70D6),
      base: Color(0xFF5840A8),
      ink: Color(0xFF4A348F),
      soft: Color(0xFFE4D8FF),
    ),
    _AudienceKind.product => const _AudienceTone(
      title: 'Product-Based Businesses',
      body: 'Simplify order processing\nand everyday operations.',
      wash: Color(0xFF8E70D6),
      base: Color(0xFF5840A8),
      ink: Color(0xFF4A348F),
      soft: Color(0xFFE4D8FF),
    ),
  };
}

class _AudienceArtPainter extends CustomPainter {
  _AudienceArtPainter(this.kind);

  final _AudienceKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final tone = _audienceTone(kind);
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.32),
      size.shortestSide * 0.42,
      Paint()
        ..color = const Color(0xFFB7AEC8).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    switch (kind) {
      case _AudienceKind.wholesale:
        _wholesale(canvas, size, tone);
      case _AudienceKind.retail:
        _retail(canvas, size, tone);
      case _AudienceKind.trading:
        _trading(canvas, size, tone);
      case _AudienceKind.product:
        _product(canvas, size, tone);
    }
  }

  void _wholesale(Canvas canvas, Size size, _AudienceTone tone) {
    final w = size.width;
    final h = size.height;
    _ground(canvas, size, tone.ink);
    final route = Path()
      ..moveTo(w * 0.08, h * 0.62)
      ..quadraticBezierTo(w * 0.4, h * 0.28, w * 0.92, h * 0.48);
    canvas.drawPath(
      route,
      Paint()
        ..color = tone.soft.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    _box(canvas, Rect.fromLTWH(w * 0.10, h * 0.42, w * 0.16, h * 0.18), tone);
    _box(
      canvas,
      Rect.fromLTWH(w * 0.16, h * 0.30, w * 0.14, h * 0.16),
      tone,
      fill: tone.soft,
    );
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.42, h * 0.40, w * 0.42, h * 0.22),
      14,
      tone.ink,
    );
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.66, h * 0.44, w * 0.13, h * 0.11),
      6,
      tone.soft.withValues(alpha: 0.92),
    );
    _wheel(canvas, Offset(w * 0.54, h * 0.64), w * 0.038, tone);
    _wheel(canvas, Offset(w * 0.76, h * 0.64), w * 0.038, tone);
  }

  void _retail(Canvas canvas, Size size, _AudienceTone tone) {
    final w = size.width;
    final h = size.height;
    _ground(canvas, size, tone.ink);
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.22, h * 0.28, w * 0.56, h * 0.42),
      16,
      tone.soft.withValues(alpha: 0.96),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.18, h * 0.24, w * 0.64, h * 0.12),
      10,
      tone.ink,
    );
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.30, h * 0.42, w * 0.26, h * 0.20),
      8,
      tone.base.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      Offset(w * 0.37, h * 0.52),
      w * 0.028,
      Paint()..color = tone.soft,
    );
    canvas.drawCircle(
      Offset(w * 0.48, h * 0.52),
      w * 0.028,
      Paint()..color = tone.ink.withValues(alpha: 0.85),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.60, h * 0.42, w * 0.10, h * 0.28),
      6,
      tone.base,
    );
    final bag = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.78, h * 0.46, w * 0.12, h * 0.16),
      const Radius.circular(6),
    );
    canvas.drawRRect(bag, Paint()..color = tone.soft);
    canvas.drawArc(
      Rect.fromLTWH(w * 0.80, h * 0.40, w * 0.08, h * 0.10),
      3.4,
      2.6,
      false,
      Paint()
        ..color = tone.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _trading(Canvas canvas, Size size, _AudienceTone tone) {
    final w = size.width;
    final h = size.height;
    canvas.save();
    canvas.translate(w * 0.28, h * 0.42);
    canvas.rotate(-0.12);
    _rrect(
      canvas,
      Rect.fromCenter(center: Offset.zero, width: w * 0.42, height: h * 0.46),
      14,
      tone.base,
    );
    canvas.restore();
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.30, h * 0.22, w * 0.46, h * 0.50),
      16,
      tone.soft.withValues(alpha: 0.98),
    );
    final chart = Path()
      ..moveTo(w * 0.38, h * 0.52)
      ..cubicTo(w * 0.46, h * 0.50, w * 0.50, h * 0.34, w * 0.58, h * 0.38)
      ..cubicTo(w * 0.64, h * 0.41, w * 0.66, h * 0.30, w * 0.70, h * 0.28);
    canvas.drawPath(
      chart,
      Paint()
        ..color = tone.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < 3; i++) {
      _rrect(
        canvas,
        Rect.fromLTWH(w * 0.38, h * (0.32 + i * 0.07), w * 0.22, h * 0.025),
        4,
        tone.base,
      );
    }
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.58),
      w * 0.055,
      Paint()..color = tone.ink.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.58),
      w * 0.028,
      Paint()
        ..color = tone.soft.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _product(Canvas canvas, Size size, _AudienceTone tone) {
    final w = size.width;
    final h = size.height;
    _ground(canvas, size, tone.ink);
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.16, h * 0.40, w * 0.34, h * 0.26),
      8,
      tone.ink.withValues(alpha: 0.82),
    );
    final lid = Path()
      ..moveTo(w * 0.16, h * 0.42)
      ..lineTo(w * 0.33, h * 0.28)
      ..lineTo(w * 0.52, h * 0.28)
      ..lineTo(w * 0.50, h * 0.42)
      ..close();
    canvas.drawPath(lid, Paint()..color = tone.base);
    _rrect(
      canvas,
      Rect.fromLTWH(w * 0.28, h * 0.46, w * 0.12, h * 0.08),
      4,
      tone.soft.withValues(alpha: 0.94),
    );
    canvas.save();
    canvas.translate(w * 0.62, h * 0.46);
    canvas.rotate(0.08);
    _rrect(
      canvas,
      Rect.fromCenter(center: Offset.zero, width: w * 0.34, height: h * 0.40),
      12,
      tone.soft.withValues(alpha: 0.98),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(-w * 0.10, h * (-0.10 + i * 0.09)),
        w * 0.018,
        Paint()..color = tone.ink,
      );
      _rrect(
        canvas,
        Rect.fromLTWH(-w * 0.05, h * (-0.11 + i * 0.09), w * 0.16, h * 0.02),
        3,
        tone.base,
      );
    }
    canvas.restore();
  }

  void _ground(Canvas canvas, Size size, Color ink) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.78),
        width: size.width * 0.78,
        height: size.height * 0.14,
      ),
      Paint()
        ..color = ink.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _box(Canvas canvas, Rect rect, _AudienceTone tone, {Color? fill}) {
    _rrect(canvas, rect, 8, fill ?? tone.soft);
    canvas.drawLine(
      Offset(rect.center.dx, rect.top + 4),
      Offset(rect.center.dx, rect.bottom - 4),
      Paint()
        ..color = tone.base
        ..strokeWidth = 2,
    );
  }

  void _wheel(Canvas canvas, Offset center, double radius, _AudienceTone tone) {
    canvas.drawCircle(center, radius, Paint()..color = tone.ink);
    canvas.drawCircle(center, radius * 0.42, Paint()..color = tone.soft);
  }

  void _rrect(Canvas canvas, Rect rect, double radius, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _AudienceArtPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

class _V2Team extends StatelessWidget {
  const _V2Team();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1648), Color(0xFF140A28), Color(0xFF090212)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: _V2Shell(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final gap = 16.0;
            final topHeight = wide ? 500.0 : 540.0;
            final bottomHeight = wide ? 440.0 : 500.0;
            final bento = wide
                ? SizedBox(
                    height: topHeight + gap + bottomHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 12,
                          child: Column(
                            children: [
                              SizedBox(
                                height: topHeight,
                                child: const _TeamPhotoCard(
                                  asset: 'assets/brand/v2_team_owners.jpg',
                                  title: 'Owner & Manager',
                                  body:
                                      'See the whole business at once, and keep day-to-day\noperations, people and performance in view.',
                                ),
                              ),
                              SizedBox(height: gap),
                              SizedBox(
                                height: bottomHeight,
                                child: const _TeamPurpleCard(
                                  asset: 'assets/brand/v2_team_store.png',
                                  title: 'Store & Sales In-charge',
                                  body:
                                      'Run daily sales, stock and the shop floor, and\nkeep inventory responsibilities clear for the team.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: gap),
                        const Expanded(
                          flex: 11,
                          child: _TeamPortraitCard(
                            asset: 'assets/brand/v2_team_sales.jpg',
                            title: 'Sales Representative',
                            body:
                                'Handle customer visits, order taking and collections,\nwhile staying connected to the business.',
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: topHeight,
                        child: const _TeamPhotoCard(
                          asset: 'assets/brand/v2_team_owners.jpg',
                          title: 'Owner & Manager',
                          body:
                              'See the whole business at once, and keep day-to-day\noperations, people and performance in view.',
                        ),
                      ),
                      SizedBox(height: gap),
                      SizedBox(
                        height: bottomHeight,
                        child: const _TeamPurpleCard(
                          asset: 'assets/brand/v2_team_store.png',
                          title: 'Store & Sales In-charge',
                          body:
                              'Run daily sales, stock and the shop floor, and\nkeep inventory responsibilities clear for the team.',
                        ),
                      ),
                      SizedBox(height: gap),
                      const SizedBox(
                        height: 640,
                        child: _TeamPortraitCard(
                          asset: 'assets/brand/v2_team_sales.jpg',
                          title: 'Sales Representative',
                          body:
                              'Handle customer visits, order taking and collections,\nwhile staying connected to the business.',
                        ),
                      ),
                    ],
                  );
            return Column(
              children: [
                const Text(
                  'THE TEAM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.8,
                    color: Color(0xFFB9A6FF),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your entire team, working in sync.',
                  textAlign: TextAlign.center,
                  style: _v2Heading2.copyWith(fontSize: wide ? 48 : 34),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const Text(
                    'Give everyone the access and tools they need to do their job, while keeping business operations connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFFC4BDD6),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                bento,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TeamPhotoCard extends StatelessWidget {
  const _TeamPhotoCard({
    required this.asset,
    required this.title,
    required this.body,
  });

  final String asset;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF241C3A)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00090212),
                  Color(0x66090212),
                  Color(0xF2090212),
                ],
                stops: [0.28, 0.58, 1],
              ),
            ),
          ),
          Positioned(
            left: 40,
            right: 40,
            bottom: 40,
            child: _TeamCopy(title: title, body: body),
          ),
        ],
      ),
    );
  }
}

class _TeamPurpleCard extends StatelessWidget {
  const _TeamPurpleCard({
    required this.asset,
    required this.title,
    required this.body,
  });

  final String asset;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF7D3DCD), Color(0xFF0F031F)],
              ),
            ),
          ),
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x007D3DCD),
                  Color(0x660F031F),
                  Color(0xF20F031F),
                ],
                stops: [0.35, 0.68, 1],
              ),
            ),
          ),
          Positioned(
            left: 40,
            right: 40,
            bottom: 40,
            child: _TeamCopy(
              title: title,
              body: body,
              bodyColor: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamPortraitCard extends StatelessWidget {
  const _TeamPortraitCard({
    required this.asset,
    required this.title,
    required this.body,
  });

  final String asset;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF1A1430)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00090212),
                  Color(0x73090212),
                  Color(0xF2090212),
                ],
                stops: [0.3, 0.62, 1],
              ),
            ),
          ),
          Positioned(
            left: 40,
            right: 40,
            bottom: 40,
            child: _TeamCopy(title: title, body: body),
          ),
        ],
      ),
    );
  }
}

class _TeamCopy extends StatelessWidget {
  const _TeamCopy({
    required this.title,
    required this.body,
    this.bodyColor = const Color(0xFFC4BDD6),
  });

  final String title;
  final String body;
  final Color bodyColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 18,
            height: 1.45,
            color: bodyColor,
          ),
        ),
      ],
    );
  }
}

class _V2Faq extends StatefulWidget {
  const _V2Faq({required this.sectionKey});

  final Key sectionKey;

  @override
  State<_V2Faq> createState() => _V2FaqState();
}

class _V2FaqState extends State<_V2Faq> {
  int? _open = 0;

  static const _items = [
    (
      'What types of businesses can use Sello?',
      'Sello is for businesses that sell, supply or trade physical products, including wholesale, distribution, retail and trading.',
    ),
    (
      'Can I access Sello from my computer and mobile?',
      'Yes. Use the Windows desktop app, the web app in a browser, or the Android app for sales visits, orders and collections.',
    ),
    (
      'Can multiple employees use one business account?',
      'Yes. An owner can add team members as Manager, Store In-charge or Sales Representative. Access follows each role.',
    ),
    (
      'Can I manage multiple branches?',
      'Sello organises stock and people around a branch. A new business starts with a Head Office. Creating additional branches in the product is not available yet.',
    ),
    (
      'Can I track customer payments and outstanding balances?',
      'Yes. You can record collections, including cheque-related transactions, and see what a customer still owes.',
    ),
    (
      'How can I get started with Sello?',
      'Choose Get started and use the email address that was invited. New businesses join by invitation.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF090212),
      child: _V2Shell(
        sectionKey: widget.sectionKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _v2Max * 8 / 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _V2Intro(
                  title: 'Questions about Sello?',
                  body:
                      'Straight answers about who Sello is for and how to begin.',
                  center: false,
                ),
                const SizedBox(height: 28),
                for (var i = 0; i < _items.length; i++)
                  _V2FaqItem(
                    question: _items[i].$1,
                    answer: _items[i].$2,
                    expanded: _open == i,
                    onToggle: () =>
                        setState(() => _open = _open == i ? null : i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _V2FaqItem extends StatelessWidget {
  const _V2FaqItem({
    required this.question,
    required this.answer,
    required this.expanded,
    required this.onToggle,
  });

  final String question;
  final String answer;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF241E30),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(18),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          splashColor: Colors.white.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 18, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        question,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 20,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: motion ? AppDurations.fast : Duration.zero,
                      child: const _ThinChevron(size: 22),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: motion ? AppDurations.normal : Duration.zero,
                  curve: AppCurves.standard,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10, right: 38),
                          child: Text(
                            answer,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFFB7B1C6),
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinChevron extends StatelessWidget {
  const _ThinChevron({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _ThinChevronPainter(),
    );
  }
}

class _ThinChevronPainter extends CustomPainter {
  const _ThinChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC8C2D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.16, size.height * 0.36)
      ..lineTo(size.width * 0.5, size.height * 0.66)
      ..lineTo(size.width * 0.84, size.height * 0.36);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ThinChevronPainter oldDelegate) => false;
}

class _V2Closing extends StatelessWidget {
  const _V2Closing({required this.onGetStarted, required this.onTalk});

  final VoidCallback onGetStarted;
  final VoidCallback onTalk;

  @override
  Widget build(BuildContext context) {
    return _V2Shell(
      padding: const EdgeInsets.fromLTRB(0, 72, 0, 28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return SizedBox(
            width: constraints.maxWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _ClosingAtmospherePainter()),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 64 : 24,
                      wide ? 112 : 72,
                      wide ? 64 : 24,
                      wide ? 108 : 68,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Bring your business operations together.',
                            textAlign: TextAlign.center,
                            style: _v2Heading2.copyWith(
                              fontSize: wide ? 48 : 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: double.infinity,
                          child: Text(
                            'Manage products, customers, orders and your team — all in one place with Sello.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 16,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFFE4DCF8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _V2GlowButton(
                              label: 'Get started with Sello',
                              onPressed: onGetStarted,
                              height: 54,
                            ),
                            OutlinedButton(
                              onPressed: onTalk,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.04,
                                ),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.28),
                                ),
                                minimumSize: const Size(48, 54),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              child: const Text('Talk to our team'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClosingAtmospherePainter extends CustomPainter {
  const _ClosingAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.9, -1),
          end: Alignment(1, 1.1),
          colors: [Color(0xFF3A2078), Color(0xFF1A1034), Color(0xFF090212)],
          stops: [0, 0.52, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * -0.05),
      size.shortestSide * 0.42,
      Paint()
        ..color = const Color(0xFF7A5CFF).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 56),
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.95),
      size.width * 0.18,
      Paint()
        ..color = const Color(0xFF4A2E9A).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * -0.02, size.height * 0.78)
        ..cubicTo(
          size.width * 0.22,
          size.height * 0.42,
          size.width * 0.48,
          size.height * 0.98,
          size.width * 1.02,
          size.height * 0.58,
        ),
      ribbon,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.04, size.height * 0.9)
        ..cubicTo(
          size.width * 0.3,
          size.height * 0.62,
          size.width * 0.62,
          size.height * 1.05,
          size.width * 0.98,
          size.height * 0.72,
        ),
      ribbon..color = Colors.white.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _ClosingAtmospherePainter oldDelegate) => false;
}

class _V2Footer extends StatelessWidget {
  const _V2Footer({
    required this.sectionKey,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onPricing,
    required this.onFaq,
    required this.onV1,
    required this.onSignIn,
    required this.onEmail,
    required this.onPhone,
    required this.onOpen,
    required this.email,
    required this.phoneLabel,
  });

  final Key sectionKey;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onPricing;
  final VoidCallback onFaq;
  final VoidCallback onV1;
  final VoidCallback onSignIn;
  final VoidCallback onEmail;
  final VoidCallback onPhone;
  final Future<void> Function(String uri) onOpen;
  final String email;
  final String phoneLabel;

  @override
  Widget build(BuildContext context) {
    assert(
      onV1.hashCode >= 0 &&
          onSignIn.hashCode >= 0 &&
          onWorkflow.hashCode >= 0 &&
          onPricing.hashCode >= 0,
    );
    return ColoredBox(
      key: sectionKey,
      color: const Color(0xFF090212),
      child: _V2Shell(
        padding: const EdgeInsets.fromLTRB(0, 88, 0, 36),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final brand = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  AppAssets.wordmarkOnDark,
                  height: 36,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'Sello',
                ),
                const SizedBox(height: 16),
                const Text(
                  'A connected\nbusiness operations platform\nfor product businesses.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    height: 1.65,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFB7B0C8),
                  ),
                ),
              ],
            );
            final socials = _FooterSocials(onOpen: onOpen);
            final explore = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FooterLabel('Explore'),
                _FooterLink(label: 'Features', onPressed: onFeatures),
                _FooterLink(label: 'How it works', onPressed: onWorkflow),
                _FooterLink(label: 'Pricing', onPressed: onPricing),
                _FooterLink(label: 'FAQ', onPressed: onFaq),
              ],
            );
            final contact = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FooterLabel('Contact'),
                const _FooterLine('Sello by Unitech Solutions'),
                _FooterLink(label: email, onPressed: onEmail),
                _FooterLink(label: phoneLabel, onPressed: onPhone),
                const _FooterLine('207 Saranankara Road, Dehiwala.'),
              ],
            );
            final columns = stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brand,
                      const SizedBox(height: 20),
                      socials,
                      const SizedBox(height: 40),
                      explore,
                      const SizedBox(height: 40),
                      contact,
                    ],
                  )
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Stack(
                            children: [
                              brand,
                              Positioned(left: 0, bottom: 0, child: socials),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(flex: 3, child: explore),
                        const SizedBox(width: 32),
                        Expanded(flex: 4, child: contact),
                      ],
                    ),
                  );
            return Column(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _v2Max * 8 / 12),
                    child: columns,
                  ),
                ),
                const SizedBox(height: 64),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                const SizedBox(height: 22),
                const Text(
                  '© 2026 Sello by Unitech Solutions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF8A849C),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FooterSocials extends StatelessWidget {
  const _FooterSocials({required this.onOpen});

  final Future<void> Function(String uri) onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _FooterLink.height,
      child: Row(
        children: [
          _FooterSocialButton(
            label: 'Facebook',
            onPressed: () => onOpen('https://facebook.com/unitechsolutions.pro'),
            painter: const _FacebookMarkPainter(),
          ),
          const SizedBox(width: 10),
          _FooterSocialButton(
            label: 'Instagram',
            onPressed: () =>
                onOpen('https://www.instagram.com/unitech_solutions_it'),
            painter: const _InstagramMarkPainter(),
          ),
          const SizedBox(width: 10),
          _FooterSocialButton(
            label: 'LinkedIn',
            onPressed: () =>
                onOpen('https://www.linkedin.com/company/unitech-solutions-it'),
            painter: const _LinkedInMarkPainter(),
          ),
        ],
      ),
    );
  }
}

class _FooterSocialButton extends StatelessWidget {
  const _FooterSocialButton({
    required this.label,
    required this.onPressed,
    required this.painter,
  });

  final String label;
  final VoidCallback onPressed;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        fixedSize: const Size(32, 32),
        minimumSize: const Size(32, 32),
        maximumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: const CircleBorder(),
      ),
      icon: CustomPaint(size: const Size(14, 14), painter: painter),
    );
  }
}

class _FooterLabel extends StatelessWidget {
  const _FooterLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: Color(0xFF8A849C),
        ),
      ),
    );
  }
}

class _FooterLine extends StatelessWidget {
  const _FooterLine(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _FooterLink.height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: _FooterLink.textStyle),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  static const height = 40.0;
  static const textStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: Color(0xFFE6E1F4),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFC9C3D6),
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            alignment: Alignment.centerLeft,
            overlayColor: Colors.transparent,
            textStyle: textStyle.copyWith(color: const Color(0xFFC9C3D6)),
          ).copyWith(splashFactory: NoSplash.splashFactory),
          child: Text(label),
        ),
      ),
    );
  }
}

class _V2Intro extends StatelessWidget {
  const _V2Intro({
    required this.title,
    required this.body,
    this.center = false,
  });

  final String title;
  final String body;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: _v2Heading2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              height: 1.5,
              color: Color(0xFFC9C2E4),
            ),
          ),
        ],
      ),
    );
  }
}

class _V2ContactDialog extends StatelessWidget {
  const _V2ContactDialog({
    required this.email,
    required this.phoneLabel,
    required this.phoneUri,
    required this.onOpen,
  });

  final String email;
  final String phoneLabel;
  final String phoneUri;
  final Future<void> Function(String uri) onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const ColoredBox(color: Color(0x8A090212)),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xD01A1230),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 40,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 22, 26),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.of(context).pop(),
                                style: IconButton.styleFrom(
                                  foregroundColor: const Color(0xFFE6E1F4),
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ),
                            const Icon(
                              Icons.waving_hand_rounded,
                              color: Color(0xFFC4B0FF),
                              size: 28,
                            ),
                            const SizedBox(height: 18),
                            const Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 34,
                                  height: 1.12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.6,
                                  color: Colors.white,
                                ),
                                children: [
                                  TextSpan(
                                    text: "Let's get your\nbusiness on ",
                                  ),
                                  TextSpan(
                                    text: 'Sello.',
                                    style: TextStyle(color: Color(0xFFC4B0FF)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "We'd love to walk you through it in person. Reach out and we'll find a time that works — no pressure, and no long calls unless you want one.",
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 15,
                                height: 1.5,
                                color: Color(0xFFC9C2D8),
                              ),
                            ),
                            const SizedBox(height: 22),
                            _ContactRow(
                              icon: Icons.mail_outline_rounded,
                              tint: const Color(0xFFC4B0FF),
                              label: 'Drop us a line',
                              value: email,
                              onTap: () => onOpen('mailto:$email'),
                            ),
                            const SizedBox(height: 10),
                            _ContactRow(
                              icon: Icons.call_outlined,
                              tint: const Color(0xFFD4C6FF),
                              label: 'Give us a call',
                              value: phoneLabel,
                              onTap: () => onOpen(phoneUri),
                            ),
                            const SizedBox(height: 10),
                            _ContactRow(
                              icon: Icons.place_outlined,
                              tint: const Color(0xFFB9A6FF),
                              label: 'Visit us',
                              value: '207 Saranankara Road, Dehiwala',
                              onTap: () => onOpen(
                                'https://maps.google.com/?q=207+Saranankara+Road,+Dehiwala',
                              ),
                            ),
                            const SizedBox(height: 18),
                            Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "We're a small team — you'll talk to a real person who knows product businesses.\nWe'll get back to you quickly.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 13,
                                height: 1.5,
                                color: Color(0xFFA79FBA),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.1,
                        color: Color(0xFF9A93AD),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
