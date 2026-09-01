import 'package:sello/shared/utils/phone_number.dart';

/// Helpers for onboarding form defaults (company code / slug generation).
abstract final class OnboardingService {
  /// Builds an uppercase company code from a business name.
  ///
  /// Example: `"Acme Corp"` → `"ACMECORP"`.
  static String generateCompanyCode(String businessName) {
    final alnum = businessName
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '')
        .trim();
    if (alnum.isEmpty) return 'BIZ';
    return alnum.length > 32 ? alnum.substring(0, 32) : alnum;
  }

  /// Candidate codes when the preferred code from [businessName] is taken.
  ///
  /// Attempt 0 is the base (`ACME`). Later attempts append `2`, `3`, …
  static String companyCodeCandidate(String businessName, int attempt) {
    final seed = generateCompanyCode(businessName);
    if (attempt <= 0) return seed;
    final suffix = '${attempt + 1}';
    final maxBase = 32 - suffix.length;
    final trimmed = seed.length > maxBase ? seed.substring(0, maxBase) : seed;
    return '$trimmed$suffix';
  }

  /// Normalizes a user-edited company code (trim + uppercase).
  static String normalizeCompanyCode(String companyCode) {
    return companyCode.trim().toUpperCase();
  }

  /// Slug candidate from a business name (`Unitech Solutions` → `unitech-solutions`).
  ///
  /// Company code stays the internal identifier; slug is user-facing.
  static String slugFromBusinessName(String businessName) {
    var slug = businessName.trim().toLowerCase();
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'-+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static String normalizeOptionalPhone(String? phone) {
    return PhoneNumber.normalizeStorage(phone) ?? '';
  }
}
