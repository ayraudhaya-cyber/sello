import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/app.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/auth/auth_service.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Future<void> pumpLogin(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_UnauthenticatedSession.new),
          updateCheckControllerProvider.overrideWith(_IdleUpdateCheck.new),
          ...overrides,
        ],
        child: const SelloApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Login screen shows email and password only', (tester) async {
    await pumpLogin(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsWidgets);
    expect(find.text('Password'), findsWidgets);
    expect(find.text("Don't have an account? Create account"), findsOneWidget);
    expect(find.text('Foundation preview role'), findsNothing);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('Sales Representative'), findsNothing);
  });

  testWidgets(
    'Forgot password from empty login opens recovery without password errors',
    (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset your password'), findsOneWidget);
      expect(
        find.text(
          "Enter your email address and we'll send you a link to reset your password.",
        ),
        findsOneWidget,
      );
      expect(find.text('Send reset link'), findsOneWidget);
      expect(find.text('Back to sign in'), findsOneWidget);
      expect(find.text('Password'), findsNothing);
      expect(find.text('Email is required'), findsNothing);
      expect(find.text('Password is required'), findsNothing);
      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
    },
  );

  testWidgets(
    'Password recovery request validates email only then shows success',
    (tester) async {
      final auth = _FakeAuthService();
      await pumpLogin(
        tester,
        overrides: [authServiceProvider.overrideWithValue(auth)],
      );

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(find.text('Email is required'), findsOneWidget);
      expect(auth.recoveryEmails, isEmpty);

      await tester.enterText(
        find.byType(TextField).first,
        'owner@example.com',
      );
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(auth.recoveryEmails, ['owner@example.com']);
      expect(find.text('Check your email'), findsOneWidget);
      expect(
        find.text("We've sent a password reset link to your email."),
        findsOneWidget,
      );
      expect(find.text('Back to sign in'), findsOneWidget);

      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Email is required'), findsNothing);
      expect(find.text('Password is required'), findsNothing);
    },
  );

  testWidgets('Password recovery mode shows reset form', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_PasswordRecoverySession.new),
          updateCheckControllerProvider.overrideWith(_IdleUpdateCheck.new),
        ],
        child: const SelloApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Update password'), findsOneWidget);
    expect(find.text('Set your password'), findsNothing);
    expect(find.text('Set password'), findsNothing);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('Team invite recovery mode shows set-password form', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_TeamInviteRecoverySession.new),
          updateCheckControllerProvider.overrideWith(_IdleUpdateCheck.new),
        ],
        child: const SelloApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set your password'), findsOneWidget);
    expect(find.text('Set password'), findsOneWidget);
    expect(find.text('Reset your password'), findsNothing);
    expect(find.text('Update password'), findsNothing);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });
}

class _IdleUpdateCheck extends UpdateCheckController {
  @override
  Future<UpdateCheckSnapshot> build() async {
    const installed = AppVersion(major: 1, minor: 0, patch: 0, build: 1);
    return const UpdateCheckSnapshot(
      status: UpdateCheckStatus.upToDate,
      installed: installed,
      latest: installed,
    );
  }
}

class _UnauthenticatedSession extends AuthSessionNotifier {
  @override
  AuthSessionState build() {
    return const AuthSessionState(status: AuthStatus.unauthenticated);
  }
}

class _PasswordRecoverySession extends AuthSessionNotifier {
  @override
  AuthSessionState build() {
    return const AuthSessionState(
      status: AuthStatus.unauthenticated,
      isPasswordRecovery: true,
      infoMessage: 'Choose a new password to finish account recovery.',
    );
  }
}

class _TeamInviteRecoverySession extends AuthSessionNotifier {
  @override
  AuthSessionState build() {
    return const AuthSessionState(
      status: AuthStatus.unauthenticated,
      isPasswordRecovery: true,
      isTeamInvitePasswordSetup: true,
      infoMessage: 'Choose a password to finish joining your team.',
    );
  }
}

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final recoveryEmails = <String>[];

  @override
  Future<void> sendPasswordRecovery({
    required String email,
    String redirectPath = RoutePaths.login,
  }) async {
    recoveryEmails.add(email.trim().toLowerCase());
  }
}
