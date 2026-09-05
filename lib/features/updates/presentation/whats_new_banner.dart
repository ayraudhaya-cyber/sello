import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/updates/release_notes_formatter.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Compact, non-blocking “What’s new” card for Web / PWA optional updates.
class WhatsNewBanner extends StatefulWidget {
  const WhatsNewBanner({
    super.key,
    required this.snapshot,
    required this.onDismiss,
  });

  final UpdateCheckSnapshot snapshot;
  final VoidCallback onDismiss;

  @override
  State<WhatsNewBanner> createState() => _WhatsNewBannerState();
}

class _WhatsNewBannerState extends State<WhatsNewBanner> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final version = widget.snapshot.latest?.versionName ??
        widget.snapshot.installed.versionName;
    final bullets = ReleaseNotesFormatter.bullets(widget.snapshot.notes);
    final isMobile = context.isMobile;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Sello $version. What’s new.',
        child: Focus(
          autofocus: false,
          child: SelloCard(
            enableHoverLift: false,
            elevation: SelloCardElevation.soft,
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              8,
              _expanded ? 14 : 12,
            ),
            borderRadius: AppRadius.panelAll,
            borderColor: AppColors.outlinePanel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _expanded = !_expanded),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2, right: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sello $version',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.15,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _expanded ? 'What’s new' : 'What’s new — tap to expand',
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: widget.onDismiss,
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
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  if (bullets.isEmpty)
                    const Text(
                      'Sello has been updated with the latest improvements.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    )
                  else
                    for (final line in bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '•  ',
                              style: TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 13,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13,
                                  height: 1.4,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelloButton(
                      label: 'Got it',
                      variant: SelloButtonVariant.ghost,
                      size: SelloButtonSize.small,
                      onPressed: widget.onDismiss,
                    ),
                  ),
                ],
                if (isMobile && !_expanded) const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Optional Shortcuts wrapper for Escape-to-dismiss on web.
class WhatsNewShortcuts extends StatelessWidget {
  const WhatsNewShortcuts({
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
