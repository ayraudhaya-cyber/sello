/// Temporary invite-only gate for NEW self-service tenants.
///
/// Server-side source of truth is `sello_tenant_invites` +
/// `sello_signup_is_allowed`. This Dart mirror is for UX copy and tests only.
abstract final class SignupInvitePolicy {
  static const title = 'Sello is currently available by invitation.';

  static const support =
      'Please use the email address that was invited to your Sello workspace.';

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// Matches the SQL rule: only `approved` and unexpired rows may create a tenant.
  static bool canCreateTenant({
    required String status,
    DateTime? expiresAt,
    DateTime? now,
  }) {
    if (status != 'approved') return false;
    final current = now ?? DateTime.now().toUtc();
    if (expiresAt != null && !expiresAt.toUtc().isAfter(current)) {
      return false;
    }
    return true;
  }

  static bool isInviteGateError(String message) {
    final upper = message.toUpperCase();
    return upper.contains('SIGNUP_NOT_INVITED') || message.trim() == title;
  }
}
