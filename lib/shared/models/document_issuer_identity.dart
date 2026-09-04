import 'package:equatable/equatable.dart';

/// Resolves tenant issuer identity for customer-facing invoices / receipts.
///
/// Never uses the Sello mark. Business name ([companyName] from `companies.name`)
/// is the mandatory fallback when no logo exists.
class DocumentIssuerIdentity extends Equatable {
  const DocumentIssuerIdentity({
    required this.showLogo,
    required this.showBusinessName,
    this.logoUrl,
    required this.businessName,
  });

  final bool showLogo;
  final bool showBusinessName;
  final String? logoUrl;

  /// Always from `companies.name` (never a separate legal-name field).
  final String businessName;

  /// Prefer light-surface logo, then dark chrome logo.
  static String? resolveLogoUrl({
    String? logoLightUrl,
    String? logoUrl,
  }) {
    return _usable(logoLightUrl) ?? _usable(logoUrl);
  }

  static DocumentIssuerIdentity resolve({
    required String companyName,
    String? logoUrl,
    String? logoLightUrl,
    bool showBusinessNameWithLogo = false,
  }) {
    final name = companyName.trim().isEmpty ? 'Business' : companyName.trim();
    final logo = resolveLogoUrl(
      logoLightUrl: logoLightUrl,
      logoUrl: logoUrl,
    );
    if (logo != null) {
      return DocumentIssuerIdentity(
        showLogo: true,
        showBusinessName: showBusinessNameWithLogo,
        logoUrl: logo,
        businessName: name,
      );
    }
    return DocumentIssuerIdentity(
      showLogo: false,
      showBusinessName: true,
      logoUrl: null,
      businessName: name,
    );
  }

  static String? _usable(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return trimmed;
  }

  @override
  List<Object?> get props =>
      [showLogo, showBusinessName, logoUrl, businessName];
}
