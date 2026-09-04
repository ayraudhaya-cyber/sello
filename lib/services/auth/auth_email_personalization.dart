/// Flat Auth `user_metadata` fields for personalized Supabase email templates.
///
/// Templates read these via `{{ .Data.* }}`. GoTrue cannot derive an email
/// local-part in the template, so [emailLocal] is computed at write time.
abstract final class AuthEmailPersonalization {
  static const roleOwner = 'Owner';
  static const roleSalesRep = 'Sales Rep';
  static const roleManager = 'Manager';
  static const roleAdministrator = 'Administrator';

  /// Written by `invite-employee-login` so recovery UI can show invite copy.
  ///
  /// Forgot-password recovery never sets this. Cleared after the invitee
  /// successfully sets a password so later self-service resets use reset copy.
  static const teamInviteKey = 'sello_team_invite';

  static String emailLocal(String email) {
    final trimmed = email.trim().toLowerCase();
    final at = trimmed.indexOf('@');
    if (at <= 0) return trimmed;
    return trimmed.substring(0, at);
  }

  /// True when Auth user_metadata marks a Hub team invitation.
  static bool isTeamInviteMetadata(Map<String, dynamic>? metadata) =>
      metadata?[teamInviteKey] == true;

  /// Metadata merged alongside `pending_business` (or team invite fields).
  static Map<String, dynamic> fields({
    required String email,
    String? fullName,
    String? companyName,
    String? roleLabel,
  }) {
    final name = fullName?.trim() ?? '';
    final company = companyName?.trim() ?? '';
    final role = roleLabel?.trim() ?? '';
    final local = emailLocal(email);
    return {
      if (name.isNotEmpty) 'full_name': name,
      if (name.isNotEmpty) 'greeting_name': name,
      if (local.isNotEmpty) 'email_local': local,
      if (company.isNotEmpty) 'company_name': company,
      if (role.isNotEmpty) 'role_label': role,
    };
  }
}
