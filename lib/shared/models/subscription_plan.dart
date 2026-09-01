import 'package:equatable/equatable.dart';

/// Stable capacity keys — resolve via plan config, never hardcode numbers in UI.
abstract final class PlanLimitKeys {
  static const maxUsers = 'max_users';
  static const maxSalesRepresentatives = 'max_sales_representatives';
  static const maxBranches = 'max_branches';
  static const maxStorageMb = 'max_storage_mb';

  static const all = <String>[
    maxUsers,
    maxSalesRepresentatives,
    maxBranches,
    maxStorageMb,
  ];
}

/// Stable feature entitlement keys — commercial module access, not IAM.
abstract final class PlanEntitlementKeys {
  static const reports = 'reports';
  static const intelligence = 'intelligence';
  static const advancedAnalytics = 'advanced_analytics';
  static const multipleBranches = 'multiple_branches';
  static const advancedPermissions = 'advanced_permissions';
  static const integrations = 'integrations';
  static const apiAccess = 'api_access';
  static const automation = 'automation';
  static const additionalStorage = 'additional_storage';

  static const all = <String>[
    reports,
    intelligence,
    advancedAnalytics,
    multipleBranches,
    advancedPermissions,
    integrations,
    apiAccess,
    automation,
    additionalStorage,
  ];
}

enum BillingInterval {
  month,
  year;

  String get dbValue => name;

  static BillingInterval fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'year':
      case 'annual':
      case 'yearly':
        return BillingInterval.year;
      default:
        return BillingInterval.month;
    }
  }
}

enum SubscriptionLifecycleStatus {
  active,
  trialing,
  pastDue,
  grace,
  suspended,
  cancelled;

  String get dbValue => switch (this) {
        SubscriptionLifecycleStatus.active => 'active',
        SubscriptionLifecycleStatus.trialing => 'trialing',
        SubscriptionLifecycleStatus.pastDue => 'past_due',
        SubscriptionLifecycleStatus.grace => 'grace',
        SubscriptionLifecycleStatus.suspended => 'suspended',
        SubscriptionLifecycleStatus.cancelled => 'cancelled',
      };

  bool get isCommerciallyUsable =>
      this == active || this == trialing || this == pastDue || this == grace;

  static SubscriptionLifecycleStatus fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'trialing':
        return SubscriptionLifecycleStatus.trialing;
      case 'past_due':
        return SubscriptionLifecycleStatus.pastDue;
      case 'grace':
        return SubscriptionLifecycleStatus.grace;
      case 'suspended':
        return SubscriptionLifecycleStatus.suspended;
      case 'cancelled':
        return SubscriptionLifecycleStatus.cancelled;
      default:
        return SubscriptionLifecycleStatus.active;
    }
  }
}

/// Capacity band for upgrade / soft-limit UX — not a hard destroy signal.
enum CapacityStatus {
  within,
  approaching,
  atLimit,
  exceeded,
  unlimited;

  bool get canAdd => this == within || this == approaching || this == unlimited;

  bool get isConstrained =>
      this == approaching || this == atLimit || this == exceeded;

  static CapacityStatus fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'approaching':
        return CapacityStatus.approaching;
      case 'at_limit':
        return CapacityStatus.atLimit;
      case 'exceeded':
        return CapacityStatus.exceeded;
      case 'unlimited':
        return CapacityStatus.unlimited;
      default:
        return CapacityStatus.within;
    }
  }
}

/// Catalog plan — limits & entitlements are configuration, not app constants.
class SubscriptionPlan extends Equatable {
  const SubscriptionPlan({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.isActive = true,
    this.displayOrder = 100,
    this.limits = const {},
    this.entitlements = const {},
    this.definitionVersion = 1,
    this.effectiveFrom,
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final bool isActive;
  final int displayOrder;

  /// Null value = unlimited for that key.
  final Map<String, int?> limits;
  final Map<String, bool> entitlements;
  final int definitionVersion;
  final DateTime? effectiveFrom;

  int? limitOf(String key) => limits[key];

  bool hasEntitlement(String key) => entitlements[key] == true;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 100,
      limits: _parseLimits(json['limits']),
      entitlements: _parseEntitlements(json['entitlements']),
      definitionVersion: (json['definition_version'] as num?)?.toInt() ?? 1,
      effectiveFrom: _parseDate(json['effective_from']),
    );
  }

  @override
  List<Object?> get props => [id, code, definitionVersion, limits, entitlements];
}

/// Versioned list price for a plan. Historical invoices use snapshots instead.
class SubscriptionPlanPrice extends Equatable {
  const SubscriptionPlanPrice({
    required this.id,
    required this.planId,
    required this.billingInterval,
    required this.currency,
    this.amount,
    this.isActive = true,
    this.priceVersion = 1,
    this.effectiveFrom,
    this.effectiveUntil,
  });

  final String id;
  final String planId;
  final BillingInterval billingInterval;
  final String currency;

  /// Null = custom / contact-sales pricing.
  final num? amount;
  final bool isActive;
  final int priceVersion;
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;

  bool get isCustomPricing => amount == null;

  factory SubscriptionPlanPrice.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlanPrice(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      billingInterval: BillingInterval.fromDb(json['billing_interval'] as String?),
      currency: (json['currency'] as String? ?? 'USD').toUpperCase(),
      amount: json['amount'] as num?,
      isActive: json['is_active'] as bool? ?? true,
      priceVersion: (json['price_version'] as num?)?.toInt() ?? 1,
      effectiveFrom: _parseDate(json['effective_from']),
      effectiveUntil: _parseDate(json['effective_until']),
    );
  }

  @override
  List<Object?> get props => [id, planId, billingInterval, currency, amount, priceVersion];
}

/// Business-owned subscription with locked price snapshot.
class CompanySubscription extends Equatable {
  const CompanySubscription({
    required this.id,
    required this.companyId,
    required this.planId,
    required this.planCode,
    required this.status,
    required this.billingInterval,
    required this.currency,
    this.unitAmount,
    this.planPriceId,
    this.trialEndsAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.cancelledAt,
    this.activatedAt,
    this.expiresAt,
    this.capacityOverrides = const {},
    this.entitlementOverrides = const {},
  });

  final String id;
  final String companyId;
  final String planId;
  final String planCode;
  final SubscriptionLifecycleStatus status;
  final BillingInterval billingInterval;
  final String currency;

  /// Price at activation/renewal — do not re-read live catalog prices for history.
  final num? unitAmount;
  final String? planPriceId;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime? cancelledAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final Map<String, int?> capacityOverrides;
  final Map<String, bool> entitlementOverrides;

  factory CompanySubscription.fromJson(Map<String, dynamic> json) {
    return CompanySubscription(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      planId: json['plan_id'] as String,
      planCode: json['plan_code'] as String,
      status: SubscriptionLifecycleStatus.fromDb(json['status'] as String?),
      billingInterval: BillingInterval.fromDb(json['billing_interval'] as String?),
      currency: (json['currency'] as String? ?? 'USD').toUpperCase(),
      unitAmount: json['unit_amount'] as num?,
      planPriceId: json['plan_price_id'] as String?,
      trialEndsAt: _parseDate(json['trial_ends_at']),
      currentPeriodStart: _parseDate(json['current_period_start']),
      currentPeriodEnd: _parseDate(json['current_period_end']),
      cancelAtPeriodEnd: json['cancel_at_period_end'] as bool? ?? false,
      cancelledAt: _parseDate(json['cancelled_at']),
      activatedAt: _parseDate(json['activated_at']),
      expiresAt: _parseDate(json['expires_at']),
      capacityOverrides: _parseLimits(json['capacity_overrides']),
      entitlementOverrides: _parseEntitlements(json['entitlement_overrides']),
    );
  }

  @override
  List<Object?> get props => [id, companyId, planCode, status, unitAmount];
}

class CompanyUsageCounts extends Equatable {
  const CompanyUsageCounts({
    this.users = 0,
    this.salesRepresentatives = 0,
    this.branches = 0,
  });

  final int users;
  final int salesRepresentatives;
  final int branches;

  factory CompanyUsageCounts.fromJson(Map<String, dynamic> json) {
    return CompanyUsageCounts(
      users: (json['users'] as num?)?.toInt() ?? 0,
      salesRepresentatives:
          (json['sales_representatives'] as num?)?.toInt() ?? 0,
      branches: (json['branches'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [users, salesRepresentatives, branches];
}

/// Result of a capacity check — shared by Team, Settings, onboarding, billing.
class CapacityCheck extends Equatable {
  const CapacityCheck({
    required this.limitKey,
    required this.status,
    required this.used,
    this.limitValue,
    this.remaining,
  });

  final String limitKey;
  final CapacityStatus status;
  final int used;
  final int? limitValue;
  final int? remaining;

  bool get unlimited => status == CapacityStatus.unlimited;
  bool get canAdd => status.canAdd;

  String get usageLabel {
    if (unlimited || limitValue == null) return '$used';
    return '$used / $limitValue';
  }

  /// Soft copy for future upgrade UX — pages should not invent their own wording.
  String get limitReachedMessage =>
      "You've reached your current plan limit.";

  factory CapacityCheck.fromJson(Map<String, dynamic> json) {
    return CapacityCheck(
      limitKey: json['limit_key'] as String? ?? '',
      status: CapacityStatus.fromDb(json['status'] as String?),
      used: (json['used'] as num?)?.toInt() ?? 0,
      limitValue: (json['limit_value'] as num?)?.toInt(),
      remaining: (json['remaining'] as num?)?.toInt(),
    );
  }

  factory CapacityCheck.unlimited(String limitKey, {int used = 0}) {
    return CapacityCheck(
      limitKey: limitKey,
      status: CapacityStatus.unlimited,
      used: used,
    );
  }

  @override
  List<Object?> get props => [limitKey, status, used, limitValue, remaining];
}

/// Resolved commercial context for a workspace (plan + usage + checks).
class CompanyPlanContext extends Equatable {
  const CompanyPlanContext({
    required this.companyId,
    required this.plan,
    required this.usage,
    required this.limits,
    required this.entitlements,
    this.subscription,
    this.activePrice,
    this.checks = const {},
  });

  final String companyId;
  final SubscriptionPlan plan;
  final CompanySubscription? subscription;
  final SubscriptionPlanPrice? activePrice;
  final CompanyUsageCounts usage;
  final Map<String, int?> limits;
  final Map<String, bool> entitlements;
  final Map<String, CapacityCheck> checks;

  CapacityCheck check(String limitKey) =>
      checks[limitKey] ?? CapacityCheck.unlimited(limitKey);

  bool hasEntitlement(String key) => entitlements[key] == true;

  String get planLabel => plan.name;

  @override
  List<Object?> get props =>
      [companyId, plan, subscription, usage, limits, entitlements];
}

Map<String, int?> _parseLimits(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, int?>{};
  raw.forEach((key, value) {
    final k = key.toString();
    if (value == null) {
      out[k] = null;
    } else if (value is num) {
      out[k] = value.toInt();
    } else if (value is String) {
      out[k] = int.tryParse(value);
    }
  });
  return out;
}

Map<String, bool> _parseEntitlements(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, bool>{};
  raw.forEach((key, value) {
    if (value is bool) {
      out[key.toString()] = value;
    } else if (value is String) {
      out[key.toString()] = value.toLowerCase() == 'true';
    }
  });
  return out;
}

DateTime? _parseDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
