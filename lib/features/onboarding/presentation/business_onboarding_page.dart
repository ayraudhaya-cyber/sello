import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/onboarding/application/onboarding_provider.dart';
import 'package:sello/services/onboarding/onboarding_validation.dart';
import 'package:sello/services/onboarding/signup_invite_policy.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Public self-service signup. Tenant creation runs after email verification.
class BusinessOnboardingPage extends ConsumerStatefulWidget {
  const BusinessOnboardingPage({super.key});

  @override
  ConsumerState<BusinessOnboardingPage> createState() =>
      _BusinessOnboardingPageState();
}

class _BusinessOnboardingPageState
    extends ConsumerState<BusinessOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _businessNameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final notifier = ref.read(onboardingProvider.notifier);
    notifier.updateFullName(_nameController.text);
    notifier.updateEmail(_emailController.text);
    notifier.updatePassword(_passwordController.text);
    notifier.updateConfirmPassword(_confirmController.text);
    notifier.updateBusinessName(_businessNameController.text);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await notifier.submit();
  }

  Future<void> _resendEmail() async {
    await ref.read(authSessionProvider.notifier).resendSignupConfirmation();
  }

  void _backToSignIn() {
    ref.read(authSessionProvider.notifier).clearEmailConfirmationWait();
    context.go(RoutePaths.login);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingProvider);
    final auth = ref.watch(authSessionProvider);
    final loading = draft.isBusy || auth.isAuthenticating || auth.isLoading;
    final awaitingEmail = auth.awaitingEmailConfirmation;

    final width = MediaQuery.sizeOf(context).width;
    final cardPadding = width < 360 ? AppSpacing.md : AppSpacing.lg;

    return Scaffold(
      body: AuthShellLayout(
        maxCardWidth: 480,
        cardPadding: EdgeInsets.all(cardPadding),
        child: awaitingEmail
            ? _EmailConfirmationSuccess(
                email: auth.pendingEmail ?? draft.email,
                loading: loading,
                infoMessage: auth.infoMessage,
                errorMessage: auth.errorMessage,
                onResend: _resendEmail,
                onBackToSignIn: _backToSignIn,
              )
            : _SignupForm(
                formKey: _formKey,
                nameController: _nameController,
                emailController: _emailController,
                passwordController: _passwordController,
                confirmController: _confirmController,
                businessNameController: _businessNameController,
                obscurePassword: _obscurePassword,
                obscureConfirm: _obscureConfirm,
                onTogglePassword: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
                onToggleConfirm: () => setState(
                  () => _obscureConfirm = !_obscureConfirm,
                ),
                loading: loading,
                fieldError: draft.fieldError,
                errorMessage: draft.errorMessage ?? auth.errorMessage,
                inviteRequired: draft.inviteRequired ||
                    SignupInvitePolicy.isInviteGateError(
                      draft.errorMessage ?? auth.errorMessage ?? '',
                    ),
                infoMessage: auth.requiresOnboarding ? auth.infoMessage : null,
                onNameChanged: (v) =>
                    ref.read(onboardingProvider.notifier).updateFullName(v),
                onEmailChanged: (v) =>
                    ref.read(onboardingProvider.notifier).updateEmail(v),
                onPasswordChanged: (v) =>
                    ref.read(onboardingProvider.notifier).updatePassword(v),
                onConfirmChanged: (v) => ref
                    .read(onboardingProvider.notifier)
                    .updateConfirmPassword(v),
                onBusinessNameChanged: (v) => ref
                    .read(onboardingProvider.notifier)
                    .updateBusinessName(v),
                onSubmit: loading ? null : _submit,
                onSignIn: loading ? null : _backToSignIn,
              ),
      ),
    );
  }
}

class _SignupForm extends StatelessWidget {
  const _SignupForm({
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmController,
    required this.businessNameController,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.loading,
    required this.fieldError,
    required this.errorMessage,
    required this.inviteRequired,
    required this.infoMessage,
    required this.onNameChanged,
    required this.onEmailChanged,
    required this.onPasswordChanged,
    required this.onConfirmChanged,
    required this.onBusinessNameChanged,
    required this.onSubmit,
    required this.onSignIn,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final TextEditingController businessNameController;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final bool loading;
  final String? fieldError;
  final String? errorMessage;
  final bool inviteRequired;
  final String? infoMessage;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onConfirmChanged;
  final ValueChanged<String> onBusinessNameChanged;
  final VoidCallback? onSubmit;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SelloBrandMark(size: 36),
          const SizedBox(height: AppSpacing.lg),
          Text('Create your account', style: context.texts.headlineLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Verify your email, then tell Sello about your business.',
            style: context.texts.bodyMedium?.copyWith(
              color: context.selloColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (infoMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _InfoBanner(message: infoMessage!),
          ],
          const SizedBox(height: AppSpacing.xl),
          SelloTextField(
            controller: nameController,
            label: 'Full name',
            required: true,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.person_outline_rounded,
            enabled: !loading,
            autofillHints: const [AutofillHints.name],
            onChanged: onNameChanged,
            validator: OnboardingValidation.ownerFullName,
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: emailController,
            label: 'Email',
            required: true,
            hint: 'you@company.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.mail_outline_rounded,
            enabled: !loading,
            autofillHints: const [AutofillHints.email],
            onChanged: onEmailChanged,
            validator: OnboardingValidation.ownerEmail,
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: passwordController,
            label: 'Password',
            required: true,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.lock_outline_rounded,
            enabled: !loading,
            autofillHints: const [AutofillHints.newPassword],
            suffixIcon: IconButton(
              onPressed: loading ? null : onTogglePassword,
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            onChanged: onPasswordChanged,
            validator: OnboardingValidation.password,
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: confirmController,
            label: 'Confirm password',
            required: true,
            obscureText: obscureConfirm,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.lock_outline_rounded,
            enabled: !loading,
            autofillHints: const [AutofillHints.newPassword],
            suffixIcon: IconButton(
              onPressed: loading ? null : onToggleConfirm,
              tooltip: obscureConfirm ? 'Show password' : 'Hide password',
              icon: Icon(
                obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            onChanged: onConfirmChanged,
            validator: (value) => OnboardingValidation.confirmPassword(
              value,
              passwordController.text,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: businessNameController,
            label: 'Business name',
            required: true,
            hint: 'Unitech Traders',
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.storefront_outlined,
            enabled: !loading,
            autofillHints: const [AutofillHints.organizationName],
            onChanged: onBusinessNameChanged,
            validator: OnboardingValidation.businessName,
          ),
          if (inviteRequired) ...[
            const SizedBox(height: AppSpacing.md),
            const _InviteOnlyNote(),
          ] else ...[
            if (fieldError != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorText(message: fieldError!),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorText(message: errorMessage!),
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          SelloButton(
            label: 'Create account',
            variant: SelloButtonVariant.primary,
            expanded: true,
            loading: loading,
            onPressed: onSubmit,
          ),
          const SizedBox(height: AppSpacing.sm),
          AuthTextLink(
            label: 'Already have an account? Sign in',
            onPressed: onSignIn,
          ),
        ],
      ),
    );
  }
}

class _EmailConfirmationSuccess extends StatelessWidget {
  const _EmailConfirmationSuccess({
    required this.email,
    required this.loading,
    required this.onResend,
    required this.onBackToSignIn,
    this.infoMessage,
    this.errorMessage,
  });

  final String email;
  final bool loading;
  final String? infoMessage;
  final String? errorMessage;
  final VoidCallback onResend;
  final VoidCallback onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SelloBrandMark(size: 36),
        const SizedBox(height: AppSpacing.xl),
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.successContainer,
            borderRadius: BorderRadius.circular(AppRadius.dialog),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: AppColors.success,
            size: 32,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Check your email',
          style: context.texts.headlineMedium,
          softWrap: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We sent a verification email to:',
          style: context.texts.bodyMedium?.copyWith(
            color: context.selloColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          email,
          style: context.texts.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Verify your email before signing in. After that, Sello creates '
          'your workspace and takes you through a short setup.',
          style: context.texts.bodyMedium?.copyWith(
            color: context.selloColors.textSecondary,
            height: 1.45,
          ),
        ),
        if (infoMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoBanner(message: infoMessage!),
        ],
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorText(message: errorMessage!),
        ],
        const SizedBox(height: AppSpacing.xl),
        SelloButton(
          label: 'Resend email',
          variant: SelloButtonVariant.primary,
          expanded: true,
          loading: loading,
          onPressed: loading ? null : onResend,
        ),
        const SizedBox(height: AppSpacing.sm),
        SelloButton(
          label: 'Back to sign in',
          variant: SelloButtonVariant.outline,
          expanded: true,
          onPressed: loading ? null : onBackToSignIn,
        ),
      ],
    );
  }
}

class _InviteOnlyNote extends StatelessWidget {
  const _InviteOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SignupInvitePolicy.title,
            style: context.texts.bodyMedium?.copyWith(
              color: AppColors.info,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            SignupInvitePolicy.support,
            style: context.texts.bodySmall?.copyWith(
              color: context.selloColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Text(
        message,
        style: context.texts.bodySmall?.copyWith(color: AppColors.info),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: context.texts.bodySmall?.copyWith(
        color: AppColors.error,
        height: 1.35,
      ),
    );
  }
}
