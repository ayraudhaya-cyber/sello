import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/marketing/presentation/marketing_v2_glass_icons.dart';

/// Light phone mock used in the hero, styled like a device screenshot.
class V2HeroShowcase extends StatelessWidget {
  const V2HeroShowcase({super.key, this.width = 286});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Illustrative Sello workspace. A desktop orders view with a phone in front.',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : width * 3;
            // Phone is 18:9 (tall). Desktop frame is 16:9 and overlaps it.
            var phoneW = width * 0.9;
            var desktopW = width * 1.85 * 1.1 * 1.15 * 1.1 * 1.1;
            var compositionW = desktopW + phoneW * 0.48;
            if (compositionW > maxW && maxW > 0) {
              final scale = maxW / compositionW;
              phoneW *= scale;
              desktopW *= scale;
              compositionW = maxW;
            }
            final phoneH = phoneW * 18 / 9;
            final desktopH = desktopW * 9 / 16;
            // Desktop bottom sits just above the phone bottom.
            final desktopTop = (phoneH - 20 - desktopH).clamp(0.0, phoneH);
            final stackH = desktopTop + desktopH > phoneH
                ? desktopTop + desktopH
                : phoneH;
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: compositionW,
                height: stackH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: desktopTop,
                      width: desktopW,
                      height: desktopH,
                      child: V2DashboardFrame(height: desktopH),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      width: phoneW,
                      height: phoneH,
                      child: _V2HeroPhone(width: phoneW),
                    ),
                    Positioned(
                      left: desktopW * 0.62,
                      top: desktopTop,
                      child: const FractionalTranslation(
                        translation: Offset(-0.5, -0.5),
                        child: _HeroGlassChip(
                          'Business Dashboard',
                          icon: Icons.space_dashboard_outlined,
                          kind: V2GlassIconKind.dashboard,
                        ),
                      ),
                    ),
                    Positioned(
                      left: desktopW * 0.5,
                      top: desktopTop + desktopH + 18,
                      child: const FractionalTranslation(
                        translation: Offset(-0.5, 0),
                        child: _HeroGlassChip(
                          'Sales Rep App',
                          icon: Icons.smartphone_outlined,
                          kind: V2GlassIconKind.phone,
                          phase: 0.34,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -64,
                      top: phoneH * 0.66,
                      child: const _HeroGlassChip(
                        'Stock & Orders',
                        icon: Icons.inventory_2_outlined,
                        kind: V2GlassIconKind.stock,
                        phase: 0.68,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroGlassChip extends StatefulWidget {
  const _HeroGlassChip(
    this.label, {
    required this.icon,
    required this.kind,
    this.phase = 0,
  });

  final String label;
  final IconData icon;
  final V2GlassIconKind kind;
  final double phase;

  @override
  State<_HeroGlassChip> createState() => _HeroGlassChipState();
}

class _HeroGlassChipState extends State<_HeroGlassChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.icon.codePoint > 0);
    final chip = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF120818).withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF241838).withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    V2GlassIcon(kind: widget.kind, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return chip;
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) {
        final t = (_float.value + widget.phase) % 1;
        final dy = math.sin(t * math.pi * 2) * 6;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: chip,
    );
  }
}

class _V2HeroPhone extends StatelessWidget {
  const _V2HeroPhone({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 18 / 9,
      child: Container(
        width: width,
        height: width * 18 / 9,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0C),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: const Color(0xFF2A2A30), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 40,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: ColoredBox(
            color: const Color(0xFFF7F6FB),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: Column(
                children: [
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 260,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '9:41',
                                  style: TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF16141F),
                                  ),
                                ),
                                Spacer(),
                                Icon(
                                  Icons.signal_cellular_alt,
                                  size: 13,
                                  color: Color(0xFF16141F),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.wifi_rounded,
                                  size: 14,
                                  color: Color(0xFF16141F),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.battery_full_rounded,
                                  size: 16,
                                  color: Color(0xFF16141F),
                                ),
                              ],
                            ),
                            SizedBox(height: 6),
                            _SalesRepHome(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 260,
                      child: Column(
                        children: [
                          _VisitShopBanner(),
                          SizedBox(height: 8),
                          _SalesNav(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesRepHome extends StatelessWidget {
  const _SalesRepHome();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.menu_rounded, size: 18, color: Color(0xFF1C1730)),
            Spacer(),
            _BellBadge(),
            SizedBox(width: 8),
            _InitialAvatar(initials: 'V', color: Color(0xFFE7E1F8)),
          ],
        ),
        SizedBox(height: 4),
        Text(
          'Collected Today',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: Color(0xFF8A849C),
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Rs 24,800',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: Color(0xFF16141F),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(99)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                'Rs 24,800  |  6 Orders  |  4 Visits',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 10,
                  color: Color(0xFF6E6880),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        _SalesField(
          icon: Icons.search_rounded,
          label: 'Search stores, customers, products...',
        ),
        SizedBox(height: 8),
        _SalesField(
          icon: Icons.location_on_outlined,
          label: 'Near: Colombo',
          trailing: Icons.keyboard_arrow_down_rounded,
        ),
        SizedBox(height: 10),
        _VisitProgressCard(),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Worth Visiting',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16141F),
                ),
              ),
            ),
            Text(
              'See all',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        _ShopRow(
          initials: 'CM',
          color: Color(0xFF5B8DEF),
          name: 'City Mart',
          detail: 'Not visited yet · Ordered 2 days ago',
        ),
        _ShopRow(
          initials: 'GL',
          color: Color(0xFF3CB489),
          name: 'Green Leaf',
          detail: 'Not visited yet · Ordered 4 days ago',
        ),
      ],
    );
  }
}

class _BellBadge extends StatelessWidget {
  const _BellBadge();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 18,
            color: Color(0xFF1C1730),
          ),
          Positioned(
            right: -2,
            top: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFE25B5B),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 12,
                height: 12,
                child: Center(
                  child: Text(
                    '2',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initials,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5B4B8A),
        ),
      ),
    );
  }
}

class _SalesField extends StatelessWidget {
  const _SalesField({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8A849C)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: Color(0xFF8A849C),
              ),
            ),
          ),
          if (trailing != null)
            Icon(trailing, size: 16, color: const Color(0xFF8A849C)),
        ],
      ),
    );
  }
}

class _VisitProgressCard extends StatelessWidget {
  const _VisitProgressCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8E0FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit in progress',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color: Color(0xFF6A5ACD),
                  ),
                ),
                Text(
                  'City Mart',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16141F),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Continue  ›',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D4B66),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopRow extends StatelessWidget {
  const _ShopRow({
    required this.initials,
    required this.color,
    required this.name,
    required this.detail,
  });

  final String initials;
  final Color color;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16141F),
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color: Color(0xFF8A849C),
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

class _VisitShopBanner extends StatelessWidget {
  const _VisitShopBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1730),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF3A3358),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                Icons.storefront_outlined,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit a shop',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Planned, nearby, or new',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color: Color(0xFFB7AEC4),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesNav extends StatelessWidget {
  const _SalesNav();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _NavItem(Icons.home_rounded, 'Home', active: true)),
        Expanded(child: _NavItem(Icons.people_outline, 'Customers')),
        Expanded(child: _NavItem(Icons.inventory_2_outlined, 'Products')),
        Expanded(child: _NavItem(Icons.receipt_long_outlined, 'Orders')),
        Expanded(child: _NavItem(Icons.person_outline, 'Profile')),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.icon, this.label, {this.active = false});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : const Color(0xFF8A849C);
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 8,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class V2DashboardFrame extends StatelessWidget {
  const V2DashboardFrame({super.key, this.height = 420});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: const FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topLeft,
          child: SizedBox(width: 980, height: 760, child: _DashboardCanvas()),
        ),
      ),
    );
  }
}

class _DashboardCanvas extends StatelessWidget {
  const _DashboardCanvas();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF5F3FB),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashSidebar(),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DashTopBar(),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DashStat(
                          icon: Icons.payments_outlined,
                          label: 'REVENUE THIS YEAR',
                          value: 'Rs 128,400',
                          tint: Color(0xFF6C4FF2),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _DashStat(
                          icon: Icons.shopping_bag_outlined,
                          label: 'ORDERS',
                          value: '10',
                          tint: Color(0xFF7C6AE8),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _DashStat(
                          icon: Icons.person_outline,
                          label: 'ACTIVE CUSTOMERS',
                          value: '3',
                          tint: Color(0xFF2F9E78),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _DashStat(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'OUTSTANDING',
                          value: 'Rs 24,600',
                          tint: Color(0xFFE2A23A),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: _DashStat(
                          icon: Icons.warning_amber_rounded,
                          label: 'LOW STOCK',
                          value: '1 item',
                          tint: Color(0xFFE25B5B),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    height: 210,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _DashPerformance()),
                        SizedBox(width: 10),
                        Expanded(flex: 2, child: _DashIntelligence()),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    height: 196,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _DashActivity()),
                        SizedBox(width: 10),
                        Expanded(flex: 2, child: _DashInventory()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashSidebar extends StatelessWidget {
  const _DashSidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      decoration: const BoxDecoration(gradient: AppGradients.navRail),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _V2Mark(size: 28),
              SizedBox(width: 8),
              Text(
                'Sello',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          _SideLabel('OVERVIEW'),
          _SideItem('Dashboard', Icons.space_dashboard_rounded, active: true),
          _SideItem('Reports', Icons.bar_chart_rounded),
          SizedBox(height: 12),
          _SideLabel('OPERATE'),
          _SideItem('Orders', Icons.receipt_long_rounded),
          _SideItem('Inventory', Icons.inventory_2_outlined),
          _SideItem('Products', Icons.sell_outlined),
          _SideItem('Customers', Icons.people_outline),
          _SideItem('Payments', Icons.payments_outlined, badge: '2'),
          _SideItem('Schedule', Icons.calendar_month_outlined),
          SizedBox(height: 12),
          _SideLabel('TEAM'),
          _SideItem('Team', Icons.groups_outlined),
          _SideItem('Attendance', Icons.fact_check_outlined),
        ],
      ),
    );
  }
}

class _SideLabel extends StatelessWidget {
  const _SideLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: Color(0x99FFFFFF),
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem(this.label, this.icon, {this.active = false, this.badge});

  final String label;
  final IconData icon;
  final bool active;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0x33FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          if (badge != null)
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFE25B5B),
                shape: BoxShape.circle,
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashTopBar extends StatelessWidget {
  const _DashTopBar();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _SearchPill('Search products, customers or orders')),
        const SizedBox(width: 10),
        const SizedBox(width: 148, child: _SearchPill('SMS quota')),
        SizedBox(width: 10),
        _QuickPill(),
      ],
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E1F4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Color(0xFF8E879F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: Color(0xFF8E879F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.add, size: 16, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'Quick actions',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashStat extends StatelessWidget {
  const _DashStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE8F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Color(0xFF8E879F),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1730),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECE8F6)),
      ),
      child: child,
    );
  }
}

class _DashPerformance extends StatelessWidget {
  const _DashPerformance();

  @override
  Widget build(BuildContext context) {
    return const _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Business performance',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1730),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Rs 128,400',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1C1730),
            ),
          ),
          Text(
            'Completed sales in the selected period',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: Color(0xFF8E879F),
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: AppColors.primary, label: 'Revenue'),
              SizedBox(width: 12),
              _LegendDot(color: Color(0xFF7AA2F7), label: 'Orders'),
              SizedBox(width: 12),
              _LegendDot(color: Color(0xFF5CC8A8), label: 'Collections'),
            ],
          ),
          SizedBox(height: 8),
          Expanded(child: _DashChart()),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: Color(0xFF6E6880),
          ),
        ),
      ],
    );
  }
}

class _DashChart extends StatelessWidget {
  const _DashChart();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashChartPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _DashChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE6E1F2)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    _drawCurve(canvas, size, const [
      0.78,
      0.7,
      0.28,
      0.52,
      0.22,
      0.62,
    ], AppColors.primary);
    _drawCurve(canvas, size, const [
      0.88,
      0.8,
      0.62,
      0.48,
      0.58,
      0.4,
    ], const Color(0xFF7AA2F7));
    _drawCurve(canvas, size, const [
      0.92,
      0.84,
      0.74,
      0.68,
      0.6,
      0.5,
    ], const Color(0xFF5CC8A8));
  }

  void _drawCurve(Canvas canvas, Size size, List<double> ys, Color color) {
    final points = <Offset>[
      for (var i = 0; i < ys.length; i++)
        Offset(size.width * (i / (ys.length - 1)), size.height * ys[i]),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midX = (current.dx + next.dx) / 2;
      path.cubicTo(midX, current.dy, midX, next.dy, next.dx, next.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashIntelligence extends StatelessWidget {
  const _DashIntelligence();

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: constraints.maxWidth,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sello Intelligence',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1730),
                    ),
                  ),
                  SizedBox(height: 8),
                  _Insight(
                    Icons.inventory_2_outlined,
                    '3 products are out of stock',
                    'Restock before the next round.',
                  ),
                  _Insight(
                    Icons.payments_outlined,
                    'Collections are still open',
                    'Follow up so cash comes in sooner.',
                  ),
                  _Insight(
                    Icons.receipt_long_outlined,
                    'Orders are waiting to close',
                    'Finish them so they can be delivered.',
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

class _Insight extends StatelessWidget {
  const _Insight(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1730),
                  ),
                ),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    color: Color(0xFF8E879F),
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

class _DashActivity extends StatelessWidget {
  const _DashActivity();

  @override
  Widget build(BuildContext context) {
    return const _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Business activity',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1730),
            ),
          ),
          SizedBox(height: 10),
          _ActivityRow('Order submitted for review'),
          _ActivityRow('Draft order was cancelled'),
          _ActivityRow('Cheque received from a customer'),
          _ActivityRow('Payment recorded against an order'),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: Color(0xFF2F9E78)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: Color(0xFF1C1730),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashInventory extends StatelessWidget {
  const _DashInventory();

  @override
  Widget build(BuildContext context) {
    return const _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory health',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1730),
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: CircularProgressIndicator(
                          value: 0.73,
                          strokeWidth: 10,
                          backgroundColor: Color(0xFFE8E3F6),
                          color: AppColors.primary,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Text(
                        '73%',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1730),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HealthLine('Total products', '15'),
                      _HealthLine('Low stock', '1'),
                      _HealthLine('Out of stock', '3'),
                    ],
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

class _HealthLine extends StatelessWidget {
  const _HealthLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: Color(0xFF6E6880),
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1730),
            ),
          ),
        ],
      ),
    );
  }
}

class V2DesktopFrame extends StatelessWidget {
  const V2DesktopFrame({super.key, this.height = 300, this.showOverlay = true});

  final double height;
  final bool showOverlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF151222),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 640,
                height: 300,
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.navRail,
                      ),
                      child: const Column(
                        children: [
                          SizedBox(height: 14),
                          _V2Mark(size: 24),
                          SizedBox(height: 16),
                          _V2RailIcon(Icons.space_dashboard_rounded),
                          _V2RailIcon(Icons.receipt_long_rounded, active: true),
                          _V2RailIcon(Icons.inventory_2_outlined),
                          _V2RailIcon(Icons.payments_outlined),
                        ],
                      ),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Orders',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _V2MiniStat(label: 'Open', value: '4'),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: _V2MiniStat(label: 'Done', value: '7'),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: _V2MiniStat(
                                    label: 'Total',
                                    value: '12',
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            _V2OrderLine(
                              invoice: 'SO-1042',
                              customer: 'City Mart',
                              status: 'Placed',
                            ),
                            _V2OrderLine(
                              invoice: 'SO-1041',
                              customer: 'Green Leaf',
                              status: 'Draft',
                            ),
                            _V2OrderLine(
                              invoice: 'SO-1038',
                              customer: 'Home & Care',
                              status: 'Completed',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showOverlay)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: V2FrostOverlay(
                title: 'Orders in one place',
                body: 'Track drafts, fulfilment and collections together.',
              ),
            ),
        ],
      ),
    );
  }
}

class V2PhoneFrame extends StatelessWidget {
  const V2PhoneFrame({super.key, this.width = 220, this.showOverlay = true});

  final double width;
  final bool showOverlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF12101C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          size: 14,
                          color: AppColors.lavender,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'City Mart',
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 14,
                            color: Color(0xFF9B94B8),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Search products…',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 11,
                                color: Color(0xFF9B94B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Wrap(
                      spacing: 6,
                      children: [
                        _V2Chip('All', selected: true),
                        _V2Chip('Grocery'),
                        _V2Chip('Care'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(
                          child: _V2ProductTile(
                            label: 'Milk powder',
                            icon: Icons.kitchen_outlined,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _V2ProductTile(
                            label: 'Biscuits',
                            icon: Icons.cookie_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Expanded(
                          child: _V2ProductTile(
                            label: 'Shampoo',
                            icon: Icons.water_drop_outlined,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _V2ProductTile(
                            label: 'Soap',
                            icon: Icons.soap_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showOverlay)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: V2FrostOverlay(
                title: 'Orders on the move',
                body: 'Create customer orders from the field.',
                compact: true,
              ),
            ),
        ],
      ),
    );
  }
}

class V2OverlayPanel extends StatelessWidget {
  const V2OverlayPanel({
    super.key,
    required this.child,
    required this.title,
    required this.body,
    this.height = 180,
  });

  final Widget child;
  final String title;
  final String body;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF151222),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: V2FrostOverlay(title: title, body: body),
          ),
        ],
      ),
    );
  }
}

class V2FrostOverlay extends StatelessWidget {
  const V2FrostOverlay({
    super.key,
    required this.title,
    required this.body,
    this.compact = false,
  });

  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x00151022),
            const Color(0xCC151022),
            const Color(0xF2151022),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 28 : 36,
          compact ? 12 : 16,
          compact ? 12 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: compact ? 11 : 12,
                height: 1.35,
                color: const Color(0xFFC9C2E4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class V2CollectionsSnippet extends StatelessWidget {
  const V2CollectionsSnippet({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Collections',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8),
          _V2ProgressLine(label: 'Cash', fraction: 0.72),
          SizedBox(height: 6),
          _V2ProgressLine(label: 'Bank', fraction: 0.48),
        ],
      ),
    );
  }
}

class V2InventorySnippet extends StatelessWidget {
  const V2InventorySnippet({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ('Milk powder', 'Available'),
            ('Shampoo', 'Low'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: Color(0xFFE7E2F6),
                      ),
                    ),
                  ),
                  Text(
                    row.$2,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: row.$2 == 'Low'
                          ? AppColors.finance
                          : AppColors.success,
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

class _V2Mark extends StatelessWidget {
  const _V2Mark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        AppAssets.logo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _V2RailIcon extends StatelessWidget {
  const _V2RailIcon(this.icon, {this.active = false});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: active ? AppColors.navActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 16,
        color: active ? Colors.white : AppColors.navInk,
      ),
    );
  }
}

class _V2MiniStat extends StatelessWidget {
  const _V2MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Color(0xFF9B94B8),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _V2OrderLine extends StatelessWidget {
  const _V2OrderLine({
    required this.invoice,
    required this.customer,
    required this.status,
  });

  final String invoice;
  final String customer;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              invoice,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Text(
              customer,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: Color(0xFFC9C2E4),
              ),
            ),
          ),
          Text(
            status,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.lavender,
            ),
          ),
        ],
      ),
    );
  }
}

class _V2Chip extends StatelessWidget {
  const _V2Chip(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: selected
              ? AppColors.primary
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFFC9C2E4),
        ),
      ),
    );
  }
}

class _V2ProductTile extends StatelessWidget {
  const _V2ProductTile({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.lavender),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _V2ProgressLine extends StatelessWidget {
  const _V2ProgressLine({required this.label, required this.fraction});

  final String label;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            color: Color(0xFFC9C2E4),
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}
