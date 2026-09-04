import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/client_branding.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/models/order_document.dart';

void main() {
  group('DocumentIssuerIdentity', () {
    test('no logo always shows business name', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        showBusinessNameWithLogo: false,
      );
      expect(identity.showLogo, isFalse);
      expect(identity.showBusinessName, isTrue);
      expect(identity.businessName, 'Namson Lanka');
      expect(identity.logoUrl, isNull);
    });

    test('logo only when document logo exists and toggle is off', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        documentLogoUrl: 'https://cdn.example.com/document-logo.png',
        showBusinessNameWithLogo: false,
      );
      expect(identity.showLogo, isTrue);
      expect(identity.showBusinessName, isFalse);
      expect(identity.logoUrl, 'https://cdn.example.com/document-logo.png');
    });

    test('logo + business name when toggle is on', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        documentLogoUrl: 'https://cdn.example.com/document-logo.png',
        showBusinessNameWithLogo: true,
      );
      expect(identity.showLogo, isTrue);
      expect(identity.showBusinessName, isTrue);
      expect(identity.logoUrl, 'https://cdn.example.com/document-logo.png');
    });

    test('ignores brand asset URLs — only document_logo_url counts', () {
      // Brand assets must not resolve as the document issuer mark.
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        documentLogoUrl: null,
        showBusinessNameWithLogo: true,
      );
      expect(identity.showLogo, isFalse);
      expect(identity.showBusinessName, isTrue);
    });

    test('ignores name toggle when no logo exists', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        showBusinessNameWithLogo: true,
      );
      expect(identity.showLogo, isFalse);
      expect(identity.showBusinessName, isTrue);
    });

    test('empty company name falls back to Business', () {
      final identity = DocumentIssuerIdentity.resolve(companyName: '  ');
      expect(identity.businessName, 'Business');
      expect(identity.showBusinessName, isTrue);
    });
  });

  group('document logo vs brand assets independence', () {
    test('CompanySettings keeps document and brand logos on separate fields', () {
      final settings = CompanySettings.fromJson(_row({
        'logo_url': 'https://cdn.example.com/brand-dark.png',
        'logo_light_url': 'https://cdn.example.com/brand-light.png',
        'document_logo_url': 'https://cdn.example.com/document-logo.png',
        'custom_branding_enabled': true,
      }));

      expect(settings.documentLogoUrl, 'https://cdn.example.com/document-logo.png');
      expect(settings.logoUrl, 'https://cdn.example.com/brand-dark.png');
      expect(settings.logoLightUrl, 'https://cdn.example.com/brand-light.png');

      final branding = ClientBranding.fromSettings(settings);
      expect(branding.logoUrl, 'https://cdn.example.com/brand-dark.png');
      expect(branding.logoLightUrl, 'https://cdn.example.com/brand-light.png');

      final issuer = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        documentLogoUrl: settings.documentLogoUrl,
      );
      expect(issuer.logoUrl, 'https://cdn.example.com/document-logo.png');
      expect(issuer.logoUrl, isNot(branding.logoUrl));
    });

    test('document logo without Custom Branding still resolves for documents', () {
      final settings = CompanySettings.fromJson(_row({
        'document_logo_url': 'https://cdn.example.com/document-logo.png',
        'custom_branding_enabled': false,
        'logo_url': 'https://cdn.example.com/should-not-matter.png',
      }));

      final branding = ClientBranding.fromSettings(settings);
      expect(branding.hasCustomLogo, isFalse);
      expect(branding.logoUrl, isNull);

      final issuer = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        documentLogoUrl: settings.documentLogoUrl,
        showBusinessNameWithLogo: false,
      );
      expect(issuer.showLogo, isTrue);
      expect(issuer.showBusinessName, isFalse);
      expect(issuer.logoUrl, 'https://cdn.example.com/document-logo.png');
    });

    test('copyWith can clear document logo without clearing brand assets', () {
      final settings = CompanySettings.fromJson(_row({
        'logo_url': 'https://cdn.example.com/brand-dark.png',
        'document_logo_url': 'https://cdn.example.com/document-logo.png',
        'custom_branding_enabled': true,
      }));
      final updated = settings.copyWith(clearDocumentLogoUrl: true);
      expect(updated.documentLogoUrl, isNull);
      expect(updated.logoUrl, 'https://cdn.example.com/brand-dark.png');
    });

    test('copyWith can clear brand logo without clearing document logo', () {
      final settings = CompanySettings.fromJson(_row({
        'logo_url': 'https://cdn.example.com/brand-dark.png',
        'document_logo_url': 'https://cdn.example.com/document-logo.png',
        'custom_branding_enabled': true,
      }));
      final updated = settings.copyWith(clearLogoUrl: true);
      expect(updated.logoUrl, isNull);
      expect(updated.documentLogoUrl, 'https://cdn.example.com/document-logo.png');
    });

    test('settings payload never sends document or brand logo columns', () {
      final settings = CompanySettings.fromJson(_row({
        'document_logo_url': 'https://cdn.example.com/document-logo.png',
        'logo_url': 'https://cdn.example.com/brand-dark.png',
      }));
      final payload = settings.toUpdatePayload(employeeId: 'emp-1');
      expect(payload.containsKey('document_logo_url'), isFalse);
      expect(payload.containsKey('logo_url'), isFalse);
      expect(payload.containsKey('logo_light_url'), isFalse);
    });
    test('CompanySettings stores document contact fields', () {
      final settings = CompanySettings.fromJson(_row({
        'document_address': '12 Flower Rd',
        'document_phone': '+94112345678',
        'document_email': 'hello@example.com',
        'document_terms': 'Thank you for your business.',
      }));
      expect(settings.documentAddress, '12 Flower Rd');
      expect(settings.documentPhone, '+94112345678');
      expect(settings.documentEmail, 'hello@example.com');
      expect(settings.documentTerms, 'Thank you for your business.');

      final cleared = settings.copyWith(clearDocumentTerms: true);
      expect(cleared.documentTerms, isNull);
      expect(cleared.documentAddress, '12 Flower Rd');
    });
  });

  group('OrderDocument.issuerIdentity', () {
    test('parses issuer contact and terms from public document payload', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-09-01T10:00:00Z',
        'total': 100,
        'currency': 'LKR',
        'company_name': 'Namson Lanka',
        'document_address': '12 Flower Rd, Colombo',
        'document_phone': '+94771234567',
        'document_email': 'hello@namson.lk',
        'document_terms': 'Payment due within 14 days.',
        'customer_name': 'Buyer',
        'lines': [],
      });

      expect(doc.documentAddress, '12 Flower Rd, Colombo');
      expect(doc.documentPhone, '+94771234567');
      expect(doc.documentEmail, 'hello@namson.lk');
      expect(doc.documentTerms, 'Payment due within 14 days.');
      expect(doc.issuerIdentity.hasContactBlock, isTrue);
      expect(doc.issuerIdentity.address, '12 Flower Rd, Colombo');
      expect(doc.issuerIdentity.phone, '+94771234567');
      expect(doc.issuerIdentity.email, 'hello@namson.lk');
      expect(doc.issuerIdentity.hasTerms, isTrue);
      expect(doc.issuerIdentity.terms, 'Payment due within 14 days.');
    });

    test('reads document_logo_url regardless of Custom Branding entitlement', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-09-01T10:00:00Z',
        'total': 100,
        'currency': 'LKR',
        'company_name': 'Namson Lanka',
        'document_logo_url': 'https://cdn.example.com/document-logo.png',
        'document_show_business_name_with_logo': true,
        'custom_branding_enabled': false,
        'logo_url': 'https://cdn.example.com/brand-should-not-be-issuer.png',
        'customer_name': 'Buyer',
        'lines': [],
      });

      expect(doc.documentLogoUrl, 'https://cdn.example.com/document-logo.png');
      expect(doc.showBusinessNameWithLogo, isTrue);
      expect(doc.issuerIdentity.showLogo, isTrue);
      expect(doc.issuerIdentity.showBusinessName, isTrue);
      expect(doc.issuerIdentity.logoUrl, 'https://cdn.example.com/document-logo.png');
      expect(doc.issuerIdentity.businessName, 'Namson Lanka');
      // Accent stays Sello when Custom Branding is off.
      expect(doc.branding.hasCustomLogo, isFalse);
    });

    test('brand asset logos alone do not become the document issuer', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-09-01T10:00:00Z',
        'total': 100,
        'currency': 'LKR',
        'company_name': 'Namson Lanka',
        'logo_url': 'https://cdn.example.com/brand-dark.png',
        'logo_light_url': 'https://cdn.example.com/brand-light.png',
        'custom_branding_enabled': true,
        'customer_name': 'Buyer',
        'lines': [],
      });

      expect(doc.issuerIdentity.showLogo, isFalse);
      expect(doc.issuerIdentity.showBusinessName, isTrue);
      expect(doc.branding.hasCustomLogo, isTrue);
    });

    test('missing company name does not default to Sello', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'receipt',
        'payment_number': 'PAY-1',
        'received_at': '2026-09-01T10:00:00Z',
        'amount': 50,
        'currency': 'LKR',
        'customer_name': 'Buyer',
        'lines': [],
      });
      expect(doc.companyName, 'Business');
    });
  });
}

Map<String, dynamic> _row([Map<String, dynamic> extras = const {}]) {
  return {
    'id': 'settings-1',
    'company_id': 'company-1',
    'currency': 'USD',
    ...extras,
  };
}
