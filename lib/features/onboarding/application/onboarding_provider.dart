import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/provisioning_repository.dart';
import 'package:sello/services/onboarding/onboarding_service.dart';
import 'package:sello/services/onboarding/onboarding_validation.dart';
import 'package:sello/services/onboarding/signup_invite_policy.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/provision_business_request.dart';

class SignupDraft {
  const SignupDraft({
    this.fullName = '',
    this.email = '',
    this.password = '',
    this.confirmPassword = '',
    this.businessName = '',
    this.isCheckingEmail = false,
    this.isSubmitting = false,
    this.fieldError,
    this.errorMessage,
    this.inviteRequired = false,
  });

  final String fullName;
  final String email;
  final String password;
  final String confirmPassword;
  final String businessName;
  final bool isCheckingEmail;
  final bool isSubmitting;
  final String? fieldError;
  final String? errorMessage;
  final bool inviteRequired;

  bool get isBusy => isCheckingEmail || isSubmitting;

  ProvisionBusinessRequest toRequest() {
    return ProvisionBusinessRequest.signup(
      businessName: businessName,
      ownerFullName: fullName,
      ownerEmail: OnboardingService.normalizeEmail(email),
      password: password,
    );
  }

  SignupDraft copyWith({
    String? fullName,
    String? email,
    String? password,
    String? confirmPassword,
    String? businessName,
    bool? isCheckingEmail,
    bool? isSubmitting,
    String? fieldError,
    String? errorMessage,
    bool? inviteRequired,
    bool clearFieldError = false,
    bool clearError = false,
  }) {
    return SignupDraft(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      businessName: businessName ?? this.businessName,
      isCheckingEmail: isCheckingEmail ?? this.isCheckingEmail,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      fieldError: clearFieldError ? null : (fieldError ?? this.fieldError),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      inviteRequired: inviteRequired ?? this.inviteRequired,
    );
  }
}

class SignupNotifier extends Notifier<SignupDraft> {
  ProvisioningRepository get _provisioning =>
      ref.read(provisioningRepositoryProvider);

  @override
  SignupDraft build() => const SignupDraft();

  void updateFullName(String value) {
    state = state.copyWith(
      fullName: value,
      inviteRequired: false,
      clearFieldError: true,
      clearError: true,
    );
  }

  void updateEmail(String value) {
    state = state.copyWith(
      email: value,
      inviteRequired: false,
      clearFieldError: true,
      clearError: true,
    );
  }

  void updatePassword(String value) {
    state = state.copyWith(
      password: value,
      clearFieldError: true,
      clearError: true,
    );
  }

  void updateConfirmPassword(String value) {
    state = state.copyWith(
      confirmPassword: value,
      clearFieldError: true,
      clearError: true,
    );
  }

  void updateBusinessName(String value) {
    state = state.copyWith(
      businessName: value,
      clearFieldError: true,
      clearError: true,
    );
  }

  String? validate() {
    return OnboardingValidation.ownerFullName(state.fullName) ??
        OnboardingValidation.ownerEmail(state.email) ??
        OnboardingValidation.password(state.password) ??
        OnboardingValidation.confirmPassword(
          state.confirmPassword,
          state.password,
        ) ??
        OnboardingValidation.businessName(state.businessName);
  }

  Future<void> submit() async {
    if (state.isBusy) return;

    final validationError = validate();
    if (validationError != null) {
      state = state.copyWith(fieldError: validationError);
      return;
    }

    state = state.copyWith(
      isCheckingEmail: true,
      isSubmitting: false,
      inviteRequired: false,
      clearFieldError: true,
      clearError: true,
    );

    try {
      final invited = await _provisioning.isSignupAllowed(state.email);
      if (!invited) {
        state = state.copyWith(
          isCheckingEmail: false,
          inviteRequired: true,
          errorMessage: SignupInvitePolicy.title,
        );
        return;
      }

      final available = await _provisioning.isOwnerEmailAvailable(state.email);
      if (!available) {
        state = state.copyWith(
          isCheckingEmail: false,
          inviteRequired: false,
          fieldError:
              'An account with this email already exists. Sign in instead.',
        );
        return;
      }
    } on SignupInvitationFailure catch (failure) {
      state = state.copyWith(
        isCheckingEmail: false,
        inviteRequired: true,
        errorMessage: failure.message,
      );
      return;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isCheckingEmail: false,
        errorMessage: failure.message,
      );
      return;
    } catch (_) {
      state = state.copyWith(
        isCheckingEmail: false,
        errorMessage: 'Unable to check that email. Please try again.',
      );
      return;
    }

    state = state.copyWith(
      isCheckingEmail: false,
      isSubmitting: true,
      clearFieldError: true,
      clearError: true,
    );

    await ref.read(authSessionProvider.notifier).provisionBusiness(
          state.toRequest(),
        );

    final auth = ref.read(authSessionProvider);
    if (auth.isAuthenticated || auth.awaitingEmailConfirmation) {
      state = state.copyWith(isSubmitting: false);
      return;
    }

    state = state.copyWith(
      isSubmitting: false,
      inviteRequired: SignupInvitePolicy.isInviteGateError(
        auth.errorMessage ?? '',
      ),
      errorMessage: auth.errorMessage ??
          'Unable to create your account. Please try again.',
    );
  }
}

final onboardingProvider = NotifierProvider<SignupNotifier, SignupDraft>(
  SignupNotifier.new,
);
