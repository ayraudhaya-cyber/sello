import 'package:sello/shared/models/sello_release_manifest.dart';

/// How optional updates are presented. Detection stays in [UpdatePolicy].
enum UpdatePresentationStyle {
  /// Lightweight, dismissible “What’s new” surface (Web / PWA).
  whatsNew,

  /// Existing “New version available” modal (Android, iOS, desktop / Electron).
  updateModal,
}

/// Maps release platforms to optional-update presentation.
///
/// Required updates ([UpdateCheckStatus.updateRequired]) remain blocking on
/// every platform and are not routed through this policy.
abstract final class UpdatePresentationPolicy {
  static UpdatePresentationStyle forPlatform(AppReleasePlatform platform) {
    return switch (platform) {
      AppReleasePlatform.web => UpdatePresentationStyle.whatsNew,
      AppReleasePlatform.android ||
      AppReleasePlatform.ios ||
      AppReleasePlatform.other =>
        UpdatePresentationStyle.updateModal,
    };
  }
}
