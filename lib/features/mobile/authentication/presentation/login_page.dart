import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/constants/app_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref.read(authSessionProvider.notifier).signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  Future<void> _completeRecovery() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref.read(authSessionProvider.notifier).completePasswordRecovery(
          password: _passwordController.text,
        );
  }

  Future<void> _sendRecoveryEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() => _sendingRecovery = true);
    try {
      await ref.read(authServiceProvider).sendPasswordRecovery(email: email);
      if (!mounted) return;
      SelloSnackbars.success(
        context,
        'Password recovery email sent. Check your inbox.',
      );
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.error(context, failure.message);
    } finally {
      if (mounted) {
        setState(() => _sendingRecovery = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final recoveryMode = auth.isPasswordRecovery;
    final loading = auth.isLoading || auth.isAuthenticating || _sendingRecovery;

    return Scaffold(
      body: ResponsiveBuilder(
        mobile: (_) => _MobileLogin(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          confirmPasswordController: _confirmPasswordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          loading: loading,
          errorMessage: auth.errorMessage,
          infoMessage: auth.infoMessage,
          emailJustVerified: auth.emailJustVerified,
          recoveryMode: recoveryMode,
          onSubmit: recoveryMode ? _completeRecovery : _submit,
          onSendRecovery: _sendRecoveryEmail,
        ),
        tablet: (_) => _SplitLogin(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          confirmPasswordController: _confirmPasswordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          loading: loading,
          errorMessage: auth.errorMessage,
          infoMessage: auth.infoMessage,
          emailJustVerified: auth.emailJustVerified,
          recoveryMode: recoveryMode,
          onSubmit: recoveryMode ? _completeRecovery : _submit,
          onSendRecovery: _sendRecoveryEmail,
        ),
        desktop: (_) => _SplitLogin(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          confirmPasswordController: _confirmPasswordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          loading: loading,
          errorMessage: auth.errorMessage,
          infoMessage: auth.infoMessage,
          emailJustVerified: auth.emailJustVerified,
          recoveryMode: recoveryMode,
          onSubmit: recoveryMode ? _completeRecovery : _submit,
          onSendRecovery: _sendRecoveryEmail,
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
    required this.recoveryMode,
    required this.onSubmit,
    required this.onSendRecovery,
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
  final bool recoveryMode;
  final VoidCallback onSubmit;
  final VoidCallback onSendRecovery;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SelloBrandMark(size: 40),
            const SizedBox(height: AppSpacing.xl),
            Text(
              recoveryMode ? 'Reset password' : 'Welcome back',
              style: context.texts.headlineLarge,
              softWrap: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              recoveryMode
                  ? 'Create a new password to restore access to ${AppConstants.appName}'
                  : 'Sign in to continue to ${AppConstants.appName}',
              style: context.texts.bodyMedium?.copyWith(
                color: context.selloColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (!recoveryMode) ...[
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
                  if (v == null || v.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SelloTextField(
              controller: passwordController,
              label: recoveryMode ? 'New password' : 'Password',
              required: true,
              obscureText: obscure,
              textInputAction:
                  recoveryMode ? TextInputAction.next : TextInputAction.done,
              prefixIcon: Icons.lock_outline_rounded,
              enabled: !loading,
              autofillHints: [
                recoveryMode
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              suffixIcon: IconButton(
                onPressed: loading ? null : onToggleObscure,
                tooltip: obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (recoveryMode && v.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
            ),
            if (recoveryMode) ...[
              const SizedBox(height: AppSpacing.md),
              SelloTextField(
                controller: confirmPasswordController,
                label: 'Confirm password',
                obscureText: obscure,
                textInputAction: TextInputAction.done,
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
            ],
            if (infoMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: emailJustVerified
                      ? AppColors.successContainer
                      : AppColors.infoContainer,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      emailJustVerified
                          ? Icons.verified_rounded
                          : Icons.info_outline_rounded,
                      size: 18,
                      color: emailJustVerified
                          ? AppColors.success
                          : AppColors.info,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        infoMessage!,
                        style: context.texts.bodySmall?.copyWith(
                          color: emailJustVerified
                              ? AppColors.success
                              : AppColors.info,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
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
            const SizedBox(height: AppSpacing.xl),
            SelloButton(
              label: recoveryMode ? 'Update password' : 'Sign in',
              variant: SelloButtonVariant.primary,
              expanded: true,
              loading: loading,
              onPressed: loading ? null : onSubmit,
            ),
            if (!recoveryMode) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: loading ? null : onSendRecovery,
                child: const Text('Forgot password?'),
              ),
              TextButton(
                onPressed: loading
                    ? null
                    : () => context.go(RoutePaths.onboarding),
                child: const Text("Don't have an account? Create account"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobileLogin extends StatelessWidget {
  const _MobileLogin({
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
    required this.recoveryMode,
    required this.onSubmit,
    required this.onSendRecovery,
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
  final bool recoveryMode;
  final VoidCallback onSubmit;
  final VoidCallback onSendRecovery;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.heroWash),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(context.pagePadding),
            child: SelloCard(
              elevation: SelloCardElevation.raised,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _LoginForm(
                formKey: formKey,
                emailController: emailController,
                passwordController: passwordController,
                confirmPasswordController: confirmPasswordController,
                obscure: obscure,
                onToggleObscure: onToggleObscure,
                loading: loading,
                errorMessage: errorMessage,
                infoMessage: infoMessage,
                emailJustVerified: emailJustVerified,
                recoveryMode: recoveryMode,
                onSubmit: onSubmit,
                onSendRecovery: onSendRecovery,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitLogin extends ConsumerWidget {
  const _SplitLogin({
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
    required this.recoveryMode,
    required this.onSubmit,
    required this.onSendRecovery,
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
  final bool recoveryMode;
  final VoidCallback onSubmit;
  final VoidCallback onSendRecovery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider);
    final brandedChrome =
        branding.hasCustomLogo || branding.hasCustomNavBackground;
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: brandedChrome
                  ? context.selloColors.navRail
                  : context.selloColors.primaryGradient,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const BrandedLaunchLockup(
                    lightOnDark: true,
                    clientLogoSize: 64,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppConstants.appTagline,
                    style: context.texts.titleMedium?.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: _LoginForm(
                  formKey: formKey,
                  emailController: emailController,
                  passwordController: passwordController,
                  confirmPasswordController: confirmPasswordController,
                  obscure: obscure,
                  onToggleObscure: onToggleObscure,
                  loading: loading,
                  errorMessage: errorMessage,
                  infoMessage: infoMessage,
                  emailJustVerified: emailJustVerified,
                  recoveryMode: recoveryMode,
                  onSubmit: onSubmit,
                  onSendRecovery: onSendRecovery,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
