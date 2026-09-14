import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/updates/release_highlights_presenter.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Bottom-right “Sello updated” card after a new build is installed.
class AppUpdatedCard extends StatelessWidget {
  const AppUpdatedCard({
    super.key,
    required this.versionLabel,
    required this.notes,
    required this.onDismiss,
  });

  final String versionLabel;
  final String? notes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final highlights = ReleaseHighlightsPresenter.lines(notes);

    return Material(
      color: Colors.transparent,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Sello updated. What’s new.',
        child: SelloCard(
          enableHoverLift: false,
          elevation: SelloCardElevation.soft,
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          borderRadius: AppRadius.panelAll,
          borderColor: AppColors.outlinePanel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.brandAccentContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '✨',
                      style: const TextStyle(fontSize: 18, height: 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sello updated',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Version $versionLabel · thanks for your feedback',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                      hoverColor: AppColors.veil,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Here’s what’s new:',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              for (final line in highlights.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Row(
                          children: [
                            Text(
                              line.emoji,
                              style: const TextStyle(fontSize: 15, height: 1.25),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              line.icon,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line.text,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13.5,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: SelloButton(
                  label: 'Nice!',
                  icon: Icons.favorite_border_rounded,
                  variant: SelloButtonVariant.ghost,
                  size: SelloButtonSize.small,
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Escape dismisses the updated card on desktop/web.
class AppUpdatedShortcuts extends StatelessWidget {
  const AppUpdatedShortcuts({
    super.key,
    required this.onDismiss,
    required this.child,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: {
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) {
              onDismiss();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}
