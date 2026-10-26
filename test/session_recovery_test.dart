import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/auth/auth_service.dart';
import 'package:sello/services/session/session_profile_failure.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/session/session_service.dart';
import 'package:sello/services/session/session_snapshot_store.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/employment_status.dart';
import 'package:sello/shared/models/role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionProfileFailure', () {
    test('treats transport and timeouts as cacheable', () {
      expect(
        SessionProfileFailure.isTransport(
          TimeoutException('connection timed out'),
        ),
        isTrue,
      );
      expect(
        SessionProfileFailure.isTransport(AuthRetryableFetchException()),
        isTrue,
      );
      expect(
        SessionProfileFailure.isTransport(
          const PostgrestException(
            message: 'Failed host lookup: example.supabase.co',
          ),
        ),
        isTrue,
      );
      expect(
        SessionProfileFailure.isTransport(
          const NetworkFailure('Unable to reach Sello.'),
        ),
        isTrue,
      );
      expect(
        SessionProfileFailure.canUseCachedProfile(
          Exception('SocketException: Network is unreachable'),
        ),
        isTrue,
      );
    });

    test('treats an expired JWT as unconfirmed, not rejection', () {
      const error = PostgrestException(
        message: 'JWT expired',
        code: 'PGRST301',
      );
      expect(SessionProfileFailure.isTransport(error), isFalse);
      expect(SessionProfileFailure.isUnconfirmed(error), isTrue);
      expect(SessionProfileFailure.canUseCachedProfile(error), isTrue);
    });

    test('does not treat account rejection or query errors as transport', () {
      const inactive = AuthFailure('This account is inactive.');
      expect(SessionProfileFailure.isTransport(inactive), isFalse);
      expect(SessionProfileFailure.canUseCachedProfile(inactive), isFalse);

      const query = PostgrestException(
        message: 'column employees.missing does not exist',
        code: '42703',
      );
      expect(SessionProfileFailure.isTransport(query), isFalse);
      expect(SessionProfileFailure.isUnconfirmed(query), isFalse);
      expect(SessionProfileFailure.canUseCachedProfile(query), isFalse);
    });
  });

  group('SessionSnapshotStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trips one user and ignores another user', () async {
      final store = SessionSnapshotStore();
      final user = _user('user-1');
      await store.save(_appSession(user));

      final loaded = await store.loadFor(user);
      expect(loaded, isNotNull);
      expect(loaded!.userId, 'user-1');
      expect(loaded.employee.fullName, 'Sales Rep');
      expect(loaded.company.name, 'Unitech');

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SessionSnapshotStore.prefsKey)!;
      expect(raw.contains('access_token'), isFalse);
      expect(raw.contains('refresh_token'), isFalse);
      expect(raw.contains('password'), isFalse);

      expect(await store.loadFor(_user('user-2')), isNull);
    });

    test('drops a snapshot whose employee or company cannot sign in', () async {
      final store = SessionSnapshotStore();
      final user = _user('user-1');
      await store.save(
        _appSession(
          user,
          employee: const Employee(
            id: 'emp-1',
            companyId: 'co-1',
            roleId: 'role-1',
            email: 'rep@example.com',
            fullName: 'Sales Rep',
            employmentStatus: EmploymentStatus.suspended,
          ),
        ),
      );
      expect(await store.loadFor(user), isNull);

      await store.save(
        _appSession(
          user,
          company: const Company(
            id: 'co-1',
            name: 'Unitech',
            companyCode: 'UNI',
            slug: 'unitech',
            isActive: false,
          ),
        ),
      );
      expect(await store.loadFor(user), isNull);
    });

    test('clear removes the snapshot and corrupt json is ignored', () async {
      final store = SessionSnapshotStore();
      final user = _user('user-1');
      await store.save(_appSession(user));
      await store.clear();
      expect(await store.loadFor(user), isNull);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SessionSnapshotStore.prefsKey, '{not json');
      expect(await store.loadFor(user), isNull);

      await prefs.setString(
        SessionSnapshotStore.prefsKey,
        jsonEncode({'user_id': user.id}),
      );
      expect(await store.loadFor(user), isNull);
    });
  });

  group('AuthSessionNotifier recovery', () {
    late _FakeAuth auth;
    late _FakeSessions sessions;
    late _MemorySnapshotStore store;

    setUp(() {
      auth = _FakeAuth();
      sessions = _FakeSessions();
      store = _MemorySnapshotStore();
    });

    test(
      'opens a matching snapshot when the profile cannot be reached',
      () async {
        final user = _user('user-1');
        auth.current = user;
        sessions.error = const NetworkFailure('Unable to reach Sello.');
        store.remember(_appSession(user));

        final container = _container(auth, sessions, store);
        addTearDown(container.dispose);
        container.read(authSessionProvider);
        await _settle();

        final state = container.read(authSessionProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.usingCachedProfile, isTrue);
        expect(state.session?.userId, 'user-1');
        expect(state.infoMessage, AuthSessionNotifier.cachedProfileMessage);
        expect(auth.signOutCount, 0);
        expect(store.clearCount, 0);
      },
    );

    test(
      'stays signed out without a snapshot and does not revoke the session',
      () async {
        final user = _user('user-1');
        auth.current = user;
        sessions.error = const OfflineFailure();

        final container = _container(auth, sessions, store);
        addTearDown(container.dispose);
        container.read(authSessionProvider);
        await _settle();

        final state = container.read(authSessionProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.usingCachedProfile, isFalse);
        expect(state.errorMessage, isNotNull);
        expect(auth.signOutCount, 0);
      },
    );

    test('ignores a snapshot that belongs to another user', () async {
      final user = _user('user-1');
      auth.current = user;
      sessions.error = TimeoutException('timed out');
      store.remember(_appSession(_user('user-2')));

      final container = _container(auth, sessions, store);
      addTearDown(container.dispose);
      container.read(authSessionProvider);
      await _settle();

      final state = container.read(authSessionProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.session, isNull);
      expect(auth.signOutCount, 0);
      expect(store.loads, 1);
    });

    test('does not use the cache for an ambiguous server error', () async {
      final user = _user('user-1');
      auth.current = user;
      sessions.error = const PostgrestException(
        message: 'column employees.missing does not exist',
        code: '42703',
      );
      store.remember(_appSession(user));

      final container = _container(auth, sessions, store);
      addTearDown(container.dispose);
      container.read(authSessionProvider);
      await _settle();

      final state = container.read(authSessionProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.usingCachedProfile, isFalse);
      expect(auth.signOutCount, 0);
      expect(store.loads, 0);
    });

    test(
      'clears the snapshot and signs out when the account is rejected',
      () async {
        final user = _user('user-1');
        auth.current = user;
        sessions.error = const AuthFailure('This account is inactive.');
        store.remember(_appSession(user));

        final container = _container(auth, sessions, store);
        addTearDown(container.dispose);
        container.read(authSessionProvider);
        await _settle();

        final state = container.read(authSessionProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.usingCachedProfile, isFalse);
        expect(auth.signOutCount, 1);
        expect(store.clearCount, 1);
        expect(store.saved, isNull);
      },
    );

    test('saves the profile after a successful online hydrate', () async {
      final user = _user('user-1');
      auth.current = user;

      final container = _container(auth, sessions, store);
      addTearDown(container.dispose);
      container.read(authSessionProvider);
      await _settle();

      final state = container.read(authSessionProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.usingCachedProfile, isFalse);
      expect(store.saved?.userId, 'user-1');
      expect(auth.signOutCount, 0);
    });

    test(
      'sign-out clears the snapshot even when remote revoke throws',
      () async {
        final user = _user('user-1');
        auth.current = user;
        final container = _container(auth, sessions, store);
        addTearDown(container.dispose);
        container.read(authSessionProvider);
        await _settle();

        auth.signOutError = const UnexpectedFailure('revoke failed');
        await container.read(authSessionProvider.notifier).signOut();

        final state = container.read(authSessionProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.session, isNull);
        expect(state.usingCachedProfile, isFalse);
        expect(store.clearCount, 1);
        expect(store.saved, isNull);
      },
    );

    test(
      'a signed-out event clears the snapshot and does not restore it',
      () async {
        final user = _user('user-1');
        auth.current = user;
        sessions.gate = Completer<void>();
        store.remember(_appSession(user));

        final container = _container(auth, sessions, store);
        addTearDown(container.dispose);
        container.read(authSessionProvider);
        await _until(() => sessions.builds == 1);

        auth.publish(AuthState(AuthChangeEvent.signedOut, null));
        await _settle();

        expect(
          container.read(authSessionProvider).status,
          AuthStatus.unauthenticated,
        );
        expect(store.clearCount, greaterThanOrEqualTo(1));

        sessions.error = const NetworkFailure('Unable to reach Sello.');
        sessions.gate!.complete();
        await _settle();

        final state = container.read(authSessionProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.usingCachedProfile, isFalse);
        expect(state.session, isNull);
        expect(store.loads, 0);
      },
    );
  });
}

ProviderContainer _container(
  _FakeAuth auth,
  _FakeSessions sessions,
  _MemorySnapshotStore store,
) {
  return ProviderContainer(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      sessionServiceProvider.overrideWithValue(sessions),
      sessionSnapshotStoreProvider.overrideWithValue(store),
    ],
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 20; i++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition was not met');
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00.000Z',
  email: 'rep@example.com',
);

AppSession _appSession(User user, {Employee? employee, Company? company}) {
  return AppSession(
    authUser: user,
    employee:
        employee ??
        Employee(
          id: 'emp-1',
          companyId: 'co-1',
          roleId: 'role-1',
          email: 'rep@example.com',
          fullName: 'Sales Rep',
          userId: user.id,
        ),
    company:
        company ??
        const Company(
          id: 'co-1',
          name: 'Unitech',
          companyCode: 'UNI',
          slug: 'unitech',
        ),
    role: const Role(
      id: 'role-1',
      code: 'sales_representative',
      name: 'Sales Representative',
    ),
    ownerSetupCompleted: true,
  );
}

class _FakeAuth extends AuthService {
  _FakeAuth()
    : super(
        client: SupabaseClient(
          'https://example.supabase.co',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  User? current;
  int signOutCount = 0;
  Object? signOutError;
  final _controller = StreamController<AuthState>.broadcast(sync: true);

  void publish(AuthState state) => _controller.add(state);

  @override
  User? get currentUser => current;

  @override
  Stream<AuthState> get authStateChanges => _controller.stream;

  @override
  Future<void> signOut() async {
    signOutCount++;
    final error = signOutError;
    if (error != null) throw error;
  }
}

class _FakeSessions implements SessionService {
  Object? error;
  Completer<void>? gate;
  int builds = 0;

  @override
  Future<AppSession> buildSession(User user) async {
    builds++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final error = this.error;
    if (error != null) throw error;
    return _appSession(user);
  }
}

class _MemorySnapshotStore extends SessionSnapshotStore {
  AppSession? saved;
  String? savedUserId;
  int clearCount = 0;
  int loads = 0;

  void remember(AppSession session) {
    saved = session;
    savedUserId = session.userId;
  }

  @override
  Future<void> save(AppSession session) async {
    remember(session);
  }

  @override
  Future<AppSession?> loadFor(User user) async {
    loads++;
    final session = saved;
    if (session == null || savedUserId != user.id) return null;
    return session;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    saved = null;
    savedUserId = null;
  }
}
