import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/updates/presentation/update_prompt.dart';
import 'package:sello/features/updates/presentation/whats_new_banner.dart';
import 'package:sello/services/updates/release_manifest_config.dart';
import 'package:sello/services/updates/update_presentation_policy.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Root overlay for startup update checks. Failures never block the app.
///
/// Optional updates use [UpdatePresentationPolicy]: Web/PWA gets a lightweight
/// What’s New banner; Android / iOS / desktop keep the Update Available modal.
/// Required updates stay blocking on every platform.
class UpdateCheckHost extends ConsumerStatefulWidget {
  const UpdateCheckHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends ConsumerState<UpdateCheckHost> {
  var _optionalVisible = false;
  String? _promptedIdentity;

  UpdatePresentationStyle get _optionalStyle =>
      UpdatePresentationPolicy.forPlatform(
        ReleaseManifestConfig.currentPlatform,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(updateCheckControllerProvider);
    final snapshot = async.valueOrNull;
    final isMobile = context.isMobile;

    ref.listen<AsyncValue<UpdateCheckSnapshot>>(
      updateCheckControllerProvider,
      (previous, next) {
        final data = next.valueOrNull;
        if (data == null) return;
        _maybeShowOptional(data);
      },
    );

    final showOptional = _optionalVisible &&
        snapshot?.status == UpdateCheckStatus.updateAvailable;
    final useWhatsNew =
        showOptional && _optionalStyle == UpdatePresentationStyle.whatsNew;
    final useModal =
        showOptional && _optionalStyle == UpdatePresentationStyle.updateModal;

    return Stack(
      children: [
        widget.child,
        if (snapshot?.status == UpdateCheckStatus.updateRequired)
          Positioned.fill(
            child: RequiredUpdatePage(
              snapshot: snapshot!,
              onUpdate: () => _openDestination(snapshot),
            ),
          )
        else if (useModal)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.textPrimary.withValues(alpha: 0.28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: OptionalUpdatePrompt(
                      snapshot: snapshot!,
                      onLater: _postpone,
                      onUpdate: () => _openDestination(snapshot),
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (useWhatsNew)
          Positioned(
            right: isMobile ? 16 : 24,
            left: isMobile ? 16 : null,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isMobile ? double.infinity : 360,
                ),
                child: WhatsNewShortcuts(
                  onDismiss: _postpone,
                  child: WhatsNewBanner(
                    snapshot: snapshot!,
                    onDismiss: _postpone,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _maybeShowOptional(UpdateCheckSnapshot snapshot) async {
    if (snapshot.status != UpdateCheckStatus.updateAvailable) return;
    if (_promptedIdentity == snapshot.latest?.identity && _optionalVisible) {
      return;
    }
    final controller = ref.read(updateCheckControllerProvider.notifier);
    final force = controller.promptEvenIfPostponed;
    controller.promptEvenIfPostponed = false;
    if (!force) {
      if (_promptedIdentity == snapshot.latest?.identity) return;
      final postponed = await controller.isPostponed(snapshot);
      if (!mounted || postponed) return;
    }
    if (!mounted) return;
    setState(() {
      _optionalVisible = true;
      _promptedIdentity = snapshot.latest?.identity;
    });
  }

  Future<void> _postpone() async {
    await ref.read(updateCheckControllerProvider.notifier).postpone();
    if (!mounted) return;
    setState(() => _optionalVisible = false);
  }

  Future<void> _openDestination(UpdateCheckSnapshot snapshot) async {
    final url = snapshot.channel?.destinationUrl?.trim();
    if (url == null || url.isEmpty) {
      SelloSnackbars.info(
        context,
        'The update destination is not configured yet.',
      );
      return;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      SelloSnackbars.info(
        context,
        'The update destination is not configured yet.',
      );
      return;
    }
    final ok = await launchUrl(parsed, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      SelloSnackbars.info(
        context,
        'Unable to open the update destination.',
      );
    }
  }
}
