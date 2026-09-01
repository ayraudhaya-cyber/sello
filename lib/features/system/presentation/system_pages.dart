import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/widgets/branding/branded_logo.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';

/// Cold-start splash while session bootstrap runs.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider);
    final branded =
        branding.hasCustomLogo || branding.hasCustomNavBackground;

    if (!branded) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: BrandedLaunchLockup(showProgress: true),
        ),
      );
    }

    return const Scaffold(
      body: BrandedDarkSurface(
        expand: true,
        child: Center(
          child: BrandedLaunchLockup(
            showProgress: true,
            lightOnDark: true,
            clientLogoSize: 64,
          ),
        ),
      ),
    );
  }
}

class AppLoadingPage extends StatelessWidget {
  const AppLoadingPage({
    super.key,
    this.message = 'Loading…',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: context.texts.titleMedium),
          ],
        ),
      ),
    );
  }
}

class AppErrorPage extends StatelessWidget {
  const AppErrorPage({
    super.key,
    this.title = 'Something went wrong',
    this.message =
        'An unexpected error occurred. You can retry or return home.',
    this.onRetry,
    this.onHome,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: AppRadius.cardAll,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: 32,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: context.texts.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.selloColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  children: [
                    if (onHome != null)
                      SelloButton(
                        label: 'Go home',
                        variant: SelloButtonVariant.outline,
                        onPressed: onHome,
                      ),
                    if (onRetry != null)
                      SelloButton(
                        label: 'Retry',
                        variant: SelloButtonVariant.primary,
                        onPressed: onRetry,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '404',
                  style: context.texts.displayMedium?.copyWith(
                    color: context.brandAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Page not found', style: context.texts.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'This route does not exist or you do not have access.',
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.selloColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SelloButton(
                  label: 'Back to app',
                  variant: SelloButtonVariant.primary,
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
