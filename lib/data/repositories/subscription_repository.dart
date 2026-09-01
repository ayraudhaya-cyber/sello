import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/subscription_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads plan catalog, versioned prices, and company subscription state.
///
/// Writes / lifecycle changes belong to future billing RPCs — not the client.
class SubscriptionRepository {
  SubscriptionRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<List<SubscriptionPlan>> fetchActivePlans() async {
    try {
      final rows = await _client
          .from('subscription_plans')
          .select()
          .eq('is_active', true)
          .order('display_order');
      return [
        for (final row in rows as List)
          SubscriptionPlan.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load plans.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load plans.');
    }
  }

  Future<SubscriptionPlan?> fetchPlanByCode(String code) async {
    try {
      final row = await _client
          .from('subscription_plans')
          .select()
          .eq('code', code.trim().toLowerCase())
          .maybeSingle();
      if (row == null) return null;
      return SubscriptionPlan.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load plan.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load plan.');
    }
  }

  Future<List<SubscriptionPlanPrice>> fetchActivePrices({
    String? planId,
    BillingInterval? interval,
    String currency = 'USD',
  }) async {
    try {
      var query = _client
          .from('subscription_plan_prices')
          .select()
          .eq('is_active', true)
          .eq('currency', currency.toUpperCase());
      if (planId != null) {
        query = query.eq('plan_id', planId);
      }
      if (interval != null) {
        query = query.eq('billing_interval', interval.dbValue);
      }
      final rows = await query.order('effective_from', ascending: false);
      return [
        for (final row in rows as List)
          SubscriptionPlanPrice.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load plan pricing.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load plan pricing.');
    }
  }

  Future<CompanySubscription?> fetchCurrentSubscription(String companyId) async {
    try {
      final row = await _client
          .from('company_subscriptions')
          .select()
          .eq('company_id', companyId)
          .inFilter('status', [
            'active',
            'trialing',
            'past_due',
            'grace',
          ])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return CompanySubscription.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load subscription.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load subscription.');
    }
  }

  Future<CompanyUsageCounts> fetchUsageCounts(String companyId) async {
    try {
      final result = await _client.rpc(
        'company_usage_counts',
        params: {'p_company_id': companyId},
      );
      if (result is Map) {
        return CompanyUsageCounts.fromJson(Map<String, dynamic>.from(result));
      }
      return const CompanyUsageCounts();
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load usage.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load usage.');
    }
  }

  Future<CapacityCheck> checkCapacity({
    required String companyId,
    required String limitKey,
  }) async {
    try {
      final result = await _client.rpc(
        'check_company_capacity',
        params: {
          'p_company_id': companyId,
          'p_limit_key': limitKey,
        },
      );
      if (result is Map) {
        return CapacityCheck.fromJson(Map<String, dynamic>.from(result));
      }
      return CapacityCheck.unlimited(limitKey);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to check plan capacity.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to check plan capacity.');
    }
  }

  Future<bool> hasEntitlement({
    required String companyId,
    required String entitlementKey,
  }) async {
    try {
      final result = await _client.rpc(
        'company_has_entitlement',
        params: {
          'p_company_id': companyId,
          'p_entitlement_key': entitlementKey,
        },
      );
      return result == true;
    } on PostgrestException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, int?>> resolveLimits(String companyId) async {
    try {
      final result = await _client.rpc(
        'resolve_company_plan_limits',
        params: {'p_company_id': companyId},
      );
      if (result is Map) {
        final out = <String, int?>{};
        result.forEach((key, value) {
          if (value == null) {
            out[key.toString()] = null;
          } else if (value is num) {
            out[key.toString()] = value.toInt();
          }
        });
        return out;
      }
      return const {};
    } on PostgrestException {
      return const {};
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, bool>> resolveEntitlements(String companyId) async {
    try {
      final result = await _client.rpc(
        'resolve_company_entitlements',
        params: {'p_company_id': companyId},
      );
      if (result is Map) {
        final out = <String, bool>{};
        result.forEach((key, value) {
          if (value is bool) out[key.toString()] = value;
        });
        return out;
      }
      return const {};
    } on PostgrestException {
      return const {};
    } catch (_) {
      return const {};
    }
  }
}
