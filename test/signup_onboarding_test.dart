import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/data/repositories/provisioning_repository.dart';
import 'package:sello/features/onboarding/application/onboarding_provider.dart';
import 'package:sello/features/onboarding/presentation/business_onboarding_page.dart';
import 'package:sello/services/onboarding/onboarding_service.dart';
import 'package:sello/services/onboarding/onboarding_validation.dart';
import 'package:sello/services/onboarding/signup_invite_policy.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/provision_business_request.dart';
import 'package:sello/shared/models/role.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Signup validation', () {
    test('rejects weak password, mismatch, and invalid email', () {
      expect(OnboardingValidation.password('short'), isNotNull);
      expect(
        OnboardingValidation.confirmPassword('secret12', 'secret13'),
        'Passwords do not match.',
      );
      expect(OnboardingValidation.ownerEmail('not-an-email'), isNotNull);
      expect(OnboardingValidation.ownerEmail('owner@acme.com'), isNull);
      expect(OnboardingValidation.businessName('A'), isNotNull);
      expect(OnboardingValidation.ownerFullName(''), isNotNull);
    });

    test('SignupNotifier.validate surfaces the first field error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(onboardingProvider.notifier);

      expect(notifier.validate(), 'Full name is required.');
      notifier.updateFullName('Raees');
      expect(notifier.validate(), 'Email is required.');
      notifier.updateEmail('bad');
      expect(notifier.validate(), 'Enter a valid email address.');
      notifier.updateEmail('raees@acme.com');
      notifier.updatePassword('secret12');
      notifier.updateConfirmPassword('other12x');
      expect(notifier.validate(), 'Passwords do not match.');
      notifier.updateConfirmPassword('secret12');
      expect(notifier.validate(), 'Business name is required.');
      notifier.updateBusinessName('Acme Distributors');
      expect(notifier.validate(), isNull);
    });
  });

  group('Company code allocation', () {
    test('derives a stable code from the business name', () {
      expect(OnboardingService.generateCompanyCode('Acme Corp'), 'ACMECORP');
      expect(OnboardingService.generateCompanyCode('***'), 'BIZ');
    });

    test('later attempts append a suffix instead of colliding', () {
      expect(
        OnboardingService.companyCodeCandidate('Acme', 0),
        'ACME',
      );
      expect(
        OnboardingService.companyCodeCandidate('Acme', 1),
        'ACME2',
      );
    });
  });

  group('Signup request', () {
    test('always provisions Head Office and never carries a company id', () {
      final request = ProvisionBusinessRequest.signup(
        businessName: 'Unitech',
        ownerFullName: 'Raees',
        ownerEmail: 'raees@unitech.com',
        password: 'secret12',
      );

      expect(request.businessName, 'Unitech');
      expect(request.ownerFullName, 'Raees');
      expect(request.companyCode, 'UNITECH');
      expect(request.branchName, 'Head Office');
      expect(request.branchCode, 'HO');
      expect(request.ownerPhone, isNull);
    });

    test('pending metadata never includes the password', () {
      final request = ProvisionBusinessRequest.signup(
        businessName: 'Unitech',
        ownerFullName: 'Raees',
        ownerEmail: 'raees@unitech.com',
        password: 'secret12',
      );
      final json = PendingBusinessMetadata.fromRequest(request).toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json['business_name'], 'Unitech');
    });

    test('complete RPC retry is marked already provisioned', () {
      final result = ProvisionBusinessResult.fromJson({
        'company_id': 'co-1',
        'branch_id': 'br-1',
        'employee_id': 'emp-1',
        'role_id': 'role-owner',
        'company_code': 'UNITECH',
        'slug': 'unitech',
        'already_provisioned': true,
      });
      expect(result.alreadyProvisioned, isTrue);
      expect(result.companyId, 'co-1');
    });
  });

  group('Owner assignment and settings defaults', () {
    test('signup user is modeled as Owner, never Manager or Sales Rep', () {
      expect(UserRole.fromCode('owner'), UserRole.owner);
      expect(UserRole.fromCode('owner').usesHub, isTrue);
      expect(UserRole.fromCode('manager'), isNot(UserRole.owner));
      expect(UserRole.fromCode('sales_representative'), isNot(UserRole.owner));
    });

    test('new company_settings rows are incomplete until Owner Setup', () {
      final created = CompanySettings.fromJson({
        'id': 's1',
        'company_id': 'c1',
        'currency': 'USD',
        'owner_setup_completed': false,
      });
      expect(created.ownerSetupCompleted, isFalse);

      final existing = CompanySettings.fromJson({
        'id': 's1',
        'company_id': 'c1',
        'currency': 'USD',
      });
      expect(existing.ownerSetupCompleted, isTrue);
    });
  });

  group('Routing', () {
    test('unverified signup stays on the confirmation screen', () {
      const auth = AuthSessionState(
        status: AuthStatus.unauthenticated,
        awaitingEmailConfirmation: true,
        pendingEmail: 'new@acme.com',
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.onboarding),
        isNull,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubDashboard),
        RoutePaths.onboarding,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.login),
        isNull,
      );
    });

    test('new Owner is sent to Owner Setup, not a second signup wizard', () {
      final auth = _authenticated(role: 'owner', setupCompleted: false);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.onboarding),
        RoutePaths.ownerSetup,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubDashboard),
        RoutePaths.ownerSetup,
      );
    });

    test('closing the browser mid-setup returns the Owner to /setup', () {
      final auth = _authenticated(role: 'owner', setupCompleted: false);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.login),
        RoutePaths.ownerSetup,
      );
    });

    test('existing Owner, Manager, and Sales Rep still reach their homes', () {
      expect(
        RouteGuards.resolve(
          auth: _authenticated(role: 'owner', setupCompleted: true),
          location: RoutePaths.login,
        ),
        RoutePaths.hubDashboard,
      );
      expect(
        RouteGuards.resolve(
          auth: _authenticated(role: 'owner', setupCompleted: true),
          location: RoutePaths.onboarding,
        ),
        RoutePaths.hubDashboard,
      );
      expect(
        RouteGuards.resolve(
          auth: _authenticated(role: 'manager', setupCompleted: false),
          location: RoutePaths.onboarding,
        ),
        RoutePaths.hubDashboard,
      );
      expect(
        RouteGuards.resolve(
          auth: _authenticated(
            role: 'sales_representative',
            setupCompleted: false,
          ),
          location: RoutePaths.onboarding,
        ),
        RoutePaths.selloDashboard,
      );
    });

    test('signed-in users cannot open signup to join another company', () {
      final auth = _authenticated(role: 'owner', setupCompleted: true);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.onboarding),
        RoutePaths.hubDashboard,
      );
    });
  });

  group('Invite-only signup gate', () {
    test('normalizes emails so mixed case is the same identity', () {
      expect(
        SignupInvitePolicy.normalizeEmail('  Test@Example.com '),
        'test@example.com',
      );
      expect(
        SignupInvitePolicy.normalizeEmail('TEST@EXAMPLE.COM'),
        SignupInvitePolicy.normalizeEmail('test@example.com'),
      );
    });

    test('approved and unexpired emails can create a tenant', () {
      expect(
        SignupInvitePolicy.canCreateTenant(status: 'approved'),
        isTrue,
      );
      expect(
        SignupInvitePolicy.canCreateTenant(
          status: 'approved',
          expiresAt: DateTime.utc(2099, 1, 1),
          now: DateTime.utc(2026, 8, 18),
        ),
        isTrue,
      );
    });

    test('unapproved, used, revoked, and expired emails cannot create a tenant', () {
      expect(
        SignupInvitePolicy.canCreateTenant(status: 'pending'),
        isFalse,
      );
      expect(
        SignupInvitePolicy.canCreateTenant(status: 'used'),
        isFalse,
      );
      expect(
        SignupInvitePolicy.canCreateTenant(status: 'revoked'),
        isFalse,
      );
      expect(
        SignupInvitePolicy.canCreateTenant(
          status: 'approved',
          expiresAt: DateTime.utc(2026, 1, 1),
          now: DateTime.utc(2026, 8, 18),
        ),
        isFalse,
      );
    });

    test('maps the server rejection without leaking invite-row details', () {
      expect(
        SignupInvitePolicy.isInviteGateError('SIGNUP_NOT_INVITED'),
        isTrue,
      );
      expect(
        SignupInvitePolicy.isInviteGateError(SignupInvitePolicy.title),
        isTrue,
      );
      expect(SignupInvitePolicy.title, contains('invitation'));
      expect(SignupInvitePolicy.support.toLowerCase(), isNot(contains('tenant')));
      expect(SignupInvitePolicy.support.toLowerCase(), isNot(contains('rls')));
    });

    test('unapproved signup stops before company or Owner provisioning', () async {
      final repo = _InviteGateRepo(allowed: false);
      final session = _RecordingAuthSession();
      final container = ProviderContainer(
        overrides: [
          provisioningRepositoryProvider.overrideWithValue(repo),
          authSessionProvider.overrideWith(() => session),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      notifier.updateFullName('Raees');
      notifier.updateEmail('Nobody@Example.com');
      notifier.updatePassword('secret12');
      notifier.updateConfirmPassword('secret12');
      notifier.updateBusinessName('Acme');

      await notifier.submit();

      final draft = container.read(onboardingProvider);
      expect(draft.inviteRequired, isTrue);
      expect(draft.errorMessage, SignupInvitePolicy.title);
      expect(repo.availabilityChecked, isFalse);
      expect(repo.completeCalled, isFalse);
      expect(repo.upsertCalled, isFalse);
      expect(session.provisioned, isFalse);
    });

    test('approved email continues into the existing provision path', () async {
      final repo = _InviteGateRepo(allowed: true);
      final session = _RecordingAuthSession();
      final container = ProviderContainer(
        overrides: [
          provisioningRepositoryProvider.overrideWithValue(repo),
          authSessionProvider.overrideWith(() => session),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(onboardingProvider.notifier);
      notifier.updateFullName('Raees');
      notifier.updateEmail('Owner@Acme.com');
      notifier.updatePassword('secret12');
      notifier.updateConfirmPassword('secret12');
      notifier.updateBusinessName('Acme');

      await notifier.submit();

      expect(repo.availabilityChecked, isTrue);
      expect(session.provisioned, isTrue);
      expect(session.request?.ownerEmail, 'owner@acme.com');
      expect(container.read(onboardingProvider).inviteRequired, isFalse);
    });

    test('existing employees reach home without an invitation record', () {
      expect(
        RouteGuards.resolve(
          auth: _authenticated(role: 'owner', setupCompleted: true),
          location: RoutePaths.login,
        ),
        RoutePaths.hubDashboard,
      );
      expect(
        RouteGuards.resolve(
          auth: _authenticated(role: 'manager', setupCompleted: false),
          location: RoutePaths.login,
        ),
        RoutePaths.hubDashboard,
      );
      expect(
        RouteGuards.resolve(
          auth: _authenticated(
            role: 'sales_representative',
            setupCompleted: false,
          ),
          location: RoutePaths.login,
        ),
        RoutePaths.selloDashboard,
      );
    });

    test('approved Owner still continues through Owner Setup after provision', () {
      final auth = _authenticated(role: 'owner', setupCompleted: false);
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.onboarding),
        RoutePaths.ownerSetup,
      );
      expect(
        RouteGuards.resolve(auth: auth, location: RoutePaths.hubDashboard),
        RoutePaths.ownerSetup,
      );
    });

    test('Flutter has no client API to approve or insert invitations', () {
      final repo = File(
        'lib/data/repositories/provisioning_repository.dart',
      ).readAsStringSync();
      expect(repo, contains("'sello_signup_is_allowed'"));
      expect(repo, isNot(contains('sello_tenant_invites')));
      expect(repo.toLowerCase(), isNot(contains('approve_invite')));
      expect(repo.toLowerCase(), isNot(contains('insert_invite')));
    });
  });

  group('Signup UI', () {
    testWidgets('shows a short account form, not the old wizard', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_UnauthenticatedSession.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BusinessOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Business name'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Company code'), findsNothing);
      expect(find.text('Head office'), findsNothing);
      expect(find.textContaining('Step '), findsNothing);
    });

    testWidgets('password mismatch is shown on the form', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_UnauthenticatedSession.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BusinessOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Raees');
      await tester.enterText(find.byType(TextFormField).at(1), 'raees@acme.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret12');
      await tester.enterText(find.byType(TextFormField).at(3), 'different');
      await tester.enterText(find.byType(TextFormField).at(4), 'Acme');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });

    testWidgets('verification state explains the email and allows resend', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_AwaitingEmailSession.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BusinessOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text('new@acme.com'), findsOneWidget);
      expect(find.text('Resend email'), findsOneWidget);
      expect(find.text('Back to sign in'), findsOneWidget);
      expect(find.text('Create account'), findsNothing);
    });

    testWidgets('unapproved signup shows a calm invitation note', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_UnauthenticatedSession.new),
            onboardingProvider.overrideWith(_InviteBlockedSignup.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BusinessOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(SignupInvitePolicy.title), findsOneWidget);
      expect(find.text(SignupInvitePolicy.support), findsOneWidget);
      expect(find.textContaining('tenant'), findsNothing);
      expect(find.textContaining('RLS'), findsNothing);
      expect(find.text('Create account'), findsOneWidget);
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

class _UnauthenticatedSession extends AuthSessionNotifier {
  @override
  AuthSessionState build() {
    return const AuthSessionState(status: AuthStatus.unauthenticated);
  }
}

class _AwaitingEmailSession extends AuthSessionNotifier {
  @override
  AuthSessionState build() {
    return const AuthSessionState(
      status: AuthStatus.unauthenticated,
      awaitingEmailConfirmation: true,
      pendingEmail: 'new@acme.com',
    );
  }
}

class _InviteBlockedSignup extends SignupNotifier {
  @override
  SignupDraft build() => const SignupDraft(inviteRequired: true);
}

class _RecordingAuthSession extends AuthSessionNotifier {
  var provisioned = false;
  ProvisionBusinessRequest? request;

  @override
  AuthSessionState build() {
    return const AuthSessionState(status: AuthStatus.unauthenticated);
  }

  @override
  Future<void> provisionBusiness(ProvisionBusinessRequest request) async {
    provisioned = true;
    this.request = request;
  }
}

class _InviteGateRepo extends ProvisioningRepository {
  _InviteGateRepo({required this.allowed})
      : super(client: SupabaseClient('https://example.supabase.co', 'anon'));

  final bool allowed;
  var availabilityChecked = false;
  var completeCalled = false;
  var upsertCalled = false;

  @override
  Future<bool> isSignupAllowed(String email) async => allowed;

  @override
  Future<bool> isOwnerEmailAvailable(String email) async {
    availabilityChecked = true;
    return true;
  }

  @override
  Future<void> upsertPendingBusinessProvision({
    required String businessName,
    required String companyCode,
    required String ownerFullName,
    String? ownerPhone,
    required String branchName,
    required String branchCode,
  }) async {
    upsertCalled = true;
  }

  @override
  Future<ProvisionBusinessResult> completeBusinessOnboarding() async {
    completeCalled = true;
    throw StateError('complete should not run in this unit test');
  }
}
