import 'package:sello/data/repositories/subscription_repository.dart';
import 'package:sello/shared/models/subscription_plan.dart';

/// Shared commercial capacity + entitlement resolver.
///
/// Use this from Team, Settings, onboarding, and future billing — never
/// duplicate limit numbers or entitlement checks inside feature pages.
///
/// Distinct from IAM ([PermissionService]): entitlements answer
/// "does this business's plan include the feature?", not "may this user act?".
class PlanCapacityService {
  PlanCapacityService(this._repo);

  final SubscriptionRepository _repo;

  Future<CompanyPlanContext> loadContext(String companyId) async {
    final subscription = await _repo.fetchCurrentSubscription(companyId);
    final planCode = subscription?.planCode ?? 'professional';
    final plan = await _repo.fetchPlanByCode(planCode) ??
        SubscriptionPlan(
          id: 'local:$planCode',
          code: planCode,
          name: _titleCase(planCode),
        );

    final usage = await _repo.fetchUsageCounts(companyId);
    final limits = await _repo.resolveLimits(companyId);
    final entitlements = await _repo.resolveEntitlements(companyId);

    SubscriptionPlanPrice? activePrice;
    if (subscription != null && !plan.id.startsWith('local:')) {
      final prices = await _repo.fetchActivePrices(
        planId: plan.id,
        interval: subscription.billingInterval,
        currency: subscription.currency,
      );
      if (prices.isNotEmpty) {
        activePrice = prices.first;
      }
    }

    final checks = <String, CapacityCheck>{};
    for (final key in PlanLimitKeys.all) {
      checks[key] = await _repo.checkCapacity(
        companyId: companyId,
        limitKey: key,
      );
    }

    return CompanyPlanContext(
      companyId: companyId,
      plan: plan,
      subscription: subscription,
      activePrice: activePrice,
      usage: usage,
      limits: limits.isEmpty ? plan.limits : limits,
      entitlements: entitlements.isEmpty ? plan.entitlements : entitlements,
      checks: checks,
    );
  }

  Future<CapacityCheck> canAddUser(String companyId) {
    return _repo.checkCapacity(
      companyId: companyId,
      limitKey: PlanLimitKeys.maxUsers,
    );
  }

  Future<CapacityCheck> canAddSalesRepresentative(String companyId) {
    return _repo.checkCapacity(
      companyId: companyId,
      limitKey: PlanLimitKeys.maxSalesRepresentatives,
    );
  }

  Future<CapacityCheck> canAddBranch(String companyId) {
    return _repo.checkCapacity(
      companyId: companyId,
      limitKey: PlanLimitKeys.maxBranches,
    );
  }

  Future<bool> canUseFeature({
    required String companyId,
    required String entitlementKey,
  }) {
    return _repo.hasEntitlement(
      companyId: companyId,
      entitlementKey: entitlementKey,
    );
  }

  static String _titleCase(String code) {
    if (code.isEmpty) return code;
    return code[0].toUpperCase() + code.substring(1);
  }
}
