import 'package:sello/core/error/app_failure.dart';
import 'package:sello/shared/utils/phone_number.dart';

/// Pure validation helpers for business onboarding forms.
abstract final class OnboardingValidation {
  static final RegExp _emailPattern = RegExp(
    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    caseSensitive: false,
  );

  static final RegExp _companyCodePattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]*$');

  static final RegExp _branchCodePattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]*$');

  static String? businessName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Business name is required.';
    if (trimmed.length < 2) return 'Business name is too short.';
    if (trimmed.length > 120) return 'Business name is too long.';
    return null;
  }

  static String? companyCode(String? value) {
    final code = (value ?? '').trim().toUpperCase();
    if (code.isEmpty) return 'Company code is required.';
    if (code.length < 2) return 'Company code must be at least 2 characters.';
    if (code.length > 32) return 'Company code must be 32 characters or fewer.';
    if (!_companyCodePattern.hasMatch(code)) {
      return 'Use letters, numbers, hyphens, or underscores only.';
    }
    return null;
  }

  static String? ownerFullName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Full name is required.';
    if (trimmed.length < 2) return 'Enter your full name.';
    if (trimmed.length > 120) return 'Name is too long.';
    return null;
  }

  static String? ownerEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Email is required.';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required.';
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Confirm your password.';
    if (value != password) return 'Passwords do not match.';
    return null;
  }

  static String? ownerPhone(String? value) => PhoneNumber.validator(value);

  static String? branchName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Branch name is required.';
    if (trimmed.length > 120) return 'Branch name is too long.';
    return null;
  }

  static String? branchCode(String? value) {
    final code = (value ?? '').trim().toUpperCase();
    if (code.isEmpty) return 'Branch code is required.';
    if (code.length > 16) return 'Branch code must be 16 characters or fewer.';
    if (!_branchCodePattern.hasMatch(code)) {
      return 'Use letters, numbers, hyphens, or underscores only.';
    }
    return null;
  }

  /// Throws [ValidationFailure] if any required field is invalid.
  static void assertRequest({
    required String businessName,
    required String companyCode,
    required String ownerFullName,
    required String ownerEmail,
    required String password,
    required String branchName,
    required String branchCode,
    String? ownerPhone,
  }) {
    final errors = [
      OnboardingValidation.businessName(businessName),
      OnboardingValidation.companyCode(companyCode),
      OnboardingValidation.ownerFullName(ownerFullName),
      OnboardingValidation.ownerEmail(ownerEmail),
      OnboardingValidation.password(password),
      OnboardingValidation.ownerPhone(ownerPhone),
      OnboardingValidation.branchName(branchName),
      OnboardingValidation.branchCode(branchCode),
    ].whereType<String>().toList();

    if (errors.isNotEmpty) {
      throw ValidationFailure(errors.first);
    }
  }
}
