import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/billing/plan_capacity_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/subscription_plan.dart';

export 'package:sello/services/billing/plan_capacity_service.dart';

final planCapacityServiceProvider = Provider<PlanCapacityService>(
  (ref) => PlanCapacityService(ref.watch(subscriptionRepositoryProvider)),
);

/// Active commercial context for the signed-in workspace.
///
/// Soft-fails to a Professional-shaped unlimited context when the catalog
/// migration is not applied yet — keeps V1 usable during rollout.
final companyPlanContextProvider =
    FutureProvider<CompanyPlanContext?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  try {
    return await ref
        .watch(planCapacityServiceProvider)
        .loadContext(session.company.id);
  } catch (_) {
    return CompanyPlanContext(
      companyId: session.company.id,
      plan: SubscriptionPlan(
        id: 'fallback:${session.company.plan}',
        code: session.company.plan,
        name: session.company.plan,
        entitlements: const {
          PlanEntitlementKeys.reports: true,
          PlanEntitlementKeys.intelligence: true,
          PlanEntitlementKeys.advancedAnalytics: true,
          PlanEntitlementKeys.multipleBranches: true,
          PlanEntitlementKeys.advancedPermissions: true,
        },
      ),
      usage: const CompanyUsageCounts(),
      limits: const {},
      entitlements: const {
        PlanEntitlementKeys.reports: true,
        PlanEntitlementKeys.intelligence: true,
        PlanEntitlementKeys.advancedAnalytics: true,
        PlanEntitlementKeys.multipleBranches: true,
        PlanEntitlementKeys.advancedPermissions: true,
      },
    );
  }
});
