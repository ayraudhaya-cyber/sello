import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/pwa/pwa_install_policy.dart';
import 'package:sello/services/pwa/pwa_install_provider.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Compact Sales-only PWA install surface for mobile web (Android + iOS).
class SelloPwaInstallCard extends ConsumerWidget {
  const SelloPwaInstallCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final install = ref.watch(pwaInstallProvider);
    if (!install.shouldShow) return const SizedBox.shrink();

    final colors = context.selloColors;
    final isIos = install.mode == PwaInstallMode.iosManual;
    final description = PwaInstallPolicy.descriptionFor(install.mode);
    final iosSteps = PwaInstallPolicy.iosStepsFor(install.mode);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.gap),
      child: SelloCard(
        enableHoverLift: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.brandAccentContainer,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Icon(
                isIos ? Icons.ios_share_rounded : Icons.add_to_home_screen_rounded,
                color: context.brandAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Install Sello',
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: context.texts.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (iosSteps != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.brandAccentContainer.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      child: Text(
                        iosSteps,
                        style: context.texts.labelLarge?.copyWith(
                          color: context.brandAccent,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                  if (install.mode == PwaInstallMode.promptAvailable) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelloButton(
                        label: install.isPrompting
                            ? 'Installing…'
                            : 'Install Sello',
                        icon: Icons.download_rounded,
                        size: SelloButtonSize.small,
                        loading: install.isPrompting,
                        onPressed: install.isPrompting
                            ? null
                            : () => _onInstall(context, ref),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onInstall(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(pwaInstallProvider.notifier).install();
    if (!context.mounted) return;
    switch (result) {
      case PwaInstallPromptResult.accepted:
        SelloSnackbars.success(context, 'Sello is ready on your Home Screen.');
      case PwaInstallPromptResult.dismissed:
        // Card stays visible via installUiEligible; browser may re-offer promptly.
        break;
      case PwaInstallPromptResult.unavailable:
        SelloSnackbars.info(
          context,
          'Install isn’t ready yet. Try again in a moment, or use the browser menu → Install app.',
        );
    }
  }
}
