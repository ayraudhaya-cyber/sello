import 'package:sello/services/onboarding/onboarding_service.dart';

/// Input for creating a new business + owner account.
class ProvisionBusinessRequest {
  const ProvisionBusinessRequest({
    required this.businessName,
    required this.companyCode,
    required this.ownerFullName,
    required this.ownerEmail,
    required this.password,
    required this.branchName,
    required this.branchCode,
    this.ownerPhone,
  });

  /// Public signup — company code and Head Office are allocated server-side.
  factory ProvisionBusinessRequest.signup({
    required String businessName,
    required String ownerFullName,
    required String ownerEmail,
    required String password,
  }) {
    return ProvisionBusinessRequest(
      businessName: businessName.trim(),
      companyCode: OnboardingService.generateCompanyCode(businessName),
      ownerFullName: ownerFullName.trim(),
      ownerEmail: ownerEmail.trim(),
      password: password,
      branchName: 'Head Office',
      branchCode: 'HO',
    );
  }

  final String businessName;
  final String companyCode;
  final String ownerFullName;
  final String ownerEmail;
  final String password;
  final String? ownerPhone;
  final String branchName;
  final String branchCode;
}

/// Non-sensitive onboarding fields persisted server-side with the auth user.
///
/// Used as `raw_user_meta_data.pending_business` at signup. Password is never
/// included. Owner email is taken from `auth.users.email` by the DB trigger.
class PendingBusinessMetadata {
  const PendingBusinessMetadata({
    required this.businessName,
    required this.companyCode,
    required this.ownerFullName,
    required this.branchName,
    required this.branchCode,
    this.ownerPhone,
  });

  final String businessName;
  final String companyCode;
  final String ownerFullName;
  final String? ownerPhone;
  final String branchName;
  final String branchCode;

  factory PendingBusinessMetadata.fromRequest(ProvisionBusinessRequest request) {
    return PendingBusinessMetadata(
      businessName: request.businessName.trim(),
      companyCode: request.companyCode.trim().toUpperCase(),
      ownerFullName: request.ownerFullName.trim(),
      ownerPhone: request.ownerPhone?.trim(),
      branchName: request.branchName.trim(),
      branchCode: request.branchCode.trim().toUpperCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'business_name': businessName,
        'company_code': companyCode,
        'owner_full_name': ownerFullName,
        if (ownerPhone != null && ownerPhone!.isNotEmpty)
          'owner_phone': ownerPhone,
        'branch_name': branchName,
        'branch_code': branchCode,
      };
}

/// IDs returned by provisioning RPCs.
class ProvisionBusinessResult {
  const ProvisionBusinessResult({
    required this.companyId,
    required this.branchId,
    required this.employeeId,
    required this.roleId,
    required this.companyCode,
    required this.slug,
    this.alreadyProvisioned = false,
  });

  final String companyId;
  final String branchId;
  final String employeeId;
  final String roleId;
  final String companyCode;
  final String slug;
  final bool alreadyProvisioned;

  factory ProvisionBusinessResult.fromJson(Map<String, dynamic> json) {
    return ProvisionBusinessResult(
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String,
      employeeId: json['employee_id'] as String,
      roleId: json['role_id'] as String,
      companyCode: json['company_code'] as String,
      slug: json['slug'] as String,
      alreadyProvisioned: json['already_provisioned'] == true,
    );
  }
}
