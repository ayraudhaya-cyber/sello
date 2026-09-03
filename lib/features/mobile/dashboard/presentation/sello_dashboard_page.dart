import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/mobile/dashboard/application/sello_consider_customers_provider.dart';
import 'package:sello/features/mobile/dashboard/application/sello_home_provider.dart';
import 'package:sello/features/notifications/application/notifications_provider.dart';
import 'package:sello/features/notifications/presentation/notification_center_panel.dart';
import 'package:sello/features/visits/application/active_customer_visit_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/data/sri_lanka_areas.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/intelligence_insight.dart';
import 'package:sello/shared/models/sales_day.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Sales Home — field companion laid out to the mobile Home mock.
class SelloDashboardPage extends ConsumerWidget {
  const SelloDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final day = ref.watch(selloHomeDayProvider);
    final active = ref.watch(activeCustomerVisitProvider).valueOrNull;
    final consider = ref.watch(selloConsiderCustomersProvider);
    final nearArea = ref.watch(selloHomeNearAreaProvider);
    final settings = ref.watch(selloCompanySettingsProvider).valueOrNull;
    final currency = SelloFormatters.currencySymbol(settings?.currency);
    final pad = context.pagePadding;

    void openVisit({
      required String customerId,
      required String name,
      String? scheduled,
    }) {
      context.go(
        '${RoutePaths.selloVisit}'
        '?customer=$customerId'
        '${scheduled != null ? '&scheduled=$scheduled' : ''}'
        '&name=${Uri.encodeComponent(name)}',
      );
    }

    void openStop(FieldVisitStop stop) {
      final customerId = stop.customerId;
      if (customerId == null || stop.isComplete) {
        context.go(RoutePaths.selloCustomers);
        return;
      }
      openVisit(
        customerId: customerId,
        name: stop.customerName,
        scheduled: stop.isPlanned ? stop.id : null,
      );
    }

    void visitAShop() => context.go(RoutePaths.selloCustomers);

    final activeStop = active == null
        ? null
        : (day.visits
                .where((s) => s.customerId == active.customerId)
                .firstOrNull ??
            FieldVisitStop(
              id: active.id,
              customerId: active.customerId,
              customerVisitId: active.id,
              customerName: active.customerName ?? 'Customer',
              origin: VisitOrigin.unplanned,
              status: VisitStopStatus.inProgress,
              badge: VisitBadgeKind.unplanned,
            ));

    final preview = day.homePlanPreview(maxItems: 3);
    final hidden = day.homePlanHiddenCount(maxItems: 3);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: ColoredBox(
        color: AppColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeHero(
              day: day,
              currencySymbol: currency,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 20),
                children: [
                    _HomeStoreSearch(
                      nearArea: nearArea,
                      onPickArea: () => _pickNearArea(context, ref),
                      onOpenCustomer: (customer) => openVisit(
                        customerId: customer.id,
                        name: customer.name,
                      ),
                      onSeeAll: (query) => context.go(
                        query.trim().isEmpty
                            ? RoutePaths.selloCustomers
                            : '${RoutePaths.selloCustomers}'
                                '?q=${Uri.encodeComponent(query.trim())}',
                      ),
                      onSearchProducts: (query) => context.go(
                        query.trim().isEmpty
                            ? RoutePaths.selloProducts
                            : '${RoutePaths.selloProducts}'
                                '?q=${Uri.encodeComponent(query.trim())}',
                      ),
                      onWalkIn: () =>
                          context.go('${RoutePaths.selloVisit}?walkin=1'),
                    ),
                    if (activeStop != null) ...[
                      const SizedBox(height: 14),
                      _ContinueVisit(
                        shopName: activeStop.customerName,
                        onContinue: () => openStop(activeStop),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (day.hasVisitPlan) ...[
                      _TodaysPlanSection(
                        day: day,
                        preview: preview,
                        hiddenCount: hidden,
                        onOpenStop: openStop,
                        onViewAll: () => _showFullPlan(
                          context,
                          day: day,
                          onOpenStop: openStop,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _CustomersToConsider(
                      customers: consider.valueOrNull ?? const [],
                      loading: consider.isLoading,
                      onOpen: (customer) => openVisit(
                        customerId: customer.id,
                        name: customer.name,
                      ),
                      onSeeAll: () => context.go(RoutePaths.selloCustomers),
                    ),
                    if (day.intelligenceHints.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      SelloIntelligenceBanner(
                        insights: _fieldInsights(day.intelligenceHints),
                        maxVisible: 2,
                        onInsightAction: (insight) {
                          final role = session?.appRole;
                          if (role == null) return;
                          context.go(insight.routeFor(role));
                        },
                      ),
                    ],
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 10, pad, 12),
              child: _VisitShopAction(onVisitShop: visitAShop),
            ),
          ],
        ),
      ),
    );
  }

  static List<IntelligenceInsight> _fieldInsights(
    List<IntelligenceInsight> hints,
  ) {
    final field = hints
        .where((h) => switch (h.category) {
              IntelligenceCategory.customers ||
              IntelligenceCategory.customerVisits ||
              IntelligenceCategory.schedules ||
              IntelligenceCategory.payments ||
              IntelligenceCategory.orders ||
              IntelligenceCategory.recommendations =>
                true,
              _ => false,
            })
        .toList(growable: false);
    return field.isNotEmpty ? field : hints;
  }

  static Future<void> _pickNearArea(BuildContext context, WidgetRef ref) async {
    final current = ref.read(selloHomeNearAreaProvider);
    final extras = <String>[
      if (current != null && current.trim().isNotEmpty) current,
      if (ref.read(selloHomeDayProvider).primaryArea case final area?
          when area.trim().isNotEmpty)
        area.trim(),
    ];
    final areas = SriLankaAreas.suggestionsNear(extraNames: extras);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.bottomSheet),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlinePanel,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Near',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: const Text('All areas'),
                        selected: current == null,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                      for (final area in areas)
                        ListTile(
                          title: Text(area),
                          selected: current == area,
                          onTap: () => Navigator.pop(context, area),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    ref.read(selloHomeNearAreaProvider.notifier).setArea(
          picked.isEmpty ? null : picked,
        );
  }

  static Future<void> _showFullPlan(
    BuildContext context, {
    required SalesDaySnapshot day,
    required ValueChanged<FieldVisitStop> onOpenStop,
  }) {
    final stops = day.todaysRoute;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlinePanel,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Today's plan",
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${stops.length} stop${stops.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: stops.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: AppColors.outlineSubtle,
                    ),
                    itemBuilder: (context, i) {
                      final stop = stops[i];
                      return _PlanRow(
                        stop: stop,
                        emphasize: stop.isInProgress,
                        onTap: () {
                          Navigator.of(context).pop();
                          onOpenStop(stop);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHero extends ConsumerWidget {
  const _HomeHero({
    required this.day,
    required this.currencySymbol,
  });

  final SalesDaySnapshot day;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.paddingOf(context).top;
    final branding = ref.watch(brandingProvider);
    final orders = day.activity.ordersCreated;
    final visits = day.hasVisitPlan
        ? day.plannedCount
        : day.activity.customersVisited;
    final collected = SelloFormatters.currency(
      day.insights.todaysSales,
      symbol: currencySymbol,
    );
    final ordersLabel = '$orders ${orders == 1 ? 'Order' : 'Orders'}';
    final visitsLabel = '$visits ${visits == 1 ? 'Visit' : 'Visits'}';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 8, 20, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BrandedLogo(
                    size: 32,
                    maxWidth: 148,
                    branding: branding,
                    onLightSurface: true,
                  ),
                ),
              ),
              const _HomeNotificationButton(),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Collected Today',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            collected,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.6,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _HeroPill(label: '$ordersLabel | $visitsLabel'),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _HomeNotificationButton extends ConsumerWidget {
  const _HomeNotificationButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      notificationsProvider.select((s) => s.unreadCount),
    );
    final hasUnread = unread > 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => openNotificationCenter(context),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Badge(
              isLabelVisible: hasUnread,
              label: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: AppColors.attention,
              child: Icon(
                hasUnread
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                size: 22,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: child,
      ),
    );
  }
}

class _HomeStoreSearch extends ConsumerStatefulWidget {
  const _HomeStoreSearch({
    required this.nearArea,
    required this.onPickArea,
    required this.onOpenCustomer,
    required this.onSeeAll,
    required this.onSearchProducts,
    required this.onWalkIn,
  });

  final String? nearArea;
  final VoidCallback onPickArea;
  final ValueChanged<CustomerSummary> onOpenCustomer;
  final ValueChanged<String> onSeeAll;
  final ValueChanged<String> onSearchProducts;
  final VoidCallback onWalkIn;

  @override
  ConsumerState<_HomeStoreSearch> createState() => _HomeStoreSearchState();
}

class _HomeStoreSearchState extends ConsumerState<_HomeStoreSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final near = widget.nearArea?.trim();
    final nearLabel = (near == null || near.isEmpty) ? 'All' : near;
    final searching = _query.trim().length >= 2;
    final async = searching
        ? ref.watch(selloHomeCustomerSearchProvider(_query))
        : null;
    final results = async?.valueOrNull ?? const <CustomerSummary>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.surface,
          elevation: 0,
          shadowColor: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outlinePanel),
            ),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: widget.onSeeAll,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search stores, customers, products...',
                  hintStyle: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE6E4EE)),
              InkWell(
                onTap: widget.onPickArea,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Near: $nearLabel',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
        if (searching) ...[
          const SizedBox(height: 8),
          _HomePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (async?.isLoading == true && results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else if (results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      'No matching stores.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                else
                  for (final customer in results.take(5))
                    _ConsiderRow(
                      customer: customer,
                      onTap: () => widget.onOpenCustomer(customer),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => widget.onSeeAll(_query),
                        child: const Text('See all'),
                      ),
                      TextButton(
                        onPressed: () => widget.onSearchProducts(_query),
                        child: const Text('Products'),
                      ),
                      TextButton(
                        onPressed: widget.onWalkIn,
                        child: const Text('Walk-in'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CustomersToConsider extends StatelessWidget {
  const _CustomersToConsider({
    required this.customers,
    required this.loading,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<CustomerSummary> customers;
  final bool loading;
  final ValueChanged<CustomerSummary> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Worth Visiting',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: context.brandAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: const Text(
                'See all →',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (loading && customers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (customers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'No customers to suggest yet. Search or visit a shop.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          )
        else
          for (final customer in customers)
            _ConsiderRow(
              customer: customer,
              onTap: () => onOpen(customer),
            ),
      ],
    );
  }
}

class _ConsiderRow extends StatelessWidget {
  const _ConsiderRow({
    required this.customer,
    required this.onTap,
  });

  final CustomerSummary customer;
  final VoidCallback onTap;

  static const _avatars = [
    Color(0xFFE36B7A),
    Color(0xFF4C8DFF),
    Color(0xFF7B6CF6),
    Color(0xFF2BB8A8),
    Color(0xFFE08A3C),
  ];

  static Color _avatarFor(String key) {
    return _avatars[key.hashCode.abs() % _avatars.length];
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _avatarFor(customer.id.isNotEmpty
                    ? customer.id
                    : customer.name),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(customer.name),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _contextLine(customer),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
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

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 &&
        parts.first.isNotEmpty &&
        parts[1].isNotEmpty) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    final trimmed = name.trim();
    if (trimmed.length >= 2) return trimmed.substring(0, 2).toUpperCase();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  static String _contextLine(CustomerSummary customer) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = customer.nextVisitAt != null &&
        !DateTime(
          customer.nextVisitAt!.year,
          customer.nextVisitAt!.month,
          customer.nextVisitAt!.day,
        ).isAfter(today);

    final parts = <String>[
      if (due)
        'Due for a visit'
      else if (customer.lastVisitAt != null)
        'Visited ${_relative(customer.lastVisitAt!)}'
      else
        'Not visited yet',
      if (customer.lastPurchaseAt != null)
        'Ordered ${_relative(customer.lastPurchaseAt!)}',
    ];
    return parts.join(' · ');
  }

  static String _relative(DateTime value) {
    final now = DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }
}

class _ContinueVisit extends StatelessWidget {
  const _ContinueVisit({
    required this.shopName,
    required this.onContinue,
  });

  final String shopName;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE4E0F8),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onContinue,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.brandAccent,
                  borderRadius: AppRadius.iconAll,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visit in progress',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.brandAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Continue',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.brandAccent,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.brandAccent),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisitShopAction extends StatelessWidget {
  const _VisitShopAction({required this.onVisitShop});

  final VoidCallback onVisitShop;

  static const _surface = Color(0xFF160F2F);
  static const _accent = Color(0xFF6A5BE2);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onVisitShop,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Visit a shop',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Planned, nearby, or new',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
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

class _TodaysPlanSection extends StatelessWidget {
  const _TodaysPlanSection({
    required this.day,
    required this.preview,
    required this.hiddenCount,
    required this.onOpenStop,
    required this.onViewAll,
  });

  final SalesDaySnapshot day;
  final List<FieldVisitStop> preview;
  final int hiddenCount;
  final ValueChanged<FieldVisitStop> onOpenStop;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    if (!day.hasVisitPlan && preview.isEmpty) {
      return const SizedBox.shrink();
    }

    final remaining = day.plannedRemainingCount;
    final trailing = !day.hasVisitPlan
        ? null
        : (day.plannedCount == 0 && day.hasAssignedArea)
            ? null
            : (remaining == 0 ? 'Done' : '$remaining remaining');

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.plannedCount == 0 && day.hasAssignedArea
                      ? "Today's plan"
                      : "Today's plan · ${day.plannedCount} "
                          '${day.plannedCount == 1 ? 'stop' : 'stops'}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing == 'Done'
                      ? 'Done'
                      : day.plannedCompletedCount > 0
                          ? '${day.plannedCompletedCount} completed'
                          : trailing,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (preview.isEmpty && day.hasAssignedArea && day.plannedCount == 0)
            _QuietNote(
              heading: day.assignedArea!,
              detail: 'Discover shops and build your day as you go.',
              icon: Icons.explore_outlined,
            )
          else if (preview.isEmpty && day.isPlanComplete)
            const _QuietNote(
              heading: 'Plan done',
              detail: 'Keep visiting if you need to.',
              icon: Icons.check_circle_outline_rounded,
            )
          else ...[
            for (final stop in preview)
              _PlanRow(
                stop: stop,
                emphasize: stop.isInProgress,
                onTap: () => onOpenStop(stop),
              ),
            if (hiddenCount > 0 || day.todaysRoute.length > preview.length) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    foregroundColor: context.brandAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    hiddenCount > 0
                        ? 'View all · $hiddenCount more'
                        : 'View all',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.stop,
    required this.emphasize,
    required this.onTap,
  });

  final FieldVisitStop stop;
  final bool emphasize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (stop.status) {
      VisitStopStatus.completed => (
          Icons.check_circle_rounded,
          AppColors.success,
          stop.isUnplanned ? 'Completed · Walk-in' : 'Completed',
        ),
      VisitStopStatus.inProgress => (
          Icons.play_circle_filled_rounded,
          context.brandAccent,
          'In progress',
        ),
      VisitStopStatus.skipped => (
          Icons.schedule_rounded,
          AppColors.warning,
          'Skipped · come back later',
        ),
      VisitStopStatus.pending => (
          Icons.circle_outlined,
          AppColors.textFaint,
          stop.isUnplanned
              ? 'Unplanned'
              : (stop.placeLabel ?? "On today's plan"),
        ),
    };

    final subtitle = [
      label,
      if (stop.placeLabel != null && stop.placeLabel != label) stop.placeLabel!,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 15.5,
                      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
                      color: stop.isComplete
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: emphasize
                          ? context.brandAccent
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietNote extends StatelessWidget {
  const _QuietNote({
    required this.heading,
    required this.detail,
    required this.icon,
  });

  final String heading;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.success),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
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
