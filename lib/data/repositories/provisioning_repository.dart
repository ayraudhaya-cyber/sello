import 'package:sello/core/error/app_failure.dart';
import 'package:sello/shared/models/provision_business_request.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls business-provisioning RPCs (SECURITY DEFINER on the server).
class ProvisioningRepository {
  ProvisioningRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<bool> isOwnerEmailAvailable(String email) async {
    try {
      final result = await _client.rpc(
        'is_owner_email_available',
        params: {'p_email': email.trim().toLowerCase()},
      );
      return result == true;
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Server-side invite gate. Clients cannot approve themselves.
  Future<bool> isSignupAllowed(String email) async {
    try {
      final result = await _client.rpc(
        'sello_signup_is_allowed',
        params: {'p_email': email.trim().toLowerCase()},
      );
      return result == true;
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(_mapProvisionError(error));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Saves / replaces the caller's pending onboarding row (`auth.uid()`).
  Future<void> upsertPendingBusinessProvision({
    required String businessName,
    required String companyCode,
    required String ownerFullName,
    String? ownerPhone,
    required String branchName,
    required String branchCode,
  }) async {
    try {
      await _client.rpc(
        'upsert_pending_business_provision',
        params: {
          'p_business_name': businessName.trim(),
          'p_company_code': companyCode.trim().toUpperCase(),
          'p_owner_full_name': ownerFullName.trim(),
          'p_owner_phone': (ownerPhone == null || ownerPhone.trim().isEmpty)
              ? null
              : ownerPhone.trim(),
          'p_branch_name': branchName.trim(),
          'p_branch_code': branchCode.trim().toUpperCase(),
        },
      );
    } on PostgrestException catch (error) {
      if (error.message.toUpperCase().contains('SIGNUP_NOT_INVITED')) {
        throw const SignupInvitationFailure();
      }
      throw ProvisioningFailure(_mapProvisionError(error));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Completes tenant creation from the caller's server-side pending row.
  ///
  /// Idempotent: if the employee already exists, returns the existing tenant.
  Future<ProvisionBusinessResult> completeBusinessOnboarding() async {
    try {
      final result = await _client.rpc('complete_business_onboarding');

      if (result is! Map) {
        throw const ProvisioningFailure(
          'Unexpected response while creating your business.',
        );
      }

      return ProvisionBusinessResult.fromJson(
        Map<String, dynamic>.from(result),
      );
    } on ProvisioningFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapCompleteError(error);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Deletes the current auth user when no employee row exists.
  Future<void> rollbackFailedProvisioning() async {
    try {
      await _client.rpc('rollback_failed_provisioning');
    } on PostgrestException catch (error) {
      throw ProvisioningFailure(error.message);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  static AppFailure _mapCompleteError(PostgrestException error) {
    final upper = error.message.toUpperCase();
    if (upper.contains('SIGNUP_NOT_INVITED')) {
      return const SignupInvitationFailure();
    }
    if (upper.contains('NO_PENDING_ONBOARDING')) {
      return const NeedsOnboardingFailure();
    }
    if (upper.contains('PENDING_EXPIRED')) {
      return const NeedsOnboardingFailure(
        'Your business setup expired. Please create your business again.',
      );
    }
    return ProvisioningFailure(_mapProvisionError(error));
  }

  static String _mapProvisionError(PostgrestException error) {
    final message = error.message;
    final upper = message.toUpperCase();

    if (upper.contains('SIGNUP_NOT_INVITED')) {
      return const SignupInvitationFailure().message;
    }
    if (upper.contains('COMPANY_CODE_TAKEN')) {
      return 'That company code is already in use. Choose another.';
    }
    if (upper.contains('EMAIL_TAKEN') || upper.contains('EMAIL_MISMATCH')) {
      return 'That email cannot be used for a new business.';
    }
    if (upper.contains('ALREADY_PROVISIONED')) {
      return 'This account already belongs to a business. Please sign in.';
    }
    if (upper.contains('NOT_AUTHENTICATED')) {
      return 'Your session expired. Please sign in and try again.';
    }
    if (upper.contains('INVALID_COMPANY_CODE')) {
      return 'That company code is not valid. Please choose another.';
    }
    if (upper.contains('INVALID_BRANCH')) {
      return 'Please check your branch name and code.';
    }
    if (upper.contains('INVALID_BUSINESS_NAME') ||
        upper.contains('INVALID_OWNER_NAME')) {
      return 'Please check the business and owner details.';
    }
    if (message.trim().isEmpty) {
      return 'Unable to create your business. Please try again.';
    }
    return 'Unable to create your business. Please try again.';
  }
}
