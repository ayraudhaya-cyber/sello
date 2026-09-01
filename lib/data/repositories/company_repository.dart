import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/company.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Company tenancy reads used during onboarding.
class CompanyRepository {
  CompanyRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// Returns true when [companyCode] is free for a new tenant.
  Future<bool> isCompanyCodeAvailable(String companyCode) async {
    try {
      final result = await _client.rpc(
        'is_company_code_available',
        params: {'p_company_code': companyCode.trim().toUpperCase()},
      );
      return result == true;
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Updates the company display name. Owners only (enforced by RLS).
  Future<Company> updateProfile({
    required String companyId,
    required String employeeId,
    required String name,
  }) async {
    final trimmed = name.trim();
    try {
      final updated = await _client
          .from('companies')
          .update({
            'name': trimmed,
            'legal_name': trimmed,
            'updated_by': employeeId,
          })
          .eq('id', companyId)
          .select(
            'id, name, legal_name, company_code, slug, is_active, plan, '
            'subscription_status, activated_at, expires_at',
          )
          .single();
      return Company.fromJson(Map<String, dynamic>.from(updated));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to save business name.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }
}
