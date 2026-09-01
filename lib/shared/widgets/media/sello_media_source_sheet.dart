import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/media/media_service.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';

/// Platform-aware media source chooser for mobile surfaces.
///
/// Desktop callers should open the file picker directly and skip this sheet.
abstract final class SelloMediaSourceSheet {
  static Future<MediaSourceKind?> show(BuildContext context) {
    if (MediaService.useMobilePicker(context)) {
      return showModalBottomSheet<MediaSourceKind>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.bottomSheetAll,
        ),
        builder: (context) => const _MobileSourceSheet(),
      );
    }

    return showDialog<MediaSourceKind>(
      context: context,
      builder: (context) => const _DesktopSourceDialog(),
    );
  }
}

class _MobileSourceSheet extends StatelessWidget {
  const _MobileSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineStrong,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add Photos',
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: 6),
            const Text(
              'Up to 3 photos per product',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textFaint,
              ),
            ),
            const SizedBox(height: 18),
            _SourceTile(
              icon: Icons.photo_camera_outlined,
              label: 'Take Photo',
              onTap: () => Navigator.pop(context, MediaSourceKind.camera),
            ),
            const SizedBox(height: 8),
            _SourceTile(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Gallery',
              onTap: () => Navigator.pop(context, MediaSourceKind.gallery),
            ),
            const SizedBox(height: 12),
            SelloButton(
              label: 'Cancel',
              variant: SelloButtonVariant.ghost,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSourceDialog extends StatelessWidget {
  const _DesktopSourceDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Photos'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SourceTile(
              icon: Icons.folder_open_outlined,
              label: 'Browse Files',
              onTap: () => Navigator.pop(context, MediaSourceKind.files),
            ),
            if (MediaService.cameraLikelyAvailable) ...[
              const SizedBox(height: 8),
              _SourceTile(
                icon: Icons.photo_camera_outlined,
                label: 'Use Camera',
                onTap: () => Navigator.pop(context, MediaSourceKind.camera),
              ),
            ],
          ],
        ),
      ),
      actions: [
        SelloButton(
          label: 'Cancel',
          variant: SelloButtonVariant.outline,
          size: SelloButtonSize.small,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.controlAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: context.brandAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
