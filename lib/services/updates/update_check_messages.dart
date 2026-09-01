import 'package:sello/shared/models/sello_release_manifest.dart';

/// Owner-facing copy for manual update checks. Keep distinct from the prompt.
abstract final class UpdateCheckMessages {
  static String manualResult(UpdateCheckSnapshot snapshot) {
    return switch (snapshot.status) {
      UpdateCheckStatus.upToDate => "You're on the latest version.",
      UpdateCheckStatus.updateAvailable => 'A newer version of Sello is ready.',
      UpdateCheckStatus.updateRequired => 'Please update Sello to continue.',
      UpdateCheckStatus.checkFailed => failed(snapshot),
    };
  }

  static String failed(UpdateCheckSnapshot snapshot) {
    final reason = (snapshot.failureReason ?? '').toLowerCase();
    if (reason.contains('not configured')) {
      return 'Update checking isn’t set up for this install yet. '
          'You can keep using Sello.';
    }
    if (reason.contains('unable to reach') ||
        reason.contains('returned') ||
        reason.contains('invalid')) {
      return 'Couldn’t reach the update server. You can keep using Sello.';
    }
    return 'Couldn’t check for updates right now. You can keep using Sello.';
  }
}
