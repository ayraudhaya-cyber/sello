import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Optional update card — dismissible. Used as a host overlay, not a route.
class OptionalUpdatePrompt extends StatefulWidget {
  const OptionalUpdatePrompt({
    super.key,
    required this.snapshot,
    required this.onLater,
    required this.onUpdate,
  });

  final UpdateCheckSnapshot snapshot;
  final VoidCallback onLater;
  final VoidCallback onUpdate;

  @override
  State<OptionalUpdatePrompt> createState() => _OptionalUpdatePromptState();
}

class _OptionalUpdatePromptState extends State<OptionalUpdatePrompt> {
  var _showNotes = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final notes = snapshot.notes;
    final released = snapshot.releasedAt;

    return SelloCard(
      enableHoverLift: false,
      elevation: SelloCardElevation.soft,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      borderRadius: AppRadius.dialogAll,
      borderColor: AppColors.outlinePanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SelloIconBadge(
                icon: Icons.system_update_alt_rounded,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'New version available',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'A newer version of Sello is ready.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Version ${snapshot.latest?.versionName ?? '—'}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (released != null) ...[
            const SizedBox(height: 2),
            Text(
              SelloFormatters.date(released),
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (notes != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SelloButton(
                label: _showNotes ? 'Hide what’s new' : 'View what’s new',
                variant: SelloButtonVariant.ghost,
                size: SelloButtonSize.small,
                onPressed: () => setState(() => _showNotes = !_showNotes),
              ),
            ),
            if (_showNotes) ...[
              const SizedBox(height: 8),
              Text(
                notes,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              SelloButton(
                label: 'Later',
                variant: SelloButtonVariant.ghost,
                onPressed: widget.onLater,
              ),
              const Spacer(),
              SelloButton(
                label: 'Update',
                onPressed: widget.onUpdate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Blocking required-update surface. No path back into the app.
class RequiredUpdatePage extends StatelessWidget {
  const RequiredUpdatePage({
    super.key,
    required this.snapshot,
    required this.onUpdate,
  });

  final UpdateCheckSnapshot snapshot;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final notes = snapshot.notes;

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelloCard(
                enableHoverLift: false,
                elevation: SelloCardElevation.soft,
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                borderRadius: AppRadius.dialogAll,
                borderColor: AppColors.outlinePanel,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SelloIconBadge(
                      icon: Icons.lock_outline_rounded,
                      size: 40,
                      iconSize: 20,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Update required',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This version of Sello is no longer supported. '
                      'Please update to continue.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MetaLine(
                      label: 'Installed',
                      value: snapshot.installed.versionName,
                    ),
                    _MetaLine(
                      label: 'Required',
                      value: snapshot.minimum?.versionName ??
                          snapshot.latest?.versionName ??
                          '—',
                    ),
                    if (notes != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        notes,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SelloButton(
                      label: 'Update',
                      expanded: true,
                      onPressed: onUpdate,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
