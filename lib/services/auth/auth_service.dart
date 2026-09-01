import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/services/supabase/supabase_config.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase Auth (email/password).
class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  User? get currentUser => _auth.currentUser;

  Session? get currentSession => _auth.currentSession;

  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// Email + password sign-in. Session is persisted by Supabase Auth.
  Future<AuthResponse> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (error) {
      throw AuthFailure(_mapAuthMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Email + password sign-up for business provisioning.
  ///
  /// [pendingBusiness] is stored in `raw_user_meta_data` and copied by a DB
  /// trigger into `pending_business_provisions` (never includes password).
  ///
  /// When email confirmation is disabled, a session is returned immediately.
  /// Confirmation emails redirect to login so verified users can sign in.
  Future<AuthResponse> signUpWithEmailPassword({
    required String email,
    required String password,
    Map<String, dynamic>? pendingBusiness,
  }) async {
    try {
      return await _auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: pendingBusiness == null
            ? null
            : {'pending_business': pendingBusiness},
        emailRedirectTo: _redirectUrlFor(RoutePaths.login),
      );
    } on AuthException catch (error) {
      if (error.message.toUpperCase().contains('SIGNUP_NOT_INVITED')) {
        throw const SignupInvitationFailure();
      }
      throw AuthFailure(_mapSignUpMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> resendSignupConfirmation(String email) async {
    try {
      await _auth.resend(
        type: OtpType.signup,
        email: email.trim().toLowerCase(),
        emailRedirectTo: _redirectUrlFor(RoutePaths.login),
      );
    } on AuthException catch (error) {
      throw AuthFailure(_mapSignUpMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException catch (error) {
      throw AuthFailure(_mapAuthMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> sendMagicLink({
    required String email,
    String redirectPath = RoutePaths.login,
  }) async {
    try {
      await _auth.signInWithOtp(
        email: email.trim().toLowerCase(),
        emailRedirectTo: _redirectUrlFor(redirectPath),
      );
    } on AuthException catch (error) {
      throw AuthFailure(_mapAuthMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> sendPasswordRecovery({
    required String email,
    String redirectPath = RoutePaths.login,
  }) async {
    try {
      await _auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: _redirectUrlFor(redirectPath),
      );
    } on AuthException catch (error) {
      throw AuthFailure(_mapAuthMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<UserResponse> updatePassword(String password) async {
    try {
      return await _auth.updateUser(
        UserAttributes(password: password),
      );
    } on AuthException catch (error) {
      throw AuthFailure(_mapSignUpMessage(error.message));
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Creates an Auth user without switching the signed-in Hub session.
  ///
  /// Uses an ephemeral Supabase client with in-memory PKCE storage so the
  /// owner's session stays intact. Caller should send a password-recovery
  /// email afterward so the employee can set their own password.
  Future<String> createAuthUserWithoutSessionSwitch({
    required String email,
  }) async {
    final password = _randomPassword();
    final storage = _MemoryGotrueStorage();
    final inviteClient = SupabaseClient(
      SupabaseConfig.url,
      SupabaseConfig.publishableKey,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: storage,
        authFlowType: AuthFlowType.pkce,
      ),
    );

    try {
      final response = await inviteClient.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        emailRedirectTo: _redirectUrlFor(RoutePaths.login),
      );
      final user = response.user;
      final userId = user?.id;
      if (userId == null || userId.isEmpty) {
        throw const AuthFailure(
          'Unable to create a login for this email. Check Auth settings.',
        );
      }
      // When "Confirm email" is enabled, signUp for an existing address returns
      // an obfuscated user that is NOT in auth.users — empty identities.
      if (user!.identities == null || user.identities!.isEmpty) {
        throw const AuthFailure(
          'An Auth account already exists for this email. '
          'Ask them to sign in, or use Send invite after they have a login.',
        );
      }
      return userId;
    } on AuthException catch (error) {
      throw AuthFailure(_mapInviteMessage(error.message));
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw UnexpectedFailure(error.toString());
    } finally {
      try {
        await inviteClient.auth.signOut();
      } catch (_) {}
      inviteClient.dispose();
    }
  }

  String _randomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#\$%';
    final random = Random.secure();
    return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String? _redirectUrlFor(String path) {
    if (!kIsWeb) return null;
    final base = Uri.base;
    return base
        .replace(
          path: path,
          query: null,
          fragment: null,
        )
        .toString();
  }

  static String _mapAuthMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login') ||
        lower.contains('invalid credentials')) {
      return 'Invalid email or password.';
    }
    if (lower.contains('email not confirmed') ||
        lower.contains('not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (message.trim().isEmpty) return 'Something went wrong. Please try again.';
    return message;
  }

  static String _mapSignUpMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('signup_not_invited')) {
      return const SignupInvitationFailure().message;
    }
    if (lower.contains('already registered') ||
        lower.contains('already been registered') ||
        lower.contains('user already exists')) {
      return 'An account with this email already exists. Sign in instead.';
    }
    if (lower.contains('password')) {
      return message.isEmpty
          ? 'Password must be at least 8 characters.'
          : message;
    }
    if (lower.contains('rate limit') || lower.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('email')) {
      return message.isEmpty ? 'Enter a valid email address.' : message;
    }
    return message.isEmpty
        ? 'Unable to create your account. Please try again.'
        : message;
  }

  static String _mapInviteMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('already registered') ||
        lower.contains('already been registered') ||
        lower.contains('user already exists')) {
      return 'An Auth account already exists for this email. '
          'Ask them to sign in, or link an existing user later.';
    }
    return _mapSignUpMessage(message);
  }
}

class _MemoryGotrueStorage extends GotrueAsyncStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> getItem({required String key}) async => _map[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _map[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _map.remove(key);
  }
}
