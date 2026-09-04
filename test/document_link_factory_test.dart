import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/auth/auth_redirect_url.dart';
import 'package:sello/services/notifications/outbound/document_link_factory.dart';

void main() {
  group('DocumentLinkFactory', () {
    test('uses explicit override origin', () {
      const links = DocumentLinkFactory(
        overrideOrigin: 'https://app.sello.test/',
      );
      expect(
        links.orderDocument('abc123token'),
        'https://app.sello.test/d/abc123token',
      );
    });

    test('defaults to production web origin (never empty path-only in app use)', () {
      const links = DocumentLinkFactory();
      // Without SELLO_PUBLIC_URL dart-define, factory still avoids localhost by
      // falling back to the production Hub origin.
      expect(
        links.origin,
        anyOf(
          AuthRedirectUrl.productionWebOrigin,
          startsWith('http'),
        ),
      );
      expect(links.orderDocument('tok'), contains('/d/tok'));
      expect(links.orderDocument('tok'), isNot(contains('localhost')));
    });

    test('override wins over production default', () {
      const links = DocumentLinkFactory(
        overrideOrigin: 'https://staging.example.com',
      );
      expect(links.origin, 'https://staging.example.com');
    });
  });
}
