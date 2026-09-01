import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/updates/presentation/update_prompt.dart';
import 'package:sello/services/updates/update_providers.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Root overlay for startup update checks. Failures never block the app.
class UpdateCheckHost extends ConsumerStatefulWidget {
  const UpdateCheckHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends ConsumerState<UpdateCheckHost> {
  var _optionalVisible = false;
  String? _promptedIdentity;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(updateCheckControllerProvider);
    final snapshot = async.valueOrNull;

    ref.listen<AsyncValue<UpdateCheckSnapshot>>(
      updateCheckControllerProvider,
      (previous, next) {
        final data = next.valueOrNull;
        if (data == null) return;
        _maybeShowOptional(data);
      },
    );

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
        else if (_optionalVisible &&
            snapshot?.status == UpdateCheckStatus.updateAvailable)
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
