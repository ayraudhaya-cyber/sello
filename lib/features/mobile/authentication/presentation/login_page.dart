import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/constants/app_assets.dart';
import 'package:sello/core/constants/app_constants.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/user_role.dart';
import 'package:sello/shared/widgets/widgets.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'owner@sello.app');
  final _passwordController = TextEditingController(text: 'password');
  UserRole _role = UserRole.owner;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authSessionProvider.notifier).signInStub(
          email: _emailController.text,
          password: _passwordController.text,
          role: _role,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);

    return Scaffold(
      body: ResponsiveBuilder(
        mobile: (_) => _MobileLogin(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          role: _role,
          onRoleChanged: (r) => setState(() => _role = r),
          loading: auth.isLoading,
          errorMessage: auth.errorMessage,
          onSubmit: _submit,
        ),
        tablet: (_) => _SplitLogin(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          role: _role,
          onRoleChanged: (r) => setState(() => _role = r),
          loading: auth.isLoading,
          errorMessage: auth.errorMessage,
          onSubmit: _submit,
        ),
        desktop: (_) => _SplitLogin(
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          obscure: _obscure,
          onToggleObscure: () => setState(() => _obscure = !_obscure),
          role: _role,
          onRoleChanged: (r) => setState(() => _role = r),
          loading: auth.isLoading,
          errorMessage: auth.errorMessage,
          onSubmit: _submit,
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
    required this.obscure,
    required this.onToggleObscure,
    required this.role,
    required this.onRoleChanged,
    required this.loading,
    required this.errorMessage,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final UserRole role;
  final ValueChanged<UserRole> onRoleChanged;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SelloBrandMark(size: 40),
          const SizedBox(height: AppSpacing.xl),
          Text('Welcome back', style: context.texts.headlineLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sign in to continue to ${AppConstants.appName}',
            style: context.texts.bodyMedium?.copyWith(
              color: context.selloColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SelloTextField(
            controller: emailController,
            label: 'Email',
            hint: 'you@company.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.mail_outline_rounded,
            autofillHints: const [AutofillHints.email],
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Email is required' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          SelloTextField(
            controller: passwordController,
            label: 'Password',
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.lock_outline_rounded,
            autofillHints: const [AutofillHints.password],
            suffixIcon: IconButton(
              onPressed: onToggleObscure,
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Password is required' : null,
            onChanged: (_) {},
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Foundation preview role',
            style: context.texts.labelMedium?.copyWith(
              color: context.selloColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final r in UserRole.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: role == r,
                  onSelected: (_) => onRoleChanged(r),
                ),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              errorMessage!,
              style: context.texts.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SelloButton(
            label: 'Sign in',
            variant: SelloButtonVariant.gradient,
            expanded: true,
            loading: loading,
            onPressed: onSubmit,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Stub authentication for foundation only. '
            'Supabase Auth will replace this in Phase 2.',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(
              color: context.selloColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileLogin extends StatelessWidget {
  const _MobileLogin({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscure,
    required this.onToggleObscure,
    required this.role,
    required this.onRoleChanged,
    required this.loading,
    required this.errorMessage,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final UserRole role;
  final ValueChanged<UserRole> onRoleChanged;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onSubmit;

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
                obscure: obscure,
                onToggleObscure: onToggleObscure,
                role: role,
                onRoleChanged: onRoleChanged,
                loading: loading,
                errorMessage: errorMessage,
                onSubmit: onSubmit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplitLogin extends StatelessWidget {
  const _SplitLogin({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscure,
    required this.onToggleObscure,
    required this.role,
    required this.onRoleChanged,
    required this.loading,
    required this.errorMessage,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final UserRole role;
  final ValueChanged<UserRole> onRoleChanged;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: const BoxDecoration(gradient: AppGradients.primary),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppShadows.level2,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      AppAssets.logo,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    AppConstants.appName,
                    style: context.texts.displayMedium?.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppConstants.appTagline,
                    style: context.texts.titleMedium?.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'One platform for field sales and business operations.',
                    style: context.texts.bodyLarge?.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.85),
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
                  obscure: obscure,
                  onToggleObscure: onToggleObscure,
                  role: role,
                  onRoleChanged: onRoleChanged,
                  loading: loading,
                  errorMessage: errorMessage,
                  onSubmit: onSubmit,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
