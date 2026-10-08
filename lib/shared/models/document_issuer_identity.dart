import 'package:equatable/equatable.dart';

/// Printed customer-document layout. Standard is the current spacious invoice.
enum DocumentPrintTemplate {
  standard,
  compact;

  static DocumentPrintTemplate fromDb(String? value) {
    return value == 'compact'
        ? DocumentPrintTemplate.compact
        : DocumentPrintTemplate.standard;
  }

  String get dbValue => switch (this) {
    DocumentPrintTemplate.standard => 'standard',
    DocumentPrintTemplate.compact => 'compact',
  };

  String get label => switch (this) {
    DocumentPrintTemplate.standard => 'Standard',
    DocumentPrintTemplate.compact => 'Compact',
  };
}

/// Resolves tenant issuer identity for customer-facing invoices / receipts.
///
/// Never uses the Sello mark. Business name ([companyName] from `companies.name`)
/// is the mandatory fallback when no document logo exists.
class DocumentIssuerIdentity extends Equatable {
  const DocumentIssuerIdentity({
    required this.showLogo,
    required this.showBusinessName,
    this.logoUrl,
    required this.businessName,
    this.address,
    this.phone,
    this.email,
    this.terms,
    this.tagline,
    this.template = DocumentPrintTemplate.standard,
    this.logoPrintBlack = false,
    this.authorizedSignatureUrl,
  });

  final bool showLogo;
  final bool showBusinessName;

  /// Resolved [CompanySettings.documentLogoUrl] when usable.
  final String? logoUrl;

  /// Always from `companies.name` (never a separate legal-name field).
  final String businessName;

  /// Optional contact block from company_settings.document_*.
  final String? address;
  final String? phone;
  final String? email;

  /// Optional terms / footer from company_settings.document_terms.
  final String? terms;

  /// Optional closing line from company_settings.document_tagline.
  final String? tagline;

  /// Print layout. Compact is a dense solid-black sheet for dot-matrix printers.
  final DocumentPrintTemplate template;

  /// Compact print only: render logo ink as solid black. PNG alpha stays clear.
  final bool logoPrintBlack;

  /// Optional signature printed above Authorized by on compact invoices.
  final String? authorizedSignatureUrl;

  bool get printLogoBlack =>
      template == DocumentPrintTemplate.compact && logoPrintBlack;

  bool get hasContactBlock =>
      (address != null && address!.isNotEmpty) ||
      (phone != null && phone!.isNotEmpty) ||
      (email != null && email!.isNotEmpty);

  bool get hasTerms => terms != null && terms!.isNotEmpty;

  bool get hasTagline => tagline != null && tagline!.isNotEmpty;

  static String? resolveLogoUrl(String? documentLogoUrl) {
    return _usable(documentLogoUrl);
  }

  static DocumentIssuerIdentity resolve({
    required String companyName,
    String? documentLogoUrl,
    bool showBusinessNameWithLogo = false,
    String? address,
    String? phone,
    String? email,
    String? terms,
    String? tagline,
    DocumentPrintTemplate template = DocumentPrintTemplate.standard,
    bool logoPrintBlack = false,
    String? authorizedSignatureUrl,
  }) {
    final name = companyName.trim().isEmpty ? 'Business' : companyName.trim();
    final logo = resolveLogoUrl(documentLogoUrl);
    final resolvedAddress = _trimOrNull(address);
    final resolvedPhone = _trimOrNull(phone);
    final resolvedEmail = _trimOrNull(email);
    final resolvedTerms = _trimOrNull(terms);
    final resolvedTagline = _trimOrNull(tagline);
    final signature = resolveLogoUrl(authorizedSignatureUrl);
    if (logo != null) {
      return DocumentIssuerIdentity(
        showLogo: true,
        showBusinessName: showBusinessNameWithLogo,
        logoUrl: logo,
        businessName: name,
        address: resolvedAddress,
        phone: resolvedPhone,
        email: resolvedEmail,
        terms: resolvedTerms,
        tagline: resolvedTagline,
        template: template,
        logoPrintBlack: logoPrintBlack,
        authorizedSignatureUrl: signature,
      );
    }
    return DocumentIssuerIdentity(
      showLogo: false,
      showBusinessName: true,
      logoUrl: null,
      businessName: name,
      address: resolvedAddress,
      phone: resolvedPhone,
      email: resolvedEmail,
      terms: resolvedTerms,
      tagline: resolvedTagline,
      template: template,
      logoPrintBlack: logoPrintBlack,
      authorizedSignatureUrl: signature,
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

  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  List<Object?> get props => [
    showLogo,
    showBusinessName,
    logoUrl,
    businessName,
    address,
    phone,
    email,
    terms,
    tagline,
    template,
    logoPrintBlack,
    authorizedSignatureUrl,
  ];
}
