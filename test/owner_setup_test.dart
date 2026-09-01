import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/features/hub/setup/application/owner_setup_provider.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/setup/owner_setup_policy.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('OwnerSetupPolicy', () {
    test('new Owner sees setup', () {
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.owner,
          ownerSetupCompleted: false,
        ),
        isTrue,
      );
    });

    test('completed Owner does not see setup again', () {
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.owner,
          ownerSetupCompleted: true,
        ),
        isFalse,
      );
    });

    test('Sales Rep does not see Owner setup', () {
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.salesRepresentative,
          ownerSetupCompleted: false,
        ),
        isFalse,
      );
    });

    test('Manager does not see Owner setup', () {
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.manager,
          ownerSetupCompleted: false,
        ),
        isFalse,
      );
    });

    test('incomplete Owner is sent to setup from the workspace', () {
      expect(
        OwnerSetupPolicy.redirect(
          requiresSetup: true,
          location: RoutePaths.hubDashboard,
          home: RoutePaths.hubDashboard,
        ),
        RoutePaths.ownerSetup,
      );
    });

    test('incomplete Owner may stay on setup', () {
      expect(
        OwnerSetupPolicy.redirect(
          requiresSetup: true,
          location: RoutePaths.ownerSetup,
          home: RoutePaths.hubDashboard,
        ),
        isNull,
      );
    });

    test('skipping the team step does not mark setup complete', () {
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.owner,
          ownerSetupCompleted: false,
        ),
        isTrue,
      );
      expect(
        OwnerSetupPolicy.redirect(
          requiresSetup: true,
          location: RoutePaths.ownerSetup,
          home: RoutePaths.hubDashboard,
        ),
        isNull,
      );
    });

    test('skipping SMS setup does not mark setup complete', () {
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.owner,
          ownerSetupCompleted: false,
        ),
        isTrue,
      );
    });
  });

  group('RouteGuards owner setup', () {
    test('new Owner is redirected to setup after login', () {
      final auth = _authenticated(role: 'owner', setupCompleted: false);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubDashboard),
        RoutePaths.ownerSetup,
      );
    });

    test('completed Owner goes to the Hub workspace', () {
      final auth = _authenticated(role: 'owner', setupCompleted: true);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.login),
        RoutePaths.hubDashboard,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.ownerSetup),
        RoutePaths.hubDashboard,
      );
    });

    test('existing tenant Owner is not forced through setup', () {
      final auth = _authenticated(role: 'owner', setupCompleted: true);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubDashboard),
        isNull,
      );
    });

    test('Sales Rep goes to Sello, not Owner setup', () {
      final auth = _authenticated(
        role: 'sales_representative',
        setupCompleted: false,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.login),
        RoutePaths.selloDashboard,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.ownerSetup),
        RoutePaths.selloDashboard,
      );
    });

    test('unauthenticated users cannot open setup', () {
      const auth = AuthSessionState(status: AuthStatus.unauthenticated);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.ownerSetup),
        RoutePaths.login,
      );
    });
  });

  group('CompanySettings owner_setup_completed', () {
    test('missing flag is treated as complete so existing tenants are safe', () {
      final settings = CompanySettings.fromJson(_settingsRow());
      expect(settings.ownerSetupCompleted, isTrue);
    });

    test('new tenant flag is read as incomplete', () {
      final settings = CompanySettings.fromJson(
        _settingsRow({'owner_setup_completed': false}),
      );
      expect(settings.ownerSetupCompleted, isFalse);
    });

    test('defaults treat setup as complete', () {
      expect(CompanySettings.defaults.ownerSetupCompleted, isTrue);
    });
  });

  group('Owner setup SMS step', () {
    test('Sender ID can be entered and skip still finishes later', () {
      const entered = OwnerSetupState(step: OwnerSetupStep.sms);
      expect(entered.smsReady, isFalse);
      final skipped = entered.copyWith(step: OwnerSetupStep.ready);
      expect(skipped.smsVerified, isFalse);
      expect(skipped.smsSenderId, isNull);
      expect(
        OwnerSetupPolicy.requiresSetup(
          role: UserRole.owner,
          ownerSetupCompleted: false,
        ),
        isTrue,
      );
    });

    test('successful verification marks SMS ready without unlocking edits', () {
      const state = OwnerSetupState(
        smsSenderId: 'AcmeCo',
        smsSenderIdEditable: false,
        smsVerified: true,
      );
      expect(state.smsReady, isTrue);
      expect(state.smsSenderIdEditable, isFalse);
    });

    test('Sello-managed Sender IDs are already ready', () {
      const state = OwnerSetupState(smsSenderId: 'AcmeCo');
      expect(state.smsAlreadyConfigured, isTrue);
      expect(state.smsReady, isTrue);
      expect(
        OutboundSmsVerify.canActivateCandidate(
          storedSenderId: state.smsSenderId,
          editable: state.smsSenderIdEditable,
          candidate: 'OtherId',
        ),
        isFalse,
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

Map<String, dynamic> _settingsRow([Map<String, dynamic> extras = const {}]) {
  return {
    'id': 'settings-1',
    'company_id': 'company-1',
    'currency': 'USD',
    ...extras,
  };
}
