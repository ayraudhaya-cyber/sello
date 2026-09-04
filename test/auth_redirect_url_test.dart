import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/auth/auth_redirect_url.dart';

void main() {
  group('AuthRedirectUrl', () {
    test('returns null on non-web platforms', () {
      expect(
        AuthRedirectUrl.forPath(
          RoutePaths.login,
          isWeb: false,
          isRelease: true,
          baseUri: Uri.parse('http://localhost:3000/onboarding'),
        ),
        isNull,
      );
    });

    test('debug/profile web uses the current page origin', () {
      expect(
        AuthRedirectUrl.forPath(
          RoutePaths.login,
          isWeb: true,
          isRelease: false,
          baseUri: Uri.parse('http://localhost:3000/onboarding?step=1'),
          envOrigin: 'https://sello.cashro.pro',
        ),
        'http://localhost:3000/login',
      );
    });

    test('release web uses production origin when SELLO_PUBLIC_URL is unset', () {
      expect(
        AuthRedirectUrl.forPath(
          RoutePaths.login,
          isWeb: true,
          isRelease: true,
          baseUri: Uri.parse('http://localhost:3000/onboarding'),
          envOrigin: '',
        ),
        '${AuthRedirectUrl.productionWebOrigin}/login',
      );
    });

    test('release web prefers SELLO_PUBLIC_URL over Uri.base', () {
      expect(
        AuthRedirectUrl.forPath(
          RoutePaths.login,
          isWeb: true,
          isRelease: true,
          baseUri: Uri.parse('http://localhost:3000/onboarding'),
          envOrigin: 'https://sello.cashro.pro/',
        ),
        'https://sello.cashro.pro/login',
      );
    });

    test('release never keeps localhost when env is empty', () {
      final redirect = AuthRedirectUrl.forPath(
        RoutePaths.login,
        isWeb: true,
        isRelease: true,
        baseUri: Uri.parse('http://127.0.0.1:3000/'),
        envOrigin: '   ',
      );
      expect(redirect, isNot(contains('localhost')));
      expect(redirect, isNot(contains('127.0.0.1')));
      expect(redirect, 'https://sello.cashro.pro/login');
    });
  });
}
