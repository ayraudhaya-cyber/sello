import 'package:flutter/material.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/sales_day.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Identifies a swappable Primary Operational Card metric.
enum OperationalMetricKind {
  outstandingCollections,
  todaysSales,
  followUps,
  lowStock,
  pendingDeliveries,
}

/// Presentation model for one Home operational summary card.
class OperationalSummaryMetric {
  const OperationalSummaryMetric({
    required this.kind,
    required this.label,
    required this.value,
    required this.trendLabel,
    required this.icon,
    required this.tone,
    required this.route,
    this.trendPositive,
  });

  final OperationalMetricKind kind;
  final String label;
  final String value;
  final String trendLabel;
  final bool? trendPositive;
  final IconData icon;
  final Color tone;
  final String route;
}

/// Picks the Primary Operational Card from company settings + day insights.
///
/// Priority is intentional and permission-aware: never return a metric the
/// rep cannot see. Layout always receives exactly one metric (no empty slot).
abstract final class OperationalSummaryResolver {
  static String currencySymbol(String currency) => _symbol(currency);

  static OperationalSummaryMetric resolve({
    required CompanySettings settings,
    required SalesDayInsights insights,
  }) {
    final candidates = <OperationalSummaryMetric>[
      if (settings.salesCanViewOutstandingBalances)
        OperationalSummaryMetric(
          kind: OperationalMetricKind.outstandingCollections,
          label: 'Collection due',
          value: SelloFormatters.currency(
            insights.outstandingTotal,
            symbol: _symbol(settings.currency),
          ),
          trendLabel: insights.outstandingDueToday > 0
              ? '${insights.outstandingDueToday} due today'
              : 'None due today',
          trendPositive: insights.outstandingDueToday == 0,
          icon: Icons.account_balance_wallet_rounded,
          tone: AppColors.finance,
          route: RoutePaths.selloCustomers,
        ),
      OperationalSummaryMetric(
        kind: OperationalMetricKind.todaysSales,
        label: 'Today’s sales',
        value: SelloFormatters.currency(
          insights.todaysSales,
          symbol: _symbol(settings.currency),
        ),
        trendLabel: insights.ordersDueToday > 0
            ? '${insights.ordersDueToday} orders open'
            : 'Quiet so far',
        trendPositive: true,
        icon: Icons.payments_rounded,
        tone: AppColors.success,
        route: RoutePaths.selloOrders,
      ),
      OperationalSummaryMetric(
        kind: OperationalMetricKind.followUps,
        label: 'Follow-ups',
        value: '${insights.followUpsDue}',
        trendLabel: insights.followUpsDue > 0
            ? 'Need attention'
            : 'All clear',
        trendPositive: insights.followUpsDue == 0,
        icon: Icons.flag_rounded,
        tone: AppColors.attention,
        route: RoutePaths.selloCustomers,
      ),
      if (settings.enableLowStockAlert)
        OperationalSummaryMetric(
          kind: OperationalMetricKind.lowStock,
          label: 'Low stock',
          value: '${insights.lowStockCount}',
          trendLabel: insights.lowStockCount > 0
              ? 'At or below reorder'
              : 'Stock healthy',
          trendPositive: insights.lowStockCount == 0,
          icon: Icons.inventory_2_rounded,
          tone: AppColors.inventory,
          route: RoutePaths.selloProducts,
        ),
      OperationalSummaryMetric(
        kind: OperationalMetricKind.pendingDeliveries,
        label: 'Pending deliveries',
        value: '${insights.pendingDeliveries}',
        trendLabel: insights.pendingDeliveries > 0
            ? 'Awaiting fulfilment'
            : 'Nothing pending',
        trendPositive: insights.pendingDeliveries == 0,
        icon: Icons.local_shipping_rounded,
        tone: AppColors.ops,
        route: RoutePaths.selloOrders,
      ),
    ];

    return candidates.first;
  }

  static String _symbol(String currency) {
    return switch (currency.toUpperCase()) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      'LKR' => 'Rs ',
      'INR' => '₹',
      'AED' => 'AED ',
      'JPY' => '¥',
      _ => '$currency ',
    };
  }
}
