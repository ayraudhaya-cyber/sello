import 'package:flutter/material.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/theme/theme.dart';

/// Illustrative Sello interface frames.
///
/// These follow the real Hub shell and the mobile New order catalog.
/// They are not live data and do not show amounts or performance figures.
class MarketingShowcase extends StatelessWidget {
  const MarketingShowcase({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Illustrative Sello workspace. A desktop orders view, a mobile new order with a product grid, and a short list of order activity.',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 440 && !compact;
            if (!wide) {
              final phoneWidth = constraints.maxWidth.clamp(0, 300).toDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const MarketingDesktopPreview(),
                  const SizedBox(height: 20),
                  MarketingPhonePreview(width: phoneWidth),
                  const SizedBox(height: 16),
                  const MarketingActivityCard(),
                ],
              );
            }
            return const SizedBox(
              height: 540,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(top: 36, right: 24, child: _ShowcaseGlow()),
                  Positioned(
                    top: 28,
                    left: 148,
                    right: 72,
                    child: MarketingDesktopPreview(),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: MarketingPhonePreview(width: 252),
                  ),
                  Positioned(left: 0, top: 78, child: MarketingActivityCard()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShowcaseGlow extends StatelessWidget {
  const _ShowcaseGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.18),
              AppColors.primary.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class MarketingDesktopPreview extends StatelessWidget {
  const MarketingDesktopPreview({super.key, this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    final frame = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.level3,
      ),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 1040,
          height: 520,
          child: Row(
            children: [
              Container(
                width: 72,
                decoration: const BoxDecoration(gradient: AppGradients.navRail),
                child: const Column(
                  children: [
                    SizedBox(height: 16),
                    _Mark(size: 32),
                    SizedBox(height: 22),
                    _RailIcon(Icons.space_dashboard_rounded),
                    _RailIcon(Icons.receipt_long_rounded, active: true),
                    _RailIcon(Icons.inventory_2_outlined),
                    _RailIcon(Icons.people_outline_rounded),
                    _RailIcon(Icons.payments_outlined),
                    _RailIcon(Icons.bar_chart_rounded),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: AppColors.background,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: AppColors.surface,
                        child: const Row(
                          children: [
                            Expanded(
                              child: _SearchField(
                                'Search products, customers or orders…',
                              ),
                            ),
                            SizedBox(width: 12),
                            _PrimaryPill('New Order'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Orders',
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Create drafts, complete sales, and keep stock in sync.',
                                style: TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Row(
                                children: [
                                  _TabPill('Orders', selected: true),
                                  SizedBox(width: 8),
                                  _TabPill('Returns'),
                                  SizedBox(width: 8),
                                  _TabPill('Cancelled'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const _FilterBar(),
                              const SizedBox(height: 12),
                              const Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.receipt_long_rounded,
                                      label: 'Total',
                                      value: '12',
                                      caption: 'All orders',
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.schedule_rounded,
                                      label: 'Open',
                                      value: '4',
                                      caption: 'Draft, placed',
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.check_circle_outline,
                                      label: 'Completed',
                                      value: '7',
                                      caption: 'Goods delivered',
                                      tint: AppColors.successContainer,
                                      iconColor: AppColors.success,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: _StatCard(
                                      icon: Icons.cancel_outlined,
                                      label: 'Cancelled',
                                      value: '1',
                                      caption: 'No stock impact',
                                      tint: AppColors.attentionSoft,
                                      iconColor: AppColors.attention,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const _OrderHead(),
                              const _OrderRow(
                                invoice: 'SO-1042',
                                customer: 'City Mart',
                                status: 'Placed',
                                tone: _StatusTone.placed,
                              ),
                              const _OrderRow(
                                invoice: 'SO-1041',
                                customer: 'Green Leaf',
                                status: 'Draft',
                                tone: _StatusTone.draft,
                              ),
                              const _OrderRow(
                                invoice: 'SO-1038',
                                customer: 'Home & Care',
                                status: 'Completed',
                                tone: _StatusTone.done,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (height != null) return SizedBox(height: height, child: frame);
    return AspectRatio(aspectRatio: 1040 / 520, child: frame);
  }
}

class MarketingPhonePreview extends StatelessWidget {
  const MarketingPhonePreview({super.key, this.width = 248});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD9D3EE), width: 3),
        boxShadow: AppShadows.level3,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.storefront_rounded,
                  size: 16,
                  color: AppColors.brandIndigo,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'City Mart',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textFaint,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _SearchField('Search products…', compact: true),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniChip('All', selected: true),
                _MiniChip('Grocery'),
                _MiniChip('Care'),
                _MiniChip('Home'),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  child: _ProductTile(
                    label: 'Milk powder',
                    icon: Icons.kitchen_outlined,
                    tint: AppColors.primaryContainer,
                    added: true,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _ProductTile(
                    label: 'Biscuits',
                    icon: Icons.cookie_outlined,
                    tint: AppColors.financeSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  child: _ProductTile(
                    label: 'Shampoo',
                    icon: Icons.water_drop_outlined,
                    tint: AppColors.infoContainer,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _ProductTile(
                    label: 'Soap',
                    icon: Icons.soap_outlined,
                    tint: AppColors.inventorySoft,
                    added: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    '2 items',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textFaint,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Continue',
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
      ),
    );
  }
}

class MarketingActivityCard extends StatelessWidget {
  const MarketingActivityCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 196,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.level2,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Order activity',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          _ActivityLine(label: 'Placed', color: AppColors.primary),
          _ActivityLine(label: 'Partially delivered', color: AppColors.finance),
          _ActivityLine(label: 'Completed', color: AppColors.success),
        ],
      ),
    );
  }
}

class MarketingBrowserPreview extends StatelessWidget {
  const MarketingBrowserPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: AppColors.surfaceMuted,
            child: Row(
              children: [
                const _Dot(color: Color(0xFFE7B3B6)),
                const SizedBox(width: 5),
                const _Dot(color: Color(0xFFE7D3A8)),
                const SizedBox(width: 5),
                const _Dot(color: Color(0xFFB7D7C4)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 22,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.outlinePanel),
                    ),
                    child: const Text(
                      'sello.cashro.pro',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 228, child: _WorkspaceStrip()),
        ],
      ),
    );
  }
}

class _WorkspaceStrip extends StatelessWidget {
  const _WorkspaceStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          decoration: const BoxDecoration(gradient: AppGradients.navRail),
          child: const Column(
            children: [
              SizedBox(height: 12),
              _Mark(size: 22),
              SizedBox(height: 14),
              _RailIcon(Icons.receipt_long_rounded, active: true),
              _RailIcon(Icons.inventory_2_outlined),
              _RailIcon(Icons.people_outline_rounded),
            ],
          ),
        ),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Orders',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                _OrderRow(status: 'Placed', tone: _StatusTone.placed),
                _OrderRow(status: 'Draft', tone: _StatusTone.draft),
                _OrderRow(status: 'Completed', tone: _StatusTone.done),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.size});

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

class _RailIcon extends StatelessWidget {
  const _RailIcon(this.icon, {this.active = false});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: active ? AppColors.navActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 18,
        color: active ? Colors.white : AppColors.navInk,
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField(this.hint, {this.compact = false});

  final String hint;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 32 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: compact ? AppColors.surface : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(compact ? 10 : 99),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: compact ? 14 : 16,
            color: AppColors.textFaint,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hint,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: compact ? 11 : 12,
                color: AppColors.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryPill extends StatelessWidget {
  const _PrimaryPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: selected ? AppColors.outlinePanel : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: const Row(
        children: [
          Expanded(child: _SearchField('Search invoice, customer, phone…')),
          SizedBox(width: 8),
          _FilterChip('Status'),
          SizedBox(width: 8),
          _FilterChip('Payment'),
          SizedBox(width: 8),
          _FilterChip('Date'),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.inputAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: AppColors.textFaint,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.tint = AppColors.primaryContainer,
    this.iconColor = AppColors.brandIndigo,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.textTertiary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  caption,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10,
                    color: AppColors.textTertiary,
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

class _OrderHead extends StatelessWidget {
  const _OrderHead();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeadText('Invoice')),
          Expanded(flex: 3, child: _HeadText('Customer')),
          Expanded(flex: 3, child: _HeadText('Status')),
        ],
      ),
    );
  }
}

class _HeadText extends StatelessWidget {
  const _HeadText(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: AppTypography.eyebrow);
  }
}

enum _StatusTone { placed, draft, done }

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    this.invoice = 'Invoice',
    this.customer = 'Customer',
    required this.status,
    required this.tone,
  });

  final String invoice;
  final String customer;
  final String status;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.placed => AppColors.primary,
      _StatusTone.draft => AppColors.textTertiary,
      _StatusTone.done => AppColors.success,
    };
    final background = switch (tone) {
      _StatusTone.placed => AppColors.primaryContainer,
      _StatusTone.draft => AppColors.veil,
      _StatusTone.done => AppColors.successContainer,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              invoice,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              customer,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
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

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.label,
    required this.icon,
    required this.tint,
    this.added = false,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final bool added;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 22, color: AppColors.brandIndigo),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          if (added)
            Container(
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlinePanel),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(Icons.remove, size: 12, color: AppColors.textSecondary),
                  Text(
                    '1',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(Icons.add, size: 12, color: AppColors.brandIndigo),
                ],
              ),
            )
          else
            const Text(
              'In stock',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, {this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.outlinePanel,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
