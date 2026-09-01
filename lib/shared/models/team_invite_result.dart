import 'package:sello/shared/models/employee_summary.dart';

/// Outcome of creating a Sello login and sending the welcome invitation.
class TeamInviteResult {
  const TeamInviteResult({
    required this.accountReady,
    required this.emailDelivered,
  });

  /// Sello account exists and is linked to the team member.
  final bool accountReady;

  /// Invitation email was accepted by the mail provider.
  final bool emailDelivered;

  bool get emailUnavailable => accountReady && !emailDelivered;
}

/// Result of saving a team member (create always provisions access).
class EmployeeUpsertResult {
  const EmployeeUpsertResult({
    required this.employee,
    this.invite,
  });

  final EmployeeSummary employee;
  final TeamInviteResult? invite;
}
