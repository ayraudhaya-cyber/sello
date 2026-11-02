import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/services/updates/bundled_release_notes.dart';
import 'package:sello/services/updates/release_notes_formatter.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Opens the notes for the version installed on this device.
Future<void> showWhatsNewDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const WhatsNewDialog(),
  );
}

class WhatsNewDialog extends ConsumerStatefulWidget {
  const WhatsNewDialog({super.key});

  @override
  ConsumerState<WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends ConsumerState<WhatsNewDialog> {
  var _loading = true;
  String? _versionLabel;
  List<String> _bullets = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final installed = await ref.read(installedAppVersionProvider.future);
    final app = ref.read(releaseAppKindProvider);
    final notes = app == null
        ? null
        : await BundledReleaseNotes.forInstalled(
            installed: installed,
            app: app,
          );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _versionLabel = installed.versionName;
      _bullets = ReleaseNotesFormatter.bullets(notes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = _versionLabel;
    return SelloFormDialog(
      title: 'What’s new',
      subtitle: version == null
          ? 'Changes included in this Sello installation.'
          : 'In Sello $version on this device.',
      maxWidth: 520,
      fullscreenOnMobile: true,
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : _bullets.isEmpty
          ? const Text(
              'This version does not include a written What’s new list. '
              'Sello is still updated with improvements for your business.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in _bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 14,
                              height: 1.4,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      footer: SelloDialogFooter(
        cancelLabel: 'Close',
        primaryLabel: 'Done',
        onPrimary: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
