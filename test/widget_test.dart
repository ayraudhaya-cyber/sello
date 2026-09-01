import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/app.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

void main() {
  testWidgets('Login screen shows email and password only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_UnauthenticatedSession.new),
          updateCheckControllerProvider.overrideWith(_IdleUpdateCheck.new),
        ],
        child: const SelloApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsWidgets);
    expect(find.text('Password'), findsWidgets);
    expect(find.text("Don't have an account? Create account"), findsOneWidget);
    expect(find.text('Foundation preview role'), findsNothing);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('Sales Representative'), findsNothing);
  });

  testWidgets('Password recovery mode shows reset form', (tester) async {
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

    expect(find.text('Reset password'), findsOneWidget);
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
