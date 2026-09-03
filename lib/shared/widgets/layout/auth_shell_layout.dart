import 'package:flutter/material.dart';
import 'package:sello/core/constants/app_constants.dart';
import 'package:sello/core/responsive/app_breakpoints.dart';
import 'package:sello/core/theme/theme.dart';

/// Full-screen purple auth canvas with optional marketing panel and a floating
/// form card — sign-in, sign-up, and similar pre-workspace surfaces.
class AuthShellLayout extends StatelessWidget {
  const AuthShellLayout({
    super.key,
    required this.child,
    this.maxCardWidth = 420,
    this.cardPadding,
  });

  final Widget child;
  final double maxCardWidth;
  final EdgeInsetsGeometry? cardPadding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.authCanvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= AppBreakpoints.mobile;
            final horizontalGutter = wide ? AppSpacing.xl : AppSpacing.lg;
            final verticalGutter = wide ? AppSpacing.xxl : AppSpacing.xl;

            if (wide) {
              return Row(
                children: [
                  const Expanded(child: AuthMarketingPanel()),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalGutter,
                          vertical: verticalGutter,
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxCardWidth,
                            minHeight: 580,
                          ),
                          child: AuthFormCard(
                            padding: cardPadding,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalGutter,
                  vertical: verticalGutter,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxCardWidth),
                  child: AuthFormCard(
                    padding: cardPadding,
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Left marketing column — headline and hero illustration on the auth canvas.
class AuthMarketingPanel extends StatelessWidget {
  const AuthMarketingPanel({super.key});

  static const assetPath = 'assets/brand/auth_hero.jpg';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Baseline 1.28 + 12% for the NAMSON hero. Do not wrap the image in
        // Flexible — that competes with Spacers and shrinks the art.
        const heroScale = 1.28 * 1.12;
        final imageMaxWidth = constraints.maxWidth * 0.88 * heroScale;
        var imageMaxHeight = constraints.maxHeight * 0.44 * heroScale;
        final leftInset = constraints.maxWidth * 0.12;
        const textBlockHeight = 3 * 36 * 1.1 + 3 * AppSpacing.xs + AppSpacing.md;
        final roomForImage = constraints.maxHeight -
            AppSpacing.lg * 2 -
            textBlockHeight;
        if (roomForImage > 80 && imageMaxHeight > roomForImage) {
          imageMaxHeight = roomForImage;
        }

        return Padding(
          padding: EdgeInsets.only(
            left: leftInset < 72 ? 72 : leftInset,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in AppConstants.authHeroLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(
                          line,
                          style: context.texts.headlineLarge?.copyWith(
                            fontSize: 36,
                            fontWeight: FontWeight.w500,
                            height: 1.1,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: imageMaxWidth,
                    maxHeight: imageMaxHeight,
                  ),
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        );
      },
    );
  }
}

/// Floating white card for auth forms — not full-height or full-width.
class AuthFormCard extends StatelessWidget {
  const AuthFormCard({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        boxShadow: AppShadows.level3,
      ),
      child: Padding(
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: 56,
            ),
        child: child,
      ),
    );
  }
}

/// Regular-weight text link for auth footers — forgot password, create account, sign in.
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  static ButtonStyle buttonStyle(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: context.brandAccent,
      textStyle: context.texts.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: buttonStyle(context),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
