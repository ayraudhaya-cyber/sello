import 'package:flutter_test/flutter_test.dart';
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

    test('logo only when logo exists and toggle is off', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        logoLightUrl: 'https://cdn.example.com/logo-light.png',
        showBusinessNameWithLogo: false,
      );
      expect(identity.showLogo, isTrue);
      expect(identity.showBusinessName, isFalse);
      expect(identity.logoUrl, 'https://cdn.example.com/logo-light.png');
    });

    test('logo + business name when toggle is on', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        logoUrl: 'https://cdn.example.com/logo.png',
        showBusinessNameWithLogo: true,
      );
      expect(identity.showLogo, isTrue);
      expect(identity.showBusinessName, isTrue);
      expect(identity.logoUrl, 'https://cdn.example.com/logo.png');
    });

    test('prefers light logo over dark logo', () {
      final identity = DocumentIssuerIdentity.resolve(
        companyName: 'Namson Lanka',
        logoUrl: 'https://cdn.example.com/dark.png',
        logoLightUrl: 'https://cdn.example.com/light.png',
      );
      expect(identity.logoUrl, 'https://cdn.example.com/light.png');
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

  group('OrderDocument.issuerIdentity', () {
    test('reads document_show_business_name_with_logo from payload', () {
      final doc = OrderDocument.fromJson({
        'purpose': 'invoice',
        'order_number': 'SO-1',
        'ordered_at': '2026-09-01T10:00:00Z',
        'total': 100,
        'currency': 'LKR',
        'company_name': 'Namson Lanka',
        'logo_light_url': 'https://cdn.example.com/logo.png',
        'document_show_business_name_with_logo': true,
        'custom_branding_enabled': false,
        'customer_name': 'Buyer',
        'lines': [],
      });

      expect(doc.showBusinessNameWithLogo, isTrue);
      expect(doc.issuerIdentity.showLogo, isTrue);
      expect(doc.issuerIdentity.showBusinessName, isTrue);
      expect(doc.issuerIdentity.businessName, 'Namson Lanka');
      // Accent stays Sello when Custom Branding is off; logo still resolves.
      expect(doc.branding.hasCustomLogo, isFalse);
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
