import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/animations/app_durations.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/marketing/presentation/marketing_previews.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public Sello website. Uses the product brand only — never a tenant theme.
class MarketingHomePage extends StatefulWidget {
  const MarketingHomePage({super.key});

  @override
  State<MarketingHomePage> createState() => _MarketingHomePageState();
}

class _MarketingHomePageState extends State<MarketingHomePage> {
  final _scroll = ScrollController();
  final _overviewKey = GlobalKey();
  final _featuresKey = GlobalKey();
  final _workflowKey = GlobalKey();
  final _teamsKey = GlobalKey();
  final _contactKey = GlobalKey();
  bool _scrolled = false;
  bool _menuOpen = false;

  static const _email = 'sello@cashro.pro';
  static const _phoneLabel = '+94 76 564 4465';
  static const _phoneUri = 'tel:+94765644465';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final next = _scroll.offset > 4;
      if (next != _scrolled && mounted) setState(() => _scrolled = next);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _signIn() => context.go(RoutePaths.login);

  void _getStarted() => context.go(RoutePaths.onboarding);

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
    final parsed = Uri.parse(uri);
    await launchUrl(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return Title(
      title: 'Sello — Business Operations Management Platform',
      color: AppColors.primary,
      child: Theme(
        data: AppTheme.light,
        child: Scaffold(
          backgroundColor: _audienceCanvas,
          body: Column(
            children: [
              if (_scrolled)
                _NavBar(
                  scrolled: _scrolled,
                  menuOpen: _menuOpen,
                  onToggleMenu: () => setState(() => _menuOpen = !_menuOpen),
                  onOverview: () => _scrollTo(_overviewKey),
                  onFeatures: () => _scrollTo(_featuresKey),
                  onWorkflow: () => _scrollTo(_workflowKey),
                  onTeams: () => _scrollTo(_teamsKey),
                  onContact: () => _scrollTo(_contactKey),
                  onSignIn: _signIn,
                  onGetStarted: _getStarted,
                ),
              AnimatedSwitcher(
                duration: motion ? AppDurations.normal : Duration.zero,
                child: _scrolled && _menuOpen
                    ? _MobileMenu(
                        key: const ValueKey('menu'),
                        onOverview: () => _scrollTo(_overviewKey),
                        onFeatures: () => _scrollTo(_featuresKey),
                        onWorkflow: () => _scrollTo(_workflowKey),
                        onTeams: () => _scrollTo(_teamsKey),
                        onContact: () => _scrollTo(_contactKey),
                        onSignIn: _signIn,
                        onGetStarted: _getStarted,
                      )
                    : const SizedBox(
                        key: ValueKey('closed'),
                        width: 0,
                        height: 0,
                      ),
              ),
              Expanded(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Hero(
                          sectionKey: _overviewKey,
                          menuOpen: _menuOpen,
                          onToggleMenu: () =>
                              setState(() => _menuOpen = !_menuOpen),
                          onOverview: () => _scrollTo(_overviewKey),
                          onFeatures: () => _scrollTo(_featuresKey),
                          onWorkflow: () => _scrollTo(_workflowKey),
                          onTeams: () => _scrollTo(_teamsKey),
                          onContact: () => _scrollTo(_contactKey),
                          onGetStarted: _getStarted,
                          onSignIn: _signIn,
                        ),
                        const _Audience(),
                        _Capabilities(sectionKey: _featuresKey),
                        _Workflow(sectionKey: _workflowKey),
                        _Teams(sectionKey: _teamsKey),
                        const _Platforms(),
                        const _Visibility(),
                        _Faq(onGetStarted: _getStarted, onSignIn: _signIn),
                        _Closing(
                          onGetStarted: _getStarted,
                          onTalk: () => _open('mailto:$_email'),
                        ),
                        _Footer(
                          sectionKey: _contactKey,
                          onOverview: () => _scrollTo(_overviewKey),
                          onFeatures: () => _scrollTo(_featuresKey),
                          onWorkflow: () => _scrollTo(_workflowKey),
                          onTeams: () => _scrollTo(_teamsKey),
                          onSignIn: _signIn,
                          onEmail: () => _open('mailto:$_email'),
                          onPhone: () => _open(_phoneUri),
                          email: _email,
                          phoneLabel: _phoneLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _pageMaxWidth = 1280;
const Color _audienceCanvas = Color(0xFFF3F1FB);

double _pageGutter(double width) {
  if (width < 640) return 20;
  if (width < 1100) return 32;
  return 40;
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.scrolled,
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onOverview,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onTeams,
    required this.onContact,
    required this.onSignIn,
    required this.onGetStarted,
  });

  final bool scrolled;
  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onOverview;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onTeams;
  final VoidCallback onContact;
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scrolled ? AppColors.surface : const Color(0xFFF7F6FC),
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scrolled ? AppColors.outlinePanel : Colors.transparent,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final showSignIn = constraints.maxWidth >= 560;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _pageGutter(constraints.maxWidth),
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      _LogoButton(onPressed: onOverview),
                      if (wide) ...[
                        const Spacer(),
                        _NavLink(label: 'Overview', onPressed: onOverview),
                        _NavLink(label: 'Features', onPressed: onFeatures),
                        _NavLink(label: 'How it works', onPressed: onWorkflow),
                        _NavLink(label: 'Teams', onPressed: onTeams),
                        _NavLink(label: 'Contact', onPressed: onContact),
                        const SizedBox(width: 12),
                      ] else
                        const Spacer(),
                      if (showSignIn)
                        TextButton(
                          onPressed: onSignIn,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            minimumSize: const Size(48, 44),
                            textStyle: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          child: const Text('Sign in'),
                        ),
                      if (wide) ...[
                        const SizedBox(width: 4),
                        SelloButton(
                          label: 'Get started',
                          onPressed: onGetStarted,
                        ),
                      ],
                      if (!wide)
                        IconButton(
                          tooltip: menuOpen ? 'Close menu' : 'Open menu',
                          onPressed: onToggleMenu,
                          icon: Icon(
                            menuOpen ? Icons.close_rounded : Icons.menu_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MobileMenu extends StatelessWidget {
  const _MobileMenu({
    super.key,
    required this.onOverview,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onTeams,
    required this.onContact,
    required this.onSignIn,
    required this.onGetStarted,
  });

  final VoidCallback onOverview;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onTeams;
  final VoidCallback onContact;
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: Column(
          children: [
            _MenuRow(label: 'Overview', onPressed: onOverview),
            _MenuRow(label: 'Features', onPressed: onFeatures),
            _MenuRow(label: 'How it works', onPressed: onWorkflow),
            _MenuRow(label: 'Teams', onPressed: onTeams),
            _MenuRow(label: 'Contact', onPressed: onContact),
            const SizedBox(height: 8),
            SelloButton(
              label: 'Sign in',
              variant: SelloButtonVariant.outline,
              expanded: true,
              size: SelloButtonSize.large,
              onPressed: onSignIn,
            ),
            const SizedBox(height: 8),
            SelloButton(
              label: 'Get started',
              expanded: true,
              size: SelloButtonSize.large,
              onPressed: onGetStarted,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: AppColors.textPrimary,
          textStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.label,
    required this.onPressed,
    this.foreground = AppColors.textSecondary,
  });

  final String label;
  final VoidCallback onPressed;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      child: Text(label),
    );
  }
}

class _LogoButton extends StatelessWidget {
  const _LogoButton({required this.onPressed, this.light = false});

  final VoidCallback onPressed;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: AppRadius.controlAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                AppAssets.logo,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                semanticLabel: 'Sello',
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Sello',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: light ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.sectionKey,
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onOverview,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onTeams,
    required this.onContact,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final Key sectionKey;
  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onOverview;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onTeams;
  final VoidCallback onContact;
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  static const _links = [
    ('Overview', 0),
    ('Features', 1),
    ('How it works', 2),
    ('Teams', 3),
    ('Contact', 4),
  ];

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      key: sectionKey,
      constraints: BoxConstraints(minHeight: viewport),
      child: ColoredBox(
        color: _audienceCanvas,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final compact = constraints.maxWidth < 700;
              final sideBySide = wide;
              final radius = BorderRadius.circular(compact ? 24 : 32);
              final heroBody = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!sideBySide) ...[
                    _HeroNav(
                      wide: wide,
                      showSignIn: constraints.maxWidth >= 560,
                      menuOpen: menuOpen,
                      onToggleMenu: onToggleMenu,
                      onOverview: onOverview,
                      onFeatures: onFeatures,
                      onWorkflow: onWorkflow,
                      onTeams: onTeams,
                      onContact: onContact,
                      onSignIn: onSignIn,
                      onGetStarted: onGetStarted,
                    ),
                    if (menuOpen) ...[
                      const SizedBox(height: 8),
                      _HeroMenuLinks(
                        onOverview: onOverview,
                        onFeatures: onFeatures,
                        onWorkflow: onWorkflow,
                        onTeams: onTeams,
                        onContact: onContact,
                      ),
                    ],
                    SizedBox(height: compact ? 40 : 56),
                  ],
                  if (sideBySide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _Reveal(
                            child: _HeroCopy(
                              compact: false,
                              alignStart: true,
                              onGetStarted: onGetStarted,
                              onSignIn: onSignIn,
                            ),
                          ),
                        ),
                        const SizedBox(width: 36),
                        const Expanded(
                          flex: 6,
                          child: _Reveal(child: MarketingShowcase()),
                        ),
                      ],
                    )
                  else ...[
                    _Reveal(
                      child: _HeroCopy(
                        compact: compact,
                        onGetStarted: onGetStarted,
                        onSignIn: onSignIn,
                      ),
                    ),
                    SizedBox(height: compact ? 36 : 48),
                    const _Reveal(child: MarketingShowcase()),
                  ],
                ],
              );
              return Container(
                constraints: BoxConstraints(minHeight: viewport - 32),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: const LinearGradient(
                    begin: Alignment(-1, -0.4),
                    end: Alignment(1.05, 1),
                    colors: [
                      Color(0xFF10091F),
                      Color(0xFF1C0E42),
                      Color(0xFF4A2A96),
                      Color(0xFF2A3B92),
                    ],
                    stops: [0, 0.32, 0.68, 1],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1A1038).withValues(alpha: 0.28),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: sideBySide
                      ? Alignment.center
                      : Alignment.topCenter,
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(painter: _HeroGridPainter()),
                    ),
                    const Positioned(
                      top: -160,
                      right: -80,
                      child: _HeroGlow(
                        size: 520,
                        colors: [Color(0xCC7A45F5), Color(0x007A45F5)],
                      ),
                    ),
                    const Positioned(
                      right: -40,
                      bottom: -180,
                      child: _HeroGlow(
                        size: 460,
                        colors: [Color(0x993A4EDB), Color(0x003A4EDB)],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 18 : 32,
                        sideBySide ? 96 : (compact ? 14 : 22),
                        compact ? 18 : 32,
                        compact ? 28 : 40,
                      ),
                      child: heroBody,
                    ),
                    if (sideBySide)
                      Positioned(
                        top: 22,
                        left: 32,
                        right: 32,
                        child: _HeroNav(
                          wide: wide,
                          showSignIn: constraints.maxWidth >= 560,
                          menuOpen: menuOpen,
                          onToggleMenu: onToggleMenu,
                          onOverview: onOverview,
                          onFeatures: onFeatures,
                          onWorkflow: onWorkflow,
                          onTeams: onTeams,
                          onContact: onContact,
                          onSignIn: onSignIn,
                          onGetStarted: onGetStarted,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroNav extends StatelessWidget {
  const _HeroNav({
    required this.wide,
    required this.showSignIn,
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onOverview,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onTeams,
    required this.onContact,
    required this.onSignIn,
    required this.onGetStarted,
  });

  final bool wide;
  final bool showSignIn;
  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onOverview;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onTeams;
  final VoidCallback onContact;
  final VoidCallback onSignIn;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    const linkColor = Color(0xFFE7E2F6);
    return Row(
      children: [
        _LogoButton(onPressed: onOverview, light: true),
        if (wide) ...[
          const SizedBox(width: 8),
          _NavLink(
            label: 'Overview',
            onPressed: onOverview,
            foreground: linkColor,
          ),
          _NavLink(
            label: 'Features',
            onPressed: onFeatures,
            foreground: linkColor,
          ),
          _NavLink(
            label: 'How it works',
            onPressed: onWorkflow,
            foreground: linkColor,
          ),
          _NavLink(label: 'Teams', onPressed: onTeams, foreground: linkColor),
          _NavLink(
            label: 'Contact',
            onPressed: onContact,
            foreground: linkColor,
          ),
          const Spacer(),
          if (showSignIn)
            TextButton(
              onPressed: onSignIn,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 44),
                textStyle: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: const Text('Sign in'),
            ),
          const SizedBox(width: 8),
          _HeroPillButton(
            label: 'Get started',
            filled: true,
            onPressed: onGetStarted,
          ),
        ] else ...[
          const Spacer(),
          IconButton(
            tooltip: menuOpen ? 'Close menu' : 'Open menu',
            color: Colors.white,
            onPressed: onToggleMenu,
            icon: Icon(menuOpen ? Icons.close_rounded : Icons.menu_rounded),
          ),
        ],
      ],
    );
  }
}

class _HeroMenuLinks extends StatelessWidget {
  const _HeroMenuLinks({
    required this.onOverview,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onTeams,
    required this.onContact,
  });

  final VoidCallback onOverview;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onTeams;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final actions = [onOverview, onFeatures, onWorkflow, onTeams, onContact];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _Hero._links.length; i++)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: actions[i],
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 44),
                alignment: Alignment.centerLeft,
                textStyle: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(_Hero._links[i].$1),
            ),
          ),
      ],
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.compact,
    required this.onGetStarted,
    required this.onSignIn,
    this.alignStart = false,
  });

  final bool compact;
  final bool alignStart;
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final align = alignStart ? TextAlign.start : TextAlign.center;
    return Column(
      crossAxisAlignment: alignStart
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: const Text(
            'Manage. Sell. Collect. Grow.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF3F0FF),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Semantics(
          header: true,
          child: Text(
            compact
                ? 'Run your business operations in one place.'
                : 'Run your business operations\nin one place.',
            textAlign: align,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: compact ? 36 : (alignStart ? 46 : 60),
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: compact ? -1 : -1.6,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Bring orders, inventory, customers, payments, invoicing and your team together. Everything you need to manage your day-to-day operations, connected in one platform.',
            textAlign: align,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: compact ? 16 : 17,
              height: 1.55,
              color: const Color(0xFFD9D3EE),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            _HeroPillButton(
              label: 'Get started',
              filled: true,
              onPressed: onGetStarted,
            ),
            _HeroPillButton(
              label: 'Sign in',
              filled: false,
              onPressed: onSignIn,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroPillButton extends StatelessWidget {
  const _HeroPillButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        boxShadow: filled
            ? const [
                BoxShadow(
                  color: Color(0x997A5CFF),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7357F6),
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 46),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 46),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              child: Text(label),
            ),
    );
  }
}

class _HeroGlow extends StatelessWidget {
  const _HeroGlow({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class _HeroGridPainter extends CustomPainter {
  const _HeroGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 64.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Capabilities extends StatelessWidget {
  const _Capabilities({required this.sectionKey});

  final Key sectionKey;

  static const _items = [
    (
      Icons.receipt_long_rounded,
      AppColors.primary,
      AppColors.primaryContainer,
      'Sales & Orders',
      'Create orders, track their progress and manage fulfilment.',
    ),
    (
      Icons.inventory_2_outlined,
      AppColors.inventory,
      AppColors.inventorySoft,
      'Products & Inventory',
      'Manage products, stock levels, product options and inventory movements.',
    ),
    (
      Icons.people_outline_rounded,
      AppColors.info,
      AppColors.infoContainer,
      'Customers & Suppliers',
      'Organise customer and supplier information, relationships and transaction histories.',
    ),
    (
      Icons.payments_outlined,
      AppColors.finance,
      AppColors.financeSoft,
      'Payments & Financial Tracking',
      'Record collections, manage outstanding balances, credit and cheque-related transactions.',
    ),
    (
      Icons.groups_outlined,
      AppColors.success,
      AppColors.successContainer,
      'Team & Operations',
      'Manage team members, customer visits and the day\'s schedule.',
    ),
  ];

  static const _support = [
    (
      Icons.description_outlined,
      'Invoicing',
      'Create and share invoices from submitted orders.',
    ),
    (
      Icons.forum_outlined,
      'Notifications',
      'SMS, and WhatsApp sharing from the device, when those channels are set up.',
    ),
    (
      Icons.bar_chart_rounded,
      'Reporting',
      'Sales, orders, collections, stock and visit reports.',
    ),
    (
      Icons.history_rounded,
      'Customer history',
      'Profiles, purchases and what each customer still owes.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: _Section(
        sectionKey: sectionKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionIntro(
              title: 'One connected platform, not a pile of separate tools.',
              body:
                  'Orders, stock, customers, collections and the people doing the work stay in the same system.',
            ),
            const SizedBox(height: 36),
            LayoutBuilder(
              builder: (context, constraints) {
                Widget card(
                  int index, {
                  Widget? detail,
                  bool featured = false,
                }) {
                  final item = _items[index];
                  return _FeatureCard(
                    icon: item.$1,
                    iconColor: item.$2,
                    tint: item.$3,
                    title: item.$4,
                    body: item.$5,
                    featured: featured,
                    detail: detail,
                  );
                }

                final sales = card(
                  0,
                  featured: true,
                  detail: const _LabelRow(
                    labels: ['Placed', 'Draft', 'Completed'],
                  ),
                );
                final products = card(
                  1,
                  featured: true,
                  detail: const _LabelRow(
                    labels: ['On hand', 'Reserved', 'Available'],
                  ),
                );
                final rest = [for (var i = 2; i < _items.length; i++) card(i)];
                if (constraints.maxWidth >= 980) {
                  return Column(
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: sales),
                            const SizedBox(width: 16),
                            Expanded(child: products),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < rest.length; i++) ...[
                              if (i > 0) const SizedBox(width: 16),
                              Expanded(child: rest[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }
                final columns = constraints.maxWidth >= 680 ? 2 : 1;
                return _CardGrid(
                  columns: columns,
                  children: [sales, products, ...rest],
                );
              },
            ),
            const SizedBox(height: 18),
            const _SupportRow(),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.title,
    required this.body,
    this.featured = false,
    this.detail,
  });

  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String title;
  final String body;
  final bool featured;
  final Widget? detail;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: motion ? AppDurations.fast : Duration.zero,
        curve: AppCurves.standard,
        padding: EdgeInsets.all(widget.featured ? 24 : 20),
        transform: Matrix4.translationValues(0, _hover && motion ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardAll,
          border: Border.all(
            color: _hover ? AppColors.lavender : AppColors.outlinePanel,
          ),
          boxShadow: _hover ? AppShadows.level2 : AppShadows.panel,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: widget.featured ? 48 : 40,
              height: widget.featured ? 48 : 40,
              decoration: BoxDecoration(
                color: widget.tint,
                borderRadius: AppRadius.controlAll,
              ),
              child: Icon(
                widget.icon,
                color: widget.iconColor,
                size: widget.featured ? 24 : 20,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                widget.title,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: widget.featured ? 20 : 16,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 15,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (widget.detail != null) ...[
              const SizedBox(height: 20),
              widget.detail!,
            ],
          ],
        ),
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.outlinePanel),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        final items = [
          for (final item in _Capabilities._support)
            _SupportItem(icon: item.$1, title: item.$2, body: item.$3),
        ];
        final panel = DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7FD),
            borderRadius: AppRadius.panelAll,
            border: Border.all(color: AppColors.outlinePanel),
          ),
          child: stacked
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          const Divider(
                            height: 20,
                            color: AppColors.outlineSubtle,
                          ),
                        items[i],
                      ],
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 20,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: items[i],
                          ),
                        ),
                    ],
                  ),
                ),
        );
        return panel;
      },
    );
  }
}

class _SupportItem extends StatelessWidget {
  const _SupportItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.brandIndigo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Audience extends StatelessWidget {
  const _Audience();

  static const _groups = [
    (
      Icons.local_shipping_outlined,
      AppColors.primaryContainer,
      AppColors.brandIndigo,
      'Wholesale & Distribution',
      'Manage customer orders, stock, deliveries and collections.',
    ),
    (
      Icons.storefront_outlined,
      AppColors.infoContainer,
      AppColors.info,
      'Retail Businesses',
      'Keep products, inventory, customers and sales organised.',
    ),
    (
      Icons.swap_horiz_rounded,
      AppColors.financeSoft,
      AppColors.finance,
      'Trading Businesses',
      'Manage product catalogues, customer accounts and transactions.',
    ),
    (
      Icons.inventory_rounded,
      AppColors.inventorySoft,
      AppColors.inventory,
      'Product-Based Businesses',
      'Simplify order processing and everyday operations.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF3F1FB),
      child: _Section(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionIntro(
              title: 'One platform for businesses that sell, supply and grow.',
              body:
                  'Sello supports businesses that manage products, customer orders, inventory and collections every day.',
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 980
                    ? 4
                    : constraints.maxWidth >= 640
                    ? 2
                    : 1;
                final tiles = [
                  for (final group in _groups)
                    _AudienceTile(
                      icon: group.$1,
                      tint: group.$2,
                      iconColor: group.$3,
                      title: group.$4,
                      body: group.$5,
                    ),
                ];
                return _CardGrid(columns: columns, children: tiles);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceTile extends StatefulWidget {
  const _AudienceTile({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String title;
  final String body;

  @override
  State<_AudienceTile> createState() => _AudienceTileState();
}

class _AudienceTileState extends State<_AudienceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: motion ? AppDurations.fast : Duration.zero,
        curve: AppCurves.standard,
        transform: Matrix4.translationValues(0, _hover && motion ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardAll,
          border: Border.all(
            color: _hover ? AppColors.lavender : AppColors.outlinePanel,
          ),
          boxShadow: _hover ? AppShadows.level2 : AppShadows.level1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 88,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [widget.tint, AppColors.surface],
                ),
              ),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.controlAll,
                  border: Border.all(color: AppColors.outlinePanel),
                ),
                child: Icon(widget.icon, size: 22, color: widget.iconColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.body,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatefulWidget {
  const _Faq({required this.onGetStarted, required this.onSignIn});

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  int? _open = 0;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      (
        'What types of businesses can use Sello?',
        'Sello is for businesses that sell, supply or trade physical products, including wholesale, distribution, retail and trading. It is one operations platform, not a specialised system for a single industry.',
      ),
      (
        'Can I access Sello from my computer and mobile?',
        'Yes. Use the Windows desktop app, the web app in a browser, or the Android app for sales visits, orders and collections.',
      ),
      (
        'Can multiple employees use one business account?',
        'Yes. An owner can add team members as Manager, Store In-charge or Sales Representative. Each person signs in with their own account, and what they can open depends on that role.',
      ),
      (
        'Can I manage multiple branches?',
        'Sello organises stock and people around a branch. A new business starts with a Head Office. Creating and managing additional branches in the product is not available yet.',
      ),
      (
        'Can I track customer payments and outstanding balances?',
        'Yes. You can record collections, including cheque-related transactions, and see what a customer still owes.',
      ),
      (
        'Can I generate and share invoices?',
        'Yes. Once an order is submitted, you can share an invoice by a document link. SMS can be sent when it is set up, and WhatsApp can be shared from the device.',
      ),
      (
        'How is my business data protected?',
        'People sign in with their own account. Each business’s records stay in that company’s workspace, and a person’s access follows their role. This public website does not show customer information.',
      ),
      (
        'How can I get started with Sello?',
        'Choose Get started and use the email address that was invited. New businesses join by invitation. If you already have an account, sign in.',
      ),
    ];

    return ColoredBox(
      color: AppColors.surface,
      child: _Section(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionIntro(
              title: 'Questions about Sello?',
              body: 'Straight answers about who Sello is for and how to begin.',
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < items.length; i++)
              _FaqItem(
                question: items[i].$1,
                answer: items[i].$2,
                expanded: _open == i,
                onToggle: () => setState(() => _open = _open == i ? null : i),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: widget.onGetStarted,
                  child: const Text('Get started'),
                ),
                TextButton(
                  onPressed: widget.onSignIn,
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 6),
                minimumSize: const Size.fromHeight(60),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      question,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 17,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: motion ? AppDurations.fast : Duration.zero,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.brandIndigo,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: motion ? AppDurations.normal : Duration.zero,
            curve: AppCurves.standard,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 18, right: 36),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        answer,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 15.5,
                          height: 1.55,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Workflow extends StatelessWidget {
  const _Workflow({required this.sectionKey});

  final Key sectionKey;

  static const _steps = [
    (
      Icons.inventory_2_outlined,
      'Set up your products',
      'Organise your catalogue, pricing and available stock.',
    ),
    (
      Icons.add_shopping_cart_outlined,
      'Manage customer orders',
      'Create orders and capture what the customer needs.',
    ),
    (
      Icons.local_shipping_outlined,
      'Process and fulfil',
      'Track order progress and delivery.',
    ),
    (
      Icons.payments_outlined,
      'Record collections',
      'Manage payments, credit and outstanding balances.',
    ),
    (
      Icons.description_outlined,
      'Create invoices',
      'Generate and share invoices and order documents.',
    ),
    (
      Icons.forum_outlined,
      'Stay connected',
      'Update your team and customers through SMS or WhatsApp sharing.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.navRail),
      child: _Section(
        sectionKey: sectionKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionIntro(
              light: true,
              title: 'From customer order to successful collection.',
              body:
                  'Sello connects everyday business activities, so products, orders, payments and customer updates stay part of the same workflow.',
            ),
            const SizedBox(height: 40),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 680) {
                  return Column(
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        _WorkflowStep(
                          index: i + 1,
                          icon: _steps[i].$1,
                          title: _steps[i].$2,
                          label: _steps[i].$3,
                          vertical: true,
                          last: i == _steps.length - 1,
                        ),
                    ],
                  );
                }
                final columns = constraints.maxWidth >= 1040 ? 3 : 2;
                return Column(
                  children: [
                    for (var start = 0; start < _steps.length; start += columns)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: start + columns < _steps.length ? 28 : 0,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var i = start;
                              i < start + columns && i < _steps.length;
                              i++
                            )
                              Expanded(
                                child: _WorkflowStep(
                                  index: i + 1,
                                  icon: _steps[i].$1,
                                  title: _steps[i].$2,
                                  label: _steps[i].$3,
                                  vertical: false,
                                  last:
                                      i == start + columns - 1 ||
                                      i == _steps.length - 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.label,
    required this.vertical,
    required this.last,
  });

  final int index;
  final IconData icon;
  final String title;
  final String label;
  final bool vertical;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final marker = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: Text(
        index.toString().padLeft(2, '0'),
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.lavender, size: 20),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            height: 1.45,
            color: Color(0xFFE4DFFF),
          ),
        ),
      ],
    );

    if (vertical) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                marker,
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 22),
                child: copy,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              marker,
              if (!last)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 8),
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          copy,
        ],
      ),
    );
  }
}

class _Teams extends StatelessWidget {
  const _Teams({required this.sectionKey});

  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: _Section(
        sectionKey: sectionKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionIntro(
              title: 'Your entire team, working in sync.',
              body:
                  'Give everyone the access and tools they need to do their job, while keeping business operations connected.',
            ),
            const SizedBox(height: 28),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 980
                    ? 4
                    : constraints.maxWidth >= 680
                    ? 2
                    : 1;
                return _CardGrid(
                  columns: columns,
                  children: const [
                    _RoleCard(
                      index: '01',
                      icon: Icons.apartment_rounded,
                      accent: AppColors.primary,
                      title: 'Owner',
                      body: 'Business-wide control and visibility.',
                    ),
                    _RoleCard(
                      index: '02',
                      icon: Icons.insights_outlined,
                      accent: AppColors.info,
                      title: 'Manager',
                      body: 'Operational oversight and performance.',
                    ),
                    _RoleCard(
                      index: '03',
                      icon: Icons.storefront_outlined,
                      accent: AppColors.inventory,
                      title: 'Store In-charge',
                      body: 'Daily sales and inventory responsibilities.',
                    ),
                    _RoleCard(
                      index: '04',
                      icon: Icons.route_outlined,
                      accent: AppColors.finance,
                      title: 'Sales Representative',
                      body: 'Customer visits, order taking and collections.',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.index,
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
  });

  final String index;
  final IconData icon;
  final Color accent;
  final String title;
  final String body;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: motion ? AppDurations.fast : Duration.zero,
        curve: AppCurves.standard,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        transform: Matrix4.translationValues(0, _hover && motion ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardAll,
          border: Border.all(
            color: _hover
                ? widget.accent.withValues(alpha: 0.45)
                : AppColors.outlinePanel,
          ),
          boxShadow: _hover ? AppShadows.level2 : AppShadows.panel,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.12),
                    borderRadius: AppRadius.controlAll,
                  ),
                  child: Icon(widget.icon, color: widget.accent, size: 20),
                ),
                const Spacer(),
                Text(
                  widget.index,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.body,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Platforms extends StatelessWidget {
  const _Platforms();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF1EEFB),
      child: _Section(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionIntro(
              title: 'Your business, wherever work takes you.',
              body:
                  'Use Sello in the office, through your browser or with your sales team on the move.',
            ),
            const SizedBox(height: 36),
            LayoutBuilder(
              builder: (context, constraints) {
                const desktop = _PlaceCard(
                  index: '01',
                  icon: Icons.desktop_windows_outlined,
                  title: 'Desktop App',
                  where: 'In the office',
                  body:
                      'The Windows application for everyday office operations.',
                );
                const web = _PlaceCard(
                  index: '02',
                  icon: Icons.language_rounded,
                  title: 'Web App',
                  where: 'In the browser',
                  body:
                      'Access your business through a secure, browser-based experience.',
                );
                const mobile = _PlaceCard(
                  index: '03',
                  icon: Icons.smartphone_rounded,
                  title: 'Mobile App',
                  where: 'On the move',
                  body:
                      'Support sales visits, customer orders and collections while on the move.',
                );
                if (constraints.maxWidth < 860) {
                  return const Column(
                    children: [
                      desktop,
                      SizedBox(height: 16),
                      web,
                      SizedBox(height: 16),
                      mobile,
                    ],
                  );
                }
                return const IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: desktop),
                      SizedBox(width: 18),
                      Expanded(child: web),
                      SizedBox(width: 18),
                      Expanded(child: mobile),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceCard extends StatefulWidget {
  const _PlaceCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.where,
    required this.body,
  });

  final String index;
  final IconData icon;
  final String title;
  final String where;
  final String body;

  @override
  State<_PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<_PlaceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: motion ? AppDurations.fast : Duration.zero,
        curve: AppCurves.standard,
        transform: Matrix4.translationValues(0, _hover && motion ? -3 : 0, 0),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardAll,
          border: Border.all(
            color: _hover ? AppColors.lavender : AppColors.outlinePanel,
          ),
          boxShadow: _hover ? AppShadows.level2 : AppShadows.panel,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppRadius.controlAll,
                  ),
                  child: Icon(
                    widget.icon,
                    color: AppColors.brandIndigo,
                    size: 26,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.index,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              widget.where,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.brandIndigo,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.body,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 15,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Visibility extends StatelessWidget {
  const _Visibility();

  static const _items = [
    (
      Icons.receipt_long_rounded,
      'Sales and orders',
      'See how sales and orders are progressing.',
    ),
    (
      Icons.account_balance_wallet_outlined,
      'Outstanding balances',
      'Identify what customers still owe.',
    ),
    (
      Icons.inventory_2_outlined,
      'Inventory',
      'Monitor stock and inventory movements.',
    ),
    (
      Icons.people_outline_rounded,
      'Customer activity',
      'Review what customers have been buying.',
    ),
    (
      Icons.groups_outlined,
      'Team work',
      'Understand visits and the work the team is doing.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: _Section(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;
            final copy = const _SectionIntro(
              title: 'A clearer picture of your business, every day.',
              body:
                  'Orders, stock, customers and collections stay connected, so the people running the business can see the work in one place.',
            );
            final board = Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.cardAll,
                border: Border.all(color: AppColors.outlinePanel),
                boxShadow: AppShadows.level2,
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      children: [
                        _FooterMark(),
                        SizedBox(width: 10),
                        Text(
                          'Workspace',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.outlineSubtle),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _items.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: AppRadius.iconAll,
                            ),
                            child: Icon(
                              _items[i].$1,
                              size: 18,
                              color: AppColors.brandIndigo,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _items[i].$2,
                                  style: const TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _items[i].$3,
                                  style: const TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [copy, const SizedBox(height: 24), board],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: _SectionIntro(
                    title: 'A clearer picture of your business, every day.',
                    body:
                        'Orders, stock, customers and collections stay connected, so the people running the business can see the work in one place.',
                  ),
                ),
                const SizedBox(width: 56),
                Expanded(flex: 6, child: board),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Closing extends StatelessWidget {
  const _Closing({required this.onGetStarted, required this.onTalk});

  final VoidCallback onGetStarted;
  final VoidCallback onTalk;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.navRail),
      child: _Section(
        padding: const EdgeInsets.symmetric(vertical: 96),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Semantics(
                header: true,
                child: Text(
                  'Your business deserves a better way to operate.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: MediaQuery.sizeOf(context).width < 640 ? 32 : 44,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                'Bring your products, customers, orders and team together with Sello.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 17,
                  height: 1.5,
                  color: Color(0xFFE4DFFF),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _LightButton(
                  label: 'Get started with Sello',
                  filled: true,
                  onPressed: onGetStarted,
                ),
                _LightButton(
                  label: 'Talk to our team',
                  filled: false,
                  onPressed: onTalk,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LightButton extends StatelessWidget {
  const _LightButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brandDeep,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonAll,
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x66FFFFFF)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonAll,
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              child: Text(label),
            ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.sectionKey,
    required this.onOverview,
    required this.onFeatures,
    required this.onWorkflow,
    required this.onTeams,
    required this.onSignIn,
    required this.onEmail,
    required this.onPhone,
    required this.email,
    required this.phoneLabel,
  });

  final Key sectionKey;
  final VoidCallback onOverview;
  final VoidCallback onFeatures;
  final VoidCallback onWorkflow;
  final VoidCallback onTeams;
  final VoidCallback onSignIn;
  final VoidCallback onEmail;
  final VoidCallback onPhone;
  final String email;
  final String phoneLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: sectionKey,
      color: const Color(0xFF16083F),
      child: _Section(
        fillViewport: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 800;
            final brand = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    _FooterMark(),
                    SizedBox(width: 10),
                    Text(
                      'Sello',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const SizedBox(
                  width: 320,
                  child: Text(
                    'A business operations platform for orders, inventory, customers, payments, invoicing, and teams.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFFD5CEF2),
                    ),
                  ),
                ),
              ],
            );
            final links = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FooterLabel('Website'),
                _FooterLink(label: 'Overview', onPressed: onOverview),
                _FooterLink(label: 'Features', onPressed: onFeatures),
                _FooterLink(label: 'How it works', onPressed: onWorkflow),
                _FooterLink(label: 'Teams', onPressed: onTeams),
                _FooterLink(label: 'Sign in', onPressed: onSignIn),
              ],
            );
            final contact = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FooterLabel('Contact'),
                const Text(
                  'Sello by Unitech Solutions',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                _FooterLink(label: email, onPressed: onEmail),
                _FooterLink(label: phoneLabel, onPressed: onPhone),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'sello.cashro.pro',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE6E1F8),
                    ),
                  ),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stacked)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      brand,
                      const SizedBox(height: 28),
                      links,
                      const SizedBox(height: 28),
                      contact,
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: brand),
                      Expanded(flex: 3, child: links),
                      Expanded(flex: 4, child: contact),
                    ],
                  ),
                const SizedBox(height: 32),
                const Divider(color: Color(0x33FFFFFF), height: 1),
                const SizedBox(height: 16),
                const Text(
                  '© 2026 Sello by Unitech Solutions',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: Color(0xFFB7AEDA),
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

class _FooterMark extends StatelessWidget {
  const _FooterMark();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        AppAssets.logo,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        semanticLabel: 'Sello',
      ),
    );
  }
}

class _FooterLabel extends StatelessWidget {
  const _FooterLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.lavender,
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFE6E1F8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          minimumSize: const Size(44, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
          textStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.title,
    required this.body,
    this.light = false,
  });

  final String title;
  final String body;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: wide ? 40 : 30,
                height: 1.12,
                fontWeight: FontWeight.w700,
                letterSpacing: wide ? -0.9 : -0.5,
                color: light ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              height: 1.5,
              color: light ? const Color(0xFFE4DFFF) : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    this.sectionKey,
    required this.child,
    this.padding,
    this.fillViewport = true,
  });

  final Key? sectionKey;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool fillViewport;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final content = Padding(
          key: sectionKey,
          padding:
              padding ?? EdgeInsets.symmetric(vertical: width < 700 ? 64 : 88),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _pageGutter(width)),
                child: child,
              ),
            ),
          ),
        );
        if (!fillViewport) return content;
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport),
          child: Center(child: content),
        );
      },
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = !MediaQuery.disableAnimationsOf(context);
    if (!motion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.slow,
      curve: AppCurves.standard,
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
