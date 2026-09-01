/// Shared failure type for future data/application layers.
sealed class AppFailure {
  const AppFailure(this.message);
  final String message;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'Network error. Please try again.']);
}

/// Device is offline — work should be queued for synchronization.
final class OfflineFailure extends AppFailure {
  const OfflineFailure([
    super.message =
        'You are offline. Your work is saved and will sync when you reconnect.',
  ]);
}

/// Synchronization failed after retries or a conflict needs review.
final class SyncFailure extends AppFailure {
  const SyncFailure([
    super.message =
        'Some changes could not sync. Sello will keep trying safely.',
  ]);
}

final class AuthFailure extends AppFailure {
  const AuthFailure([super.message = 'Authentication failed.']);
}

/// Auth user exists but has no linked employee / company yet.
final class UnlinkedEmployeeFailure extends AuthFailure {
  const UnlinkedEmployeeFailure([
    super.message =
        'No employee profile is linked to this account. Contact your administrator.',
  ]);
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure([super.message = 'Please check your input.']);
}

final class ProvisioningFailure extends AppFailure {
  const ProvisioningFailure([
    super.message = 'Unable to create your business. Please try again.',
  ]);
}

/// Sign-up succeeded but email confirmation is required before provisioning.
final class EmailConfirmationRequiredFailure extends AppFailure {
  const EmailConfirmationRequiredFailure(this.email)
      : super(
          'We sent a verification email. Please verify your email to continue.',
        );

  final String email;
}

/// Self-service signup is invite-only for new companies.
final class SignupInvitationFailure extends AppFailure {
  const SignupInvitationFailure()
      : super('Sello is currently available by invitation.');
}

/// Auth user has no employee and no completable server-side pending onboarding.
final class NeedsOnboardingFailure extends AppFailure {
  const NeedsOnboardingFailure([
    super.message =
        'Finish creating your business to continue.',
  ]);
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([super.message = 'Something went wrong.']);
}

/// Caller lacks a required module permission (IAM).
final class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure([
    super.message = 'You do not have permission to perform this action.',
  ]);
}
