import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Branch helpers for onboarding defaults and Hub employee assignment.
class BranchRepository {
  BranchRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// Default Head Office values for first-branch provisioning.
  static const String defaultHeadOfficeName = 'Head Office';
  static const String defaultHeadOfficeCode = 'HO';

  Future<List<Branch>> fetchBranches({
    required String companyId,
    bool activeOnly = true,
  }) async {
    try {
      var query = _client
          .from('branches')
          .select(
            'id, company_id, name, code, phone, email, manager_name, address_line1, is_active',
          )
          .eq('company_id', companyId)
          .isFilter('deleted_at', null);

      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      final rows = await query.order('name');
      return (rows as List)
          .map((row) => Branch.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load branches.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to load branches.');
    }
  }

  /// Updates Head Office contact details used during first-time Owner setup.
  Future<Branch> updateContact({
    required String companyId,
    required String branchId,
    required String employeeId,
    String? phone,
    String? addressLine1,
  }) async {
    try {
      final updated = await _client
          .from('branches')
          .update({
            'phone': _blankToNull(phone),
            'address_line1': _blankToNull(addressLine1),
            'updated_by': employeeId,
          })
          .eq('id', branchId)
          .eq('company_id', companyId)
          .select(
            'id, company_id, name, code, phone, email, manager_name, address_line1, is_active',
          )
          .single();
      return Branch.fromJson(Map<String, dynamic>.from(updated));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to save branch details.'
            : error.message,
      );
    } catch (_) {
      throw const UnexpectedFailure('Unable to save branch details.');
    }
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
