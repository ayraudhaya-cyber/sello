import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/user_role.dart';

/// Auth + session state for route guards and chrome.
class AuthSessionState {
  const AuthSessionState({
    this.status = AuthStatus.unknown,
    this.session,
    this.isLoading = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final AppSession? session;
  final bool isLoading;
  final String? errorMessage;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && session != null;

  bool get isBootstrapping => status == AuthStatus.unknown;

  AuthSessionState copyWith({
    AuthStatus? status,
    AppSession? session,
    bool? isLoading,
    String? errorMessage,
    bool clearSession = false,
    bool clearError = false,
  }) {
    return AuthSessionState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Session orchestration. Phase 2 will restore from Supabase; foundation stubs.
class AuthSessionNotifier extends Notifier<AuthSessionState> {
  @override
  AuthSessionState build() {
    // Kick off cold-start restore asynchronously.
    Future.microtask(bootstrap);
    return const AuthSessionState(status: AuthStatus.unknown);
  }

  /// Cold start — restore session (stub: no persisted session yet).
  Future<void> bootstrap() async {
    state = state.copyWith(status: AuthStatus.unknown, isLoading: true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // No persisted session in foundation stub.
    state = const AuthSessionState(status: AuthStatus.unauthenticated);
  }

  /// Foundation stub sign-in. Replace with Supabase Auth in Phase 2.
  Future<void> signInStub({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));

    if (email.trim().isEmpty || password.isEmpty) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        errorMessage: 'Enter email and password to continue.',
      );
      return;
    }

    final name = email.contains('@') ? email.split('@').first : 'User';
    final display =
        name.isEmpty ? 'User' : '${name[0].toUpperCase()}${name.substring(1)}';

    state = AuthSessionState(
      status: AuthStatus.authenticated,
      session: AppSession(
        userId: 'stub-${role.name}',
        email: email.trim(),
        displayName: display,
        role: role,
        companyName: 'Demo Distributors',
      ),
    );
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    state = const AuthSessionState(status: AuthStatus.unauthenticated);
  }
}

final authSessionProvider =
    NotifierProvider<AuthSessionNotifier, AuthSessionState>(
  AuthSessionNotifier.new,
);

final currentSessionProvider = Provider<AppSession?>((ref) {
  return ref.watch(authSessionProvider).session;
});

final currentRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(currentSessionProvider)?.role;
});

final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authSessionProvider).status;
});
