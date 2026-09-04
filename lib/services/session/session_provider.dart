import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/branch_repository.dart';
import 'package:sello/data/repositories/company_repository.dart';
import 'package:sello/data/repositories/provisioning_repository.dart';
import 'package:sello/services/auth/auth_email_personalization.dart';
import 'package:sello/services/auth/auth_service.dart';
import 'package:sello/services/auth/password_recovery_redirect.dart';
import 'package:sello/services/provisioning/provisioning_coordinator.dart';
import 'package:sello/services/session/session_service.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/provision_business_request.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:sello/data/providers/repository_providers.dart'
    show employeeRepositoryProvider;

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final companyRepositoryProvider =
    Provider<CompanyRepository>((ref) => CompanyRepository());

final branchRepositoryProvider =
    Provider<BranchRepository>((ref) => BranchRepository());

final provisioningRepositoryProvider =
    Provider<ProvisioningRepository>((ref) => ProvisioningRepository());

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    employeeRepository: ref.watch(employeeRepositoryProvider),
    settingsRepository: ref.watch(companySettingsRepositoryProvider),
  );
});

final provisioningCoordinatorProvider =
    Provider<ProvisioningCoordinator>((ref) {
  return ProvisioningCoordinator(
    authService: ref.watch(authServiceProvider),
    companyRepository: ref.watch(companyRepositoryProvider),
    provisioningRepository: ref.watch(provisioningRepositoryProvider),
    sessionService: ref.watch(sessionServiceProvider),
  );
});

/// Auth + application session state for guards and chrome.
class AuthSessionState {
  const AuthSessionState({
    this.status = AuthStatus.unknown,
    this.session,
    this.isLoading = false,
    this.errorMessage,
    this.infoMessage,
    this.requiresOnboarding = false,
    this.isPasswordRecovery = false,
    this.isTeamInvitePasswordSetup = false,
    this.awaitingEmailConfirmation = false,
    this.emailJustVerified = false,
    this.pendingEmail,
  });

  final AuthStatus status;
  final AppSession? session;
  final bool isLoading;
  final String? errorMessage;
  final String? infoMessage;
  final bool requiresOnboarding;
  final bool isPasswordRecovery;

  /// Recovery came from a Hub team invite (`sello_team_invite` user_metadata).
  ///
  /// Drives LoginPage invite vs forgot-password copy. False for Owner
  /// self-service password reset.
  final bool isTeamInvitePasswordSetup;
  final bool awaitingEmailConfirmation;
  final bool emailJustVerified;
  final String? pendingEmail;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && session != null;

  bool get isBootstrapping => status == AuthStatus.unknown;

  bool get isAuthenticating => status == AuthStatus.authenticating;

  AuthSessionState copyWith({
    AuthStatus? status,
    AppSession? session,
    bool? isLoading,
    String? errorMessage,
    String? infoMessage,
    bool? requiresOnboarding,
    bool? isPasswordRecovery,
    bool? isTeamInvitePasswordSetup,
    bool? awaitingEmailConfirmation,
    bool? emailJustVerified,
    String? pendingEmail,
    bool clearSession = false,
    bool clearError = false,
    bool clearInfo = false,
    bool clearPendingEmail = false,
  }) {
    return AuthSessionState(
      status: status ?? this.status,
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      requiresOnboarding: requiresOnboarding ?? this.requiresOnboarding,
      isPasswordRecovery: isPasswordRecovery ?? this.isPasswordRecovery,
      isTeamInvitePasswordSetup:
          isTeamInvitePasswordSetup ?? this.isTeamInvitePasswordSetup,
      awaitingEmailConfirmation:
          awaitingEmailConfirmation ?? this.awaitingEmailConfirmation,
      emailJustVerified: emailJustVerified ?? this.emailJustVerified,
      pendingEmail:
          clearPendingEmail ? null : (pendingEmail ?? this.pendingEmail),
    );
  }
}

/// Orchestrates Supabase Auth + AppSession construction.
class AuthSessionNotifier extends Notifier<AuthSessionState> {
  StreamSubscription<AuthState>? _authSub;
  bool _handlingAuthEvent = false;

  /// In-memory latch for invite / forgot-password recovery.
  ///
  /// Survives auth-event ordering where [AuthChangeEvent.signedIn] arrives
  /// instead of (or after) [AuthChangeEvent.passwordRecovery]. Cleared only by
  /// a successful [completePasswordRecovery], [signIn], [signOut], or a normal
  /// cold start that is not a recovery redirect.
  bool _passwordRecoveryActive = false;

  AuthService get _auth => ref.read(authServiceProvider);
  SessionService get _sessions => ref.read(sessionServiceProvider);
  ProvisioningCoordinator get _provisioning =>
      ref.read(provisioningCoordinatorProvider);

  @override
  AuthSessionState build() {
    ref.onDispose(() {
      _authSub?.cancel();
    });

    Future.microtask(_bootstrap);
    return const AuthSessionState(status: AuthStatus.unknown, isLoading: true);
  }

  Future<void> _bootstrap() async {
    state = const AuthSessionState(
      status: AuthStatus.unknown,
      isLoading: true,
    );
    _passwordRecoveryActive = false;

    _authSub?.cancel();
    // GoTrue uses a BehaviorSubject — listen() synchronously replays the last
    // event from Supabase.initialize (often PASSWORD_RECOVERY for invite links).
    _authSub = _auth.authStateChanges.listen(_onAuthStateChanged);

    if (_passwordRecoveryActive || state.isPasswordRecovery) {
      _enterPasswordRecovery();
      return;
    }

    if (PasswordRecoveryRedirect.isIndicatedBy(Uri.base)) {
      _enterPasswordRecovery();
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      state = const AuthSessionState(status: AuthStatus.unauthenticated);
      return;
    }

    await _hydrateSession(user);
  }

  void _enterPasswordRecovery() {
    _passwordRecoveryActive = true;
    final inviteSetup = AuthEmailPersonalization.isTeamInviteMetadata(
      _auth.currentUser?.userMetadata,
    );
    state = AuthSessionState(
      status: AuthStatus.unauthenticated,
      isPasswordRecovery: true,
      isTeamInvitePasswordSetup: inviteSetup,
      infoMessage: inviteSetup
          ? 'Choose a password to finish joining your team.'
          : 'Choose a new password to finish account recovery.',
    );
  }

  void _clearPasswordRecoveryLatch() {
    _passwordRecoveryActive = false;
  }

  Future<void> _onAuthStateChanged(AuthState authState) async {
    if (_handlingAuthEvent) return;

    switch (authState.event) {
      case AuthChangeEvent.signedOut:
        _clearPasswordRecoveryLatch();
        if (state.awaitingEmailConfirmation) {
          state = AuthSessionState(
            status: AuthStatus.unauthenticated,
            awaitingEmailConfirmation: true,
            pendingEmail: state.pendingEmail,
            infoMessage: state.infoMessage,
          );
          return;
        }
        if (state.emailJustVerified) {
          state = AuthSessionState(
            status: AuthStatus.unauthenticated,
            emailJustVerified: true,
            infoMessage: state.infoMessage ??
                'Email verified successfully. Please sign in to continue.',
          );
          return;
        }
        state = const AuthSessionState(status: AuthStatus.unauthenticated);
      case AuthChangeEvent.passwordRecovery:
        _enterPasswordRecovery();
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        // Recovery sessions are real GoTrue sessions. Hydrating them would
        // clear isPasswordRecovery and skip the set-password UI (Sales invite
        // and Owner forgot-password both rely on that screen).
        if (_passwordRecoveryActive || state.isPasswordRecovery) {
          _enterPasswordRecovery();
          return;
        }
        final user = authState.session?.user ?? _auth.currentUser;
        if (user == null) {
          state = const AuthSessionState(status: AuthStatus.unauthenticated);
          return;
        }
        if (state.status == AuthStatus.authenticating) return;
        if (state.session?.userId == user.id && state.isAuthenticated) {
          return;
        }
        await _hydrateSession(user);
      default:
        break;
    }
  }

  Future<void> _hydrateSession(User user, {bool quiet = false}) async {
    // Never treat an invite/recovery session as a finished workspace login
    // unless the user just submitted a new password (completePasswordRecovery).
    if ((_passwordRecoveryActive || state.isPasswordRecovery) &&
        !_handlingAuthEvent) {
      _enterPasswordRecovery();
      return;
    }

    // Quiet reload keeps status authenticated so route guards do not bounce
    // through /login (Owner setup completion, branding refresh, etc.).
    final quietReload = quiet && state.isAuthenticated && state.session != null;
    state = state.copyWith(
      status: state.isBootstrapping
          ? AuthStatus.unknown
          : (quietReload
              ? AuthStatus.authenticated
              : AuthStatus.authenticating),
      isLoading: true,
      clearError: true,
      clearInfo: true,
      requiresOnboarding: false,
      awaitingEmailConfirmation: false,
      emailJustVerified: false,
      clearPendingEmail: true,
      isPasswordRecovery: false,
    );

    try {
      final session = await _sessions.buildSession(user);
      _clearPasswordRecoveryLatch();
      state = AuthSessionState(
        status: AuthStatus.authenticated,
        session: session,
      );
    } on UnlinkedEmployeeFailure {
      await _handleUnlinkedEmployee();
    } on AppFailure catch (failure) {
      if (_passwordRecoveryActive || state.isPasswordRecovery) {
        _enterPasswordRecovery();
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
        );
        return;
      }
      await _failHydrate(failure.message);
    } catch (_) {
      if (_passwordRecoveryActive || state.isPasswordRecovery) {
        _enterPasswordRecovery();
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Unable to load your profile. Please try again.',
        );
        return;
      }
      await _failHydrate('Unable to load your profile. Please try again.');
    }
  }

  /// Auth user exists but no employee row yet.
  ///
  /// Completes server-side pending onboarding when present. Only routes to the
  /// wizard when there is genuinely nothing to finish for this auth user.
  Future<void> _handleUnlinkedEmployee() async {
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      infoMessage: 'Preparing your workspace...',
      clearError: true,
    );

    try {
      final session = await _provisioning.completePendingOnboarding();
      state = AuthSessionState(
        status: AuthStatus.authenticated,
        session: session,
        infoMessage: 'Welcome to Sello',
      );
      return;
    } on SignupInvitationFailure catch (failure) {
      _handlingAuthEvent = true;
      try {
        await _auth.signOut();
      } catch (_) {
        // Ignore secondary sign-out errors.
      } finally {
        _handlingAuthEvent = false;
      }
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        errorMessage: failure.message,
      );
      return;
    } on NeedsOnboardingFailure catch (failure) {
      // Keep the Supabase session so recovery can upsert pending + complete.
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        requiresOnboarding: true,
        infoMessage: failure.message,
      );
      return;
    } on AppFailure catch (failure) {
      state = state.copyWith(
        errorMessage: failure.message,
        isLoading: false,
        infoMessage: null,
      );
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Unable to finish setting up your business.',
        isLoading: false,
        infoMessage: null,
      );
    }

    // Non-recoverable complete failure during a passive auth event:
    // fall back to a verified → sign-in prompt.
    if (!_handlingAuthEvent) {
      _handlingAuthEvent = true;
      try {
        await _auth.signOut();
      } catch (_) {
        // Ignore secondary sign-out errors.
      } finally {
        _handlingAuthEvent = false;
      }

      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        emailJustVerified: true,
        errorMessage: state.errorMessage,
        infoMessage:
            'Email verified successfully. Please sign in to continue.',
      );
    } else {
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        requiresOnboarding: true,
        errorMessage: state.errorMessage,
        infoMessage:
            'Your account is ready. Finish creating your business to continue.',
      );
    }
  }

  Future<void> _failHydrate(String message) async {
    _clearPasswordRecoveryLatch();
    _handlingAuthEvent = true;
    try {
      await _auth.signOut();
    } catch (_) {
      // Ignore secondary sign-out errors.
    } finally {
      _handlingAuthEvent = false;
    }
    state = AuthSessionState(
      status: AuthStatus.unauthenticated,
      errorMessage: message,
    );
  }

  /// Email + password login. Experience is derived from employee role.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _clearPasswordRecoveryLatch();
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
      clearInfo: true,
      requiresOnboarding: false,
      isPasswordRecovery: false,
      isTeamInvitePasswordSetup: false,
      awaitingEmailConfirmation: false,
      emailJustVerified: false,
      clearPendingEmail: true,
      clearSession: true,
    );

    try {
      _handlingAuthEvent = true;
      final response = await _auth.signInWithEmailPassword(
        email: email,
        password: password,
      );
      final user = response.user ?? _auth.currentUser;
      if (user == null) {
        throw const AuthFailure('Sign-in failed. Please try again.');
      }
      await _hydrateSession(user);
    } on AppFailure catch (failure) {
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        errorMessage: failure.message,
      );
    } catch (_) {
      state = const AuthSessionState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Unable to sign in. Please try again.',
      );
    } finally {
      _handlingAuthEvent = false;
    }
  }

  /// Creates auth user + server pending row, then completes into Sello Hub
  /// when a session is available.
  Future<void> provisionBusiness(ProvisionBusinessRequest request) async {
    _clearPasswordRecoveryLatch();
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
      clearInfo: true,
      requiresOnboarding: false,
      isPasswordRecovery: false,
      awaitingEmailConfirmation: false,
      emailJustVerified: false,
      clearPendingEmail: true,
      clearSession: true,
    );

    try {
      _handlingAuthEvent = true;
      final session = await _provisioning.provision(request);
      state = AuthSessionState(
        status: AuthStatus.authenticated,
        session: session,
        infoMessage: 'Welcome to Sello',
      );
    } on EmailConfirmationRequiredFailure catch (failure) {
      // Auth user + server pending row exist; tenant waits for verify + sign-in.
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        awaitingEmailConfirmation: true,
        pendingEmail: failure.email,
        infoMessage: failure.message,
      );
    } on SignupInvitationFailure catch (failure) {
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        errorMessage: failure.message,
      );
    } on AppFailure catch (failure) {
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        errorMessage: failure.message,
        requiresOnboarding: _auth.currentUser != null,
      );
    } catch (_) {
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Unable to create your business. Please try again.',
        requiresOnboarding: _auth.currentUser != null,
      );
    } finally {
      _handlingAuthEvent = false;
    }
  }

  Future<void> resendSignupConfirmation() async {
    final email = state.pendingEmail;
    if (email == null || email.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No email address is available to resend.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true, clearInfo: true);
    try {
      await _auth.resendSignupConfirmation(email);
      state = state.copyWith(
        isLoading: false,
        infoMessage: 'Verification email sent again. Check your inbox.',
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to resend the email. Please try again.',
      );
    }
  }

  Future<void> completePasswordRecovery({
    required String password,
  }) async {
    final inviteSetup = state.isTeamInvitePasswordSetup;
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
      clearInfo: true,
      isPasswordRecovery: true,
      isTeamInvitePasswordSetup: inviteSetup,
    );

    try {
      _handlingAuthEvent = true;
      await _auth.updatePassword(
        password,
        userMetadata: inviteSetup
            ? {AuthEmailPersonalization.teamInviteKey: false}
            : null,
      );
      final user = _auth.currentUser;
      if (user == null) {
        throw const AuthFailure(
          'Password updated, but your session expired. Please sign in.',
        );
      }
      // Hydrate while _handlingAuthEvent is true so the recovery latch does
      // not block workspace entry after a successful password update.
      await _hydrateSession(user);
    } on AppFailure catch (failure) {
      _enterPasswordRecovery();
      state = state.copyWith(errorMessage: failure.message);
    } catch (_) {
      _enterPasswordRecovery();
      state = state.copyWith(
        errorMessage: 'Unable to update your password. Please try again.',
      );
    } finally {
      _handlingAuthEvent = false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      _handlingAuthEvent = true;
      await _auth.signOut();
    } on AppFailure catch (failure) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      );
      return;
    } finally {
      _handlingAuthEvent = false;
    }
    _clearPasswordRecoveryLatch();
    state = const AuthSessionState(status: AuthStatus.unauthenticated);
  }

  Future<void> reloadSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      state = const AuthSessionState(status: AuthStatus.unauthenticated);
      return;
    }
    await _hydrateSession(user, quiet: true);
  }

  /// Clears the email-confirmation success screen and returns to a clean
  /// unauthenticated state (e.g. "Back to Sign In").
  void clearEmailConfirmationWait() {
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
  return ref.watch(currentSessionProvider)?.appRole;
});

final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authSessionProvider).status;
});
