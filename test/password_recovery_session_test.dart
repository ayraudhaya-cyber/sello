import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/core/router/route_guards.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/auth/auth_email_personalization.dart';
import 'package:sello/services/auth/auth_service.dart';
import 'package:sello/services/auth/password_recovery_redirect.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/session/session_service.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('PasswordRecoveryRedirect', () {
    test('detects type=recovery in query and fragment', () {
      expect(
        PasswordRecoveryRedirect.isIndicatedBy(
          Uri.parse('https://sello.cashro.pro/login?type=recovery&code=abc'),
        ),
        isTrue,
      );
      expect(
        PasswordRecoveryRedirect.isIndicatedBy(
          Uri.parse(
            'https://sello.cashro.pro/login#access_token=x&type=recovery',
          ),
        ),
        isTrue,
      );
      expect(
        PasswordRecoveryRedirect.isIndicatedBy(
          Uri.parse('https://sello.cashro.pro/login?code=abc'),
        ),
        isFalse,
      );
    });
  });

  group('AuthSessionNotifier recovery handoff', () {
    late _ReplayAuthService auth;
    late _FakeSessionService sessions;

    setUp(() {
      auth = _ReplayAuthService();
      sessions = _FakeSessionService();
    });

    ProviderContainer createContainer() {
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          sessionServiceProvider.overrideWithValue(sessions),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test(
      'PASSWORD_RECOVERY before bootstrap keeps recovery and skips hydrate',
      () async {
        final user = _user();
        auth.current = user;
        auth.publish(
          AuthState(AuthChangeEvent.passwordRecovery, _session(user)),
        );

        final container = createContainer();
        container.read(authSessionProvider);
        await settle();

        final state = container.read(authSessionProvider);
        expect(state.isPasswordRecovery, isTrue);
        expect(state.isTeamInvitePasswordSetup, isFalse);
        expect(state.isAuthenticated, isFalse);
        expect(state.status, AuthStatus.unauthenticated);
        expect(sessions.buildCount, 0);
        expect(
          RouteGuards.resolve(auth: state, location: RoutePaths.login),
          isNull,
        );
        expect(
          RouteGuards.resolve(auth: state, location: RoutePaths.selloDashboard),
          RoutePaths.login,
        );
      },
    );

    test(
      'team invite metadata marks invite password-setup recovery',
      () async {
        final user = _user(
          metadata: const {
            AuthEmailPersonalization.teamInviteKey: true,
          },
        );
        auth.current = user;
        auth.publish(
          AuthState(AuthChangeEvent.passwordRecovery, _session(user)),
        );

        final container = createContainer();
        container.read(authSessionProvider);
        await settle();

        final state = container.read(authSessionProvider);
        expect(state.isPasswordRecovery, isTrue);
        expect(state.isTeamInvitePasswordSetup, isTrue);
        expect(state.isAuthenticated, isFalse);
        expect(sessions.buildCount, 0);
      },
    );

    test(
      'PASSWORD_RECOVERY during in-flight SIGNED_IN hydrate keeps set-password UI',
      () async {
        final user = _user();
        auth.current = user;
        // No team-invite metadata so SIGNED_IN is allowed to start hydrating.
        sessions.delay = const Duration(milliseconds: 40);
        auth.publish(AuthState(AuthChangeEvent.signedIn, _session(user)));

        final container = createContainer();
        container.read(authSessionProvider);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Simulate recovery arriving while employee context is still loading.
        auth.publish(
          AuthState(AuthChangeEvent.passwordRecovery, _session(user)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await settle();

        final state = container.read(authSessionProvider);
        expect(state.isPasswordRecovery, isTrue);
        expect(state.isAuthenticated, isFalse);
      },
    );

    test(
      'SIGNED_IN after recovery stays in password-setup mode',
      () async {
        final user = _user();
        auth.current = user;
        auth.publish(
          AuthState(AuthChangeEvent.passwordRecovery, _session(user)),
        );

        final container = createContainer();
        container.read(authSessionProvider);
        await settle();

        auth.publish(AuthState(AuthChangeEvent.signedIn, _session(user)));
        await settle();

        final state = container.read(authSessionProvider);
        expect(state.isPasswordRecovery, isTrue);
        expect(state.isAuthenticated, isFalse);
        expect(sessions.buildCount, 0);
      },
    );

    test(
      'team invite metadata alone blocks workspace hydrate on cold start',
      () async {
        final user = _user(
          metadata: const {
            AuthEmailPersonalization.teamInviteKey: true,
          },
        );
        auth.current = user;
        auth.publish(AuthState(AuthChangeEvent.signedIn, _session(user)));

        final container = createContainer();
        container.read(authSessionProvider);
        await settle();

        final state = container.read(authSessionProvider);
        expect(state.isPasswordRecovery, isTrue);
        expect(state.isTeamInvitePasswordSetup, isTrue);
        expect(state.isAuthenticated, isFalse);
        expect(sessions.buildCount, 0);
      },
    );

    test(
      'completePasswordRecovery clears recovery and hydrates employee',
      () async {
        final user = _user(
          metadata: const {
            AuthEmailPersonalization.teamInviteKey: true,
          },
        );
        auth.current = user;
        auth.publish(
          AuthState(AuthChangeEvent.passwordRecovery, _session(user)),
        );

        final container = createContainer();
        final notifier = container.read(authSessionProvider.notifier);
        await settle();

        expect(
          container.read(authSessionProvider).isTeamInvitePasswordSetup,
          isTrue,
        );

        await notifier.completePasswordRecovery(password: 'new-secret1');
        await settle();

        final state = container.read(authSessionProvider);
        expect(auth.updatedPasswords, ['new-secret1']);
        expect(auth.lastPasswordMetadata, {
          AuthEmailPersonalization.teamInviteKey: false,
        });
        expect(state.isPasswordRecovery, isFalse);
        expect(state.isTeamInvitePasswordSetup, isFalse);
        expect(state.isAuthenticated, isTrue);
        expect(state.session?.employee.id, 'emp-1');
        expect(sessions.buildCount, 1);
        expect(
          RouteGuards.resolve(auth: state, location: RoutePaths.login),
          RoutePaths.selloDashboard,
        );
      },
    );

    test('normal cold start with session hydrates Sign In workspace', () async {
      final user = _user();
      auth.current = user;
      auth.publish(AuthState(AuthChangeEvent.signedIn, _session(user)));

      final container = createContainer();
      container.read(authSessionProvider);
      await settle();

      final state = container.read(authSessionProvider);
      expect(state.isPasswordRecovery, isFalse);
      expect(state.isAuthenticated, isTrue);
      expect(sessions.buildCount, greaterThanOrEqualTo(1));
    });

    test('normal unauthenticated bootstrap is not recovery', () async {
      final container = createContainer();
      container.read(authSessionProvider);
      await settle();

      final state = container.read(authSessionProvider);
      expect(state.isPasswordRecovery, isFalse);
      expect(state.status, AuthStatus.unauthenticated);
      expect(sessions.buildCount, 0);
    });

    test(
      'subsequent signed-in launch after recovery latch clear is normal',
      () async {
        final user = _user();
        auth.current = user;
        auth.publish(
          AuthState(AuthChangeEvent.passwordRecovery, _session(user)),
        );

        final container = createContainer();
        final notifier = container.read(authSessionProvider.notifier);
        await settle();
        await notifier.completePasswordRecovery(password: 'new-secret1');
        await settle();

        expect(container.read(authSessionProvider).isPasswordRecovery, isFalse);

        // Simulate a later auth refresh — must not re-enter recovery.
        auth.publish(
          AuthState(AuthChangeEvent.tokenRefreshed, _session(user)),
        );
        await settle();

        final state = container.read(authSessionProvider);
        expect(state.isPasswordRecovery, isFalse);
        expect(state.isAuthenticated, isTrue);
      },
    );
  });
}

User _user({Map<String, dynamic>? metadata}) => User(
      id: 'user-1',
      appMetadata: const {},
      userMetadata: metadata ?? const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
      email: 'rep@example.com',
    );

Session _session(User user) => Session(
      accessToken: 'access',
      refreshToken: 'refresh',
      tokenType: 'bearer',
      user: user,
    );

AppSession _appSession(User user) => AppSession(
      authUser: user,
      employee: Employee(
        id: 'emp-1',
        companyId: 'co-1',
        roleId: 'role-1',
        email: 'rep@example.com',
        fullName: 'Sales Rep',
      ),
      company: const Company(
        id: 'co-1',
        name: 'Unitech',
        companyCode: 'UNI',
        slug: 'unitech',
      ),
      role: Role(
        id: 'role-1',
        code: 'sales_representative',
        name: 'Sales Representative',
      ),
      ownerSetupCompleted: true,
    );

/// Replays the latest auth event to new listeners (GoTrue BehaviorSubject).
class _ReplayAuthService extends AuthService {
  _ReplayAuthService()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  User? current;
  AuthState? _latest;
  final _controller = StreamController<AuthState>.broadcast(sync: true);
  final updatedPasswords = <String>[];
  Map<String, dynamic>? lastPasswordMetadata;

  void publish(AuthState state) {
    _latest = state;
    _controller.add(state);
  }

  @override
  User? get currentUser => current;

  @override
  Stream<AuthState> get authStateChanges {
    late final StreamController<AuthState> bridge;
    bridge = StreamController<AuthState>.broadcast(
      sync: true,
      onListen: () {
        final latest = _latest;
        if (latest != null) {
          bridge.add(latest);
        }
      },
    );
    final sub = _controller.stream.listen(bridge.add);
    bridge.onCancel = () async {
      await sub.cancel();
      await bridge.close();
    };
    return bridge.stream;
  }

  @override
  Future<UserResponse> updatePassword(
    String password, {
    Map<String, dynamic>? userMetadata,
  }) async {
    updatedPasswords.add(password);
    lastPasswordMetadata = userMetadata;
    final user = current!;
    return UserResponse.fromJson({
      'id': user.id,
      'aud': user.aud,
      'role': '',
      'email': user.email,
      'created_at': user.createdAt,
      'app_metadata': user.appMetadata,
      'user_metadata': {
        ...?user.userMetadata,
        ...?userMetadata,
      },
    });
  }
}

class _FakeSessionService implements SessionService {
  int buildCount = 0;
  Duration delay = Duration.zero;

  @override
  Future<AppSession> buildSession(User user) async {
    buildCount += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return _appSession(user);
  }
}
