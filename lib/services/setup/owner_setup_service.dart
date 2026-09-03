import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/repositories/branch_repository.dart';
import 'package:sello/data/repositories/company_repository.dart';
import 'package:sello/data/repositories/company_settings_repository.dart';
import 'package:sello/data/repositories/employee_repository.dart';
import 'package:sello/services/onboarding/onboarding_validation.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/employee_upsert_input.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/models/team_invite_result.dart';
import 'package:sello/shared/utils/phone_number.dart';

/// Persists first-time Owner setup using existing company / team APIs.
class OwnerSetupService {
  OwnerSetupService({
    required CompanyRepository companies,
    required BranchRepository branches,
    required CompanySettingsRepository settings,
    required EmployeeRepository employees,
  }) : _companies = companies,
       _branches = branches,
       _settings = settings,
       _employees = employees;

  final CompanyRepository _companies;
  final BranchRepository _branches;
  final CompanySettingsRepository _settings;
  final EmployeeRepository _employees;

  Future<void> saveBusiness({
    required AppSession session,
    required String businessName,
    String? phone,
    String? address,
    ProcessedMedia? logo,
  }) async {
    final nameError = OnboardingValidation.businessName(businessName);
    if (nameError != null) throw ValidationFailure(nameError);
    final phoneError = OnboardingValidation.ownerPhone(phone);
    if (phoneError != null) throw ValidationFailure(phoneError);

    await _companies.updateProfile(
      companyId: session.company.id,
      employeeId: session.employee.id,
      name: businessName,
    );

    final branchId = session.branch?.id ?? session.employee.branchId;
    if (branchId != null && branchId.isNotEmpty) {
      await _branches.updateContact(
        companyId: session.company.id,
        branchId: branchId,
        employeeId: session.employee.id,
        phone: PhoneNumber.normalizeStorage(phone),
        addressLine1: address,
      );
    }

    if (logo != null) {
      final current = await _settings.fetchForCompany(session.company.id);
      if (!current.customBrandingEnabled) {
        throw const AuthorizationFailure(
          'Branding is not available for this business.',
        );
      }
      final url = await _settings.uploadLogo(
        companyId: session.company.id,
        media: logo,
      );
      await _settings.updateBranding(
        companyId: session.company.id,
        employeeId: session.employee.id,
        logoUrl: url,
        logoLightUrl: current.logoLightUrl,
        primaryColor: current.primaryColor,
        navBackgroundColor: current.navBackgroundColor,
      );
    }
  }

  Future<void> saveOwnerProfile({
    required AppSession session,
    required String fullName,
  }) async {
    final nameError = OnboardingValidation.ownerFullName(fullName);
    if (nameError != null) throw ValidationFailure(nameError);

    await _employees.upsertEmployee(
      companyId: session.company.id,
      actorEmployeeId: session.employee.id,
      input: EmployeeUpsertInput(
        id: session.employee.id,
        fullName: fullName,
        email: session.employee.email,
        roleId: session.employee.roleId,
        employmentStatus: session.employee.employmentStatus,
        phone: session.employee.phone,
        employeeCode: session.employee.employeeCode,
        branchId: session.employee.branchId,
      ),
    );
  }

  Future<TeamInviteResult?> addSalesRep({
    required AppSession session,
    required String fullName,
    required String email,
    String? phone,
  }) async {
    final nameError = OnboardingValidation.ownerFullName(fullName);
    if (nameError != null) throw ValidationFailure(nameError);
    final emailError = OnboardingValidation.ownerEmail(email);
    if (emailError != null) throw ValidationFailure(emailError);
    final phoneError = OnboardingValidation.ownerPhone(phone);
    if (phoneError != null) throw ValidationFailure(phoneError);

    final roles = await _employees.fetchAssignableRoles();
    final salesRole = roles.where(
      (role) => role.code == 'sales_representative',
    );
    if (salesRole.isEmpty) {
      throw const UnexpectedFailure('Sales Rep role is not available.');
    }

    // If a previous attempt created the employee but the invite failed,
    // find the existing row and just re-send the invite instead of inserting
    // a duplicate (which would violate employees_company_email_active_key).
    final existing = await _employees.findEmployeeByEmail(
      companyId: session.company.id,
      email: email,
    );

    if (existing != null) {
      return _employees.sendLoginInvite(
        companyId: session.company.id,
        actorEmployeeId: session.employee.id,
        employeeId: existing.id,
      );
    }

    final result = await _employees.upsertEmployee(
      companyId: session.company.id,
      actorEmployeeId: session.employee.id,
      input: EmployeeUpsertInput(
        fullName: fullName,
        email: email,
        roleId: salesRole.first.id,
        employmentStatus: EmploymentStatus.active,
        phone: PhoneNumber.normalizeStorage(phone),
        branchId: session.branch?.id ?? session.employee.branchId,
      ),
    );
    return result.invite;
  }

  Future<void> complete(AppSession session) {
    return _settings.markOwnerSetupCompleted(
      companyId: session.company.id,
      employeeId: session.employee.id,
    );
  }
}
