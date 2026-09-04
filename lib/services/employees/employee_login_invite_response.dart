import 'dart:convert';

import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/auth/auth_redirect_url.dart';
import 'package:sello/shared/models/team_invite_result.dart';

/// Parses `invite-employee-login` Edge Function responses.
abstract final class EmployeeLoginInviteResponse {
  static const functionName = 'invite-employee-login';

  static Map<String, dynamic>? asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return null;
  }

  static TeamInviteResult? tryParseSuccess(Map<String, dynamic> data) {
    if (data['ok'] != true) return null;
    return TeamInviteResult(
      accountReady: data['account_ready'] == true,
      emailDelivered: data['email_delivered'] == true,
    );
  }

  static String failureMessage(Map<String, dynamic>? data) {
    final reason = data?['reason']?.toString().trim().toLowerCase() ?? '';
    switch (reason) {
      case 'forbidden':
        return 'You do not have permission to invite team members.';
      case 'unauthorized':
        return 'Sign in required.';
      case 'not_found':
        return 'Team member not found.';
      case 'inactive':
        return 'Only active team members can receive an invitation.';
      case 'auth_user_in_use':
        return 'This email already has a Sello login linked to another person.';
      case 'already_linked_other':
        return 'This team member is already linked to a different login.';
      case 'auth_create_failed':
      case 'auth_lookup_failed':
        return 'Unable to create a login for this email. Try a different email.';
      case 'link_failed':
        return 'Login was created but could not be linked. Try Send invite again.';
      case 'server_misconfigured':
        return 'Invitation service is not configured. Contact Sello support.';
      default:
        return 'Unable to send invitation. Please try again.';
    }
  }

  /// Recovery emails must land on /login (existing password-recovery UX).
  static String? redirectToForCurrentOrigin() =>
      AuthRedirectUrl.forPath(RoutePaths.login);
}
