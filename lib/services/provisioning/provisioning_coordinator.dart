import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/company_repository.dart';
import 'package:sello/data/repositories/provisioning_repository.dart';
import 'package:sello/services/auth/auth_service.dart';
import 'package:sello/services/onboarding/onboarding_service.dart';
import 'package:sello/services/onboarding/onboarding_validation.dart';
import 'package:sello/services/onboarding/signup_invite_policy.dart';
import 'package:sello/services/session/session_service.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/provision_business_request.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Orchestrates auth signup + server-side pending onboarding + session.
///
/// Architecture:
/// 1. Validate + availability checks.
/// 2. Create Auth user with `pending_business` metadata (no password in meta).
///    A DB trigger writes `pending_business_provisions` (cross-device).
/// 3. When a session exists, call `complete_business_onboarding` (idempotent).
/// 4. Build [AppSession].
///
/// Email confirmation: signup may return a user without a session. Pending
/// data is already on the server; completion runs after verify + sign-in.
class ProvisioningCoordinator {
  ProvisioningCoordinator({
    required AuthService authService,
    required CompanyRepository companyRepository,
    required ProvisioningRepository provisioningRepository,
    required SessionService sessionService,
  })  : _auth = authService,
        _companies = companyRepository,
        _provisioning = provisioningRepository,
        _sessions = sessionService;

  final AuthService _auth;
  final CompanyRepository _companies;
  final ProvisioningRepository _provisioning;
  final SessionService _sessions;

  Future<AppSession> provision(ProvisionBusinessRequest request) async {
    final businessName = request.businessName.trim();
    final companyCode = await _allocateCompanyCode(businessName);
    final ownerFullName = request.ownerFullName.trim();
    final ownerEmail = OnboardingService.normalizeEmail(request.ownerEmail);
    final password = request.password;
    final ownerPhone = OnboardingService.normalizeOptionalPhone(
      request.ownerPhone,
    );
    final branchName = request.branchName.trim().isEmpty
        ? 'Head Office'
        : request.branchName.trim();
    final branchCode = request.branchCode.trim().isEmpty
        ? 'HO'
        : request.branchCode.trim().toUpperCase();

    OnboardingValidation.assertRequest(
      businessName: businessName,
      companyCode: companyCode,
      ownerFullName: ownerFullName,
      ownerEmail: ownerEmail,
      password: password,
      ownerPhone: ownerPhone.isEmpty ? null : ownerPhone,
      branchName: branchName,
      branchCode: branchCode,
    );

    final metadata = PendingBusinessMetadata(
      businessName: businessName,
      companyCode: companyCode,
      ownerFullName: ownerFullName,
      ownerPhone: ownerPhone.isEmpty ? null : ownerPhone,
      branchName: branchName,
      branchCode: branchCode,
    );

    User? user;
    var createdAuthUser = false;
    var requiresEmailConfirmation = false;

    try {
      final existing = _auth.currentUser;
      final isExistingOwner =
          existing != null &&
          OnboardingService.normalizeEmail(existing.email ?? '') == ownerEmail;

      final invited = await _provisioning.isSignupAllowed(ownerEmail);
      if (!invited) {
        throw const SignupInvitationFailure();
      }

      if (isExistingOwner) {
        // Recovery: auth session exists but tenant was never created.
        user = existing;
        await _provisioning.upsertPendingBusinessProvision(
          businessName: businessName,
          companyCode: companyCode,
          ownerFullName: ownerFullName,
          ownerPhone: ownerPhone.isEmpty ? null : ownerPhone,
          branchName: branchName,
          branchCode: branchCode,
        );
      } else {
        final emailAvailable =
            await _provisioning.isOwnerEmailAvailable(ownerEmail);
        if (!emailAvailable) {
          throw const ValidationFailure(
            'An account with this email already exists. Sign in instead.',
          );
        }

        if (existing != null) {
          await _auth.signOut();
        }

        final response = await _auth.signUpWithEmailPassword(
          email: ownerEmail,
          password: password,
          pendingBusiness: metadata.toJson(),
        );
        user = response.user ?? _auth.currentUser;
        createdAuthUser = true;

        if (user == null) {
          throw const AuthFailure(
            'Unable to create your account. Please try again.',
          );
        }

        if (_auth.currentSession == null) {
          // Pending row is already on the server via the auth trigger.
          requiresEmailConfirmation = true;
          throw EmailConfirmationRequiredFailure(ownerEmail);
        }
      }

      await _provisioning.completeBusinessOnboarding();
      return _sessions.buildSession(user);
    } on SignupInvitationFailure {
      rethrow;
    } on AppFailure catch (failure) {
      if (SignupInvitePolicy.isInviteGateError(failure.message)) {
        throw const SignupInvitationFailure();
      }
      await _safeRollback(
        createdAuthUser: createdAuthUser,
        requiresEmailConfirmation: requiresEmailConfirmation,
      );
      rethrow;
    } catch (error) {
      await _safeRollback(
        createdAuthUser: createdAuthUser,
        requiresEmailConfirmation: requiresEmailConfirmation,
      );
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Completes server-side pending onboarding for the current auth user.
  ///
  /// Idempotent: a refresh or retry returns the existing Owner tenant.
  Future<AppSession> completePendingOnboarding() async {
    final user = _auth.currentUser;
    final session = _auth.currentSession;
    if (user == null || session == null) {
      throw const AuthFailure(
        'Your session expired. Please sign in to finish setup.',
      );
    }

    await _provisioning.completeBusinessOnboarding();
    return _sessions.buildSession(user);
  }

  Future<void> _safeRollback({
    required bool createdAuthUser,
    required bool requiresEmailConfirmation,
  }) async {
    if (!createdAuthUser && _auth.currentUser == null) return;
    // Keep the auth user + server pending row when email confirmation is needed.
    if (requiresEmailConfirmation) return;

    try {
      await _provisioning.rollbackFailedProvisioning();
    } catch (_) {
      // Best effort — auth user may remain if delete is blocked.
    }

    try {
      await _auth.signOut();
    } catch (_) {
      // Ignore secondary sign-out errors.
    }
  }

  Future<String> _allocateCompanyCode(String businessName) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final code = OnboardingService.companyCodeCandidate(businessName, attempt);
      try {
        if (await _companies.isCompanyCodeAvailable(code)) return code;
      } on AppFailure {
        if (attempt == 19) rethrow;
      }
    }
    final fallback = OnboardingService.generateCompanyCode(businessName);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final suffix = '$stamp';
    final maxBase = 32 - suffix.length;
    final trimmed =
        fallback.length > maxBase ? fallback.substring(0, maxBase) : fallback;
    return '$trimmed$suffix';
  }
}
