import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('RouteGuards bootstrap / deep links', () {
    test('preserves Hub routes while session is bootstrapping', () {
      const auth = AuthSessionState(status: AuthStatus.unknown, isLoading: true);

      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubSettings),
        isNull,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubInventory),
        isNull,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubSchedule),
        isNull,
      );
    });

    test('preserves Sales routes while session is bootstrapping', () {
      const auth = AuthSessionState(status: AuthStatus.unknown, isLoading: true);

      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.selloOrders),
        isNull,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.selloCustomers),
        isNull,
      );
    });

    test('allows splash and login during bootstrap', () {
      const auth = AuthSessionState(status: AuthStatus.unknown, isLoading: true);

      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.splash),
        isNull,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.login),
        isNull,
      );
    });

    test('authenticated Hub deep link stays after bootstrap', () {
      final auth = _authenticated(role: 'owner', setupCompleted: true);

      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubSettings),
        isNull,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubCustomers),
        isNull,
      );
    });

    test('unauthenticated Hub deep link redirects to login', () {
      const auth = AuthSessionState(status: AuthStatus.unauthenticated);

      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubSettings),
        RoutePaths.login,
      );
    });

    test('authenticated cold start on splash still goes home', () {
      final auth = _authenticated(role: 'owner', setupCompleted: true);

      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.splash),
        RoutePaths.hubDashboard,
      );
    });
  });
}

AuthSessionState _authenticated({
  required String role,
  required bool setupCompleted,
}) {
  return AuthSessionState(
    status: AuthStatus.authenticated,
    session: AppSession(
      authUser: User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00.000Z',
      ),
      employee: Employee(
        id: 'emp-1',
        companyId: 'co-1',
        roleId: 'role-1',
        email: 'owner@example.com',
        fullName: 'Owner',
      ),
      company: const Company(
        id: 'co-1',
        name: 'Unitech',
        companyCode: 'UNI',
        slug: 'unitech',
      ),
      role: Role(id: 'role-1', code: role, name: role),
      ownerSetupCompleted: setupCompleted,
    ),
  );
}
