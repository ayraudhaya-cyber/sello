import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/branch_repository.dart';
import 'package:sello/data/repositories/company_repository.dart';
import 'package:sello/data/repositories/provisioning_repository.dart';
import 'package:sello/services/auth/auth_service.dart';
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

    _authSub?.cancel();
    _authSub = _auth.authStateChanges.listen(_onAuthStateChanged);

    final user = _auth.currentUser;
    if (user == null) {
      state = const AuthSessionState(status: AuthStatus.unauthenticated);
      return;
    }

    await _hydrateSession(user);
  }

  Future<void> _onAuthStateChanged(AuthState authState) async {
    if (_handlingAuthEvent) return;

    switch (authState.event) {
      case AuthChangeEvent.signedOut:
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
        state = const AuthSessionState(
          status: AuthStatus.unauthenticated,
          isPasswordRecovery: true,
          infoMessage: 'Choose a new password to finish account recovery.',
        );
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
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

  Future<void> _hydrateSession(User user) async {
    state = state.copyWith(
      status: state.isBootstrapping
          ? AuthStatus.unknown
          : AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
      clearInfo: true,
      requiresOnboarding: false,
      awaitingEmailConfirmation: false,
      emailJustVerified: false,
      clearPendingEmail: true,
    );

    try {
      final session = await _sessions.buildSession(user);
      state = AuthSessionState(
        status: AuthStatus.authenticated,
        session: session,
      );
    } on UnlinkedEmployeeFailure {
      await _handleUnlinkedEmployee();
    } on AppFailure catch (failure) {
      if (state.isPasswordRecovery) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          isLoading: false,
          clearError: true,
          infoMessage: 'Choose a new password to finish account recovery.',
        );
        return;
      }
      await _failHydrate(failure.message);
    } catch (_) {
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
    state = state.copyWith(
      status: AuthStatus.authenticating,
      isLoading: true,
      clearError: true,
      clearInfo: true,
    );

    try {
      _handlingAuthEvent = true;
      await _auth.updatePassword(password);
      final user = _auth.currentUser;
      if (user == null) {
        throw const AuthFailure(
          'Password updated, but your session expired. Please sign in.',
        );
      }
      await _hydrateSession(user);
    } on AppFailure catch (failure) {
      state = AuthSessionState(
        status: AuthStatus.unauthenticated,
        isPasswordRecovery: true,
        errorMessage: failure.message,
      );
    } catch (_) {
      state = const AuthSessionState(
        status: AuthStatus.unauthenticated,
        isPasswordRecovery: true,
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
    state = const AuthSessionState(status: AuthStatus.unauthenticated);
  }

  Future<void> reloadSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      state = const AuthSessionState(status: AuthStatus.unauthenticated);
      return;
    }
    await _hydrateSession(user);
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
