import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/company_settings_repository.dart';
import 'package:sello/data/repositories/employee_repository.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds [AppSession] from an authenticated Supabase [User].
class SessionService {
  SessionService({
    EmployeeRepository? employeeRepository,
    CompanySettingsRepository? settingsRepository,
  })  : _employees = employeeRepository ?? EmployeeRepository(),
        _settings = settingsRepository ?? CompanySettingsRepository();

  final EmployeeRepository _employees;
  final CompanySettingsRepository _settings;

  Future<AppSession> buildSession(User user) async {
    final context = await _employees.fetchContextByUserId(
      user.id,
      email: user.email,
    );

    final ownerSetupCompleted = await _settings.fetchOwnerSetupCompleted(
      context.company.id,
    );

    final session = AppSession(
      authUser: user,
      employee: context.employee,
      company: context.company,
      branch: context.branch,
      role: context.role,
      ownerSetupCompleted: ownerSetupCompleted,
    );

    try {
      session.appRole;
    } on StateError {
      throw const AuthFailure(
        'Your account role is not supported. Contact your administrator.',
      );
    }

    return session;
  }
}
