import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/constants/app_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Local login-card modes (distinct from Auth deep-link recovery).
enum _LoginCardMode {
  signIn,
  requestReset,
  resetSent,
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscure = true;
  bool _sendingRecovery = false;
  _LoginCardMode _cardMode = _LoginCardMode.signIn;
  String? _recoveryError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _clearFormValidation() {
    _formKey.currentState?.reset();
  }

  void _enterRequestReset() {
    FocusScope.of(context).unfocus();
    _clearFormValidation();
    setState(() {
      _cardMode = _LoginCardMode.requestReset;
      _recoveryError = null;
      _sendingRecovery = false;
    });
  }

  void _backToSignIn() {
    FocusScope.of(context).unfocus();
    _clearFormValidation();
    setState(() {
      _cardMode = _LoginCardMode.signIn;
      _recoveryError = null;
      _sendingRecovery = false;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  Future<void> _submit() async {
    if (ref.read(authSessionProvider).isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authSessionProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  Future<void> _completeRecovery() async {
    if (ref.read(authSessionProvider).isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(authSessionProvider.notifier)
        .completePasswordRecovery(password: _passwordController.text);
  }

  Future<void> _sendRecoveryEmail() async {
    if (_sendingRecovery) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _sendingRecovery = true;
      _recoveryError = null;
    });
    try {
      await ref.read(authServiceProvider).sendPasswordRecovery(email: email);
      if (!mounted) return;
      _clearFormValidation();
      setState(() {
        _cardMode = _LoginCardMode.resetSent;
        _sendingRecovery = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _recoveryError = failure.message;
        _sendingRecovery = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recoveryError = 'Could not send the reset link. Please try again.';
        _sendingRecovery = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final setNewPassword = auth.isPasswordRecovery;
    final loading = auth.isLoading || auth.isAuthenticating || _sendingRecovery;

    // Deep-link recovery always wins over the local request-reset card.
    final mode = setNewPassword ? null : _cardMode;

    return Scaffold(
      body: AuthShellLayout(
        child: _LoginForm(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          confirmPasswordController: _confirmPasswordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          loading: loading,
          errorMessage: setNewPassword
              ? auth.errorMessage
              : (mode == _LoginCardMode.signIn
                  ? auth.errorMessage
                  : _recoveryError),
          infoMessage: auth.infoMessage,
          emailJustVerified: auth.emailJustVerified,
          setNewPassword: setNewPassword,
          cardMode: mode ?? _LoginCardMode.signIn,
          onSubmit: setNewPassword ? _completeRecovery : _submit,
          onForgotPassword: _enterRequestReset,
          onSendResetLink: _sendRecoveryEmail,
          onBackToSignIn: _backToSignIn,
        ),
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.errorMessage,
    required this.infoMessage,
    required this.emailJustVerified,
    required this.setNewPassword,
    required this.cardMode,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onSendResetLink,
    required this.onBackToSignIn,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool loading;
  final String? errorMessage;
  final String? infoMessage;
  final bool emailJustVerified;
  final bool setNewPassword;
  final _LoginCardMode cardMode;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onSendResetLink;
  final VoidCallback onBackToSignIn;

  void _primaryIfReady() {
    if (loading) return;
    if (setNewPassword) {
      onSubmit();
      return;
    }
    switch (cardMode) {
      case _LoginCardMode.signIn:
        onSubmit();
      case _LoginCardMode.requestReset:
        onSendResetLink();
      case _LoginCardMode.resetSent:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (setNewPassword) {
      return _authCard(
        context,
        title: 'Reset password',
        subtitle:
            'Create a new password to restore access to ${AppConstants.appName}',
        fields: _setNewPasswordFields(context),
        primaryLabel: 'Update password',
        onPrimary: onSubmit,
        showInfo: true,
      );
    }

    return switch (cardMode) {
      _LoginCardMode.signIn => _authCard(
          context,
          title: 'Welcome back',
          subtitle: 'Sign in to continue to ${AppConstants.appName}',
          fields: _signInFields(context),
          primaryLabel: 'Sign in',
          onPrimary: onSubmit,
          showInfo: true,
          footer: [
            AuthTextLink(
              label: 'Forgot password?',
              onPressed: loading ? null : onForgotPassword,
            ),
            AuthTextLink(
              label: "Don't have an account? Create account",
              onPressed: loading
                  ? null
                  : () => context.go(RoutePaths.onboarding),
            ),
          ],
        ),
      _LoginCardMode.requestReset => _authCard(
          context,
          title: 'Reset your password',
          subtitle:
              "Enter your email address and we'll send you a link to reset your password.",
          fields: _requestResetFields(context),
          primaryLabel: 'Send reset link',
          onPrimary: onSendResetLink,
          footer: [
            AuthTextLink(
              label: 'Back to sign in',
              onPressed: loading ? null : onBackToSignIn,
            ),
          ],
        ),
      _LoginCardMode.resetSent => _authCard(
          context,
          title: 'Check your email',
          subtitle: "We've sent a password reset link to your email.",
          fields: const [],
          primaryLabel: null,
          onPrimary: null,
          footer: [
            AuthTextLink(
              label: 'Back to sign in',
              onPressed: loading ? null : onBackToSignIn,
            ),
          ],
        ),
    };
  }

  Widget _authCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> fields,
    required String? primaryLabel,
    required VoidCallback? onPrimary,
    List<Widget> footer = const [],
    bool showInfo = false,
  }) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _primaryIfReady,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _primaryIfReady,
      },
      child: Focus(
        skipTraversal: true,
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SelloBrandMark(size: 40),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  style: context.texts.headlineLarge,
                  softWrap: true,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.selloColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (fields.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  ...fields,
                ],
                if (showInfo && infoMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _InfoBanner(
                    message: infoMessage!,
                    success: emailJustVerified,
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    errorMessage!,
                    style: context.texts.bodySmall?.copyWith(
                      color: AppColors.error,
                      height: 1.35,
                    ),
                  ),
                ],
                if (primaryLabel != null && onPrimary != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  SelloButton(
                    label: primaryLabel,
                    variant: SelloButtonVariant.primary,
                    expanded: true,
                    loading: loading,
                    onPressed: loading ? null : onPrimary,
                  ),
                ],
                if (footer.isNotEmpty) ...[
                  if (primaryLabel == null)
                    const SizedBox(height: AppSpacing.xl)
                  else
                    const SizedBox(height: AppSpacing.sm),
                  ...footer,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _signInFields(BuildContext context) {
    return [
      SelloTextField(
        controller: emailController,
        label: 'Email',
        required: true,
        hint: 'you@company.com',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.mail_outline_rounded,
        autofillHints: const [AutofillHints.email],
        enabled: !loading,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Email is required';
          if (!v.contains('@')) return 'Enter a valid email';
          return null;
        },
      ),
      const SizedBox(height: AppSpacing.md),
      SelloTextField(
        controller: passwordController,
        label: 'Password',
        required: true,
        obscureText: obscure,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: loading ? null : (_) => onSubmit(),
        prefixIcon: Icons.lock_outline_rounded,
        enabled: !loading,
        autofillHints: const [AutofillHints.password],
        suffixIcon: ExcludeFocus(
          child: IconButton(
            onPressed: loading ? null : onToggleObscure,
            tooltip: obscure ? 'Show password' : 'Hide password',
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Password is required';
          return null;
        },
      ),
    ];
  }

  List<Widget> _requestResetFields(BuildContext context) {
    return [
      SelloTextField(
        controller: emailController,
        label: 'Email',
        required: true,
        hint: 'Enter your email',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: loading ? null : (_) => onSendResetLink(),
        prefixIcon: Icons.mail_outline_rounded,
        autofillHints: const [AutofillHints.email],
        enabled: !loading,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Email is required';
          if (!v.contains('@')) return 'Enter a valid email';
          return null;
        },
      ),
    ];
  }

  List<Widget> _setNewPasswordFields(BuildContext context) {
    return [
      SelloTextField(
        controller: passwordController,
        label: 'New password',
        required: true,
        obscureText: obscure,
        textInputAction: TextInputAction.next,
        prefixIcon: Icons.lock_outline_rounded,
        enabled: !loading,
        autofillHints: const [AutofillHints.newPassword],
        suffixIcon: ExcludeFocus(
          child: IconButton(
            onPressed: loading ? null : onToggleObscure,
            tooltip: obscure ? 'Show password' : 'Hide password',
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Password is required';
          if (v.length < 8) {
            return 'Password must be at least 8 characters';
          }
          return null;
        },
      ),
      const SizedBox(height: AppSpacing.md),
      SelloTextField(
        controller: confirmPasswordController,
        label: 'Confirm password',
        obscureText: obscure,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: loading ? null : (_) => onSubmit(),
        prefixIcon: Icons.lock_reset_rounded,
        enabled: !loading,
        autofillHints: const [AutofillHints.newPassword],
        validator: (v) {
          if (v == null || v.isEmpty) {
            return 'Please confirm your password';
          }
          if (v != passwordController.text) {
            return 'Passwords do not match';
          }
          return null;
        },
      ),
    ];
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, required this.success});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: success ? AppColors.successContainer : AppColors.infoContainer,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.verified_rounded : Icons.info_outline_rounded,
            size: 18,
            color: success ? AppColors.success : AppColors.info,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodySmall?.copyWith(
                color: success ? AppColors.success : AppColors.info,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
