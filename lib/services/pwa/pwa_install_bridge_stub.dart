import 'dart:async';

import 'package:sello/services/pwa/pwa_install_policy.dart';

/// Non-web stub — PWA install is web-only.
abstract final class PwaInstallBridge {
  static bool get isWeb => false;

  static bool get isStandalone => false;

  static bool get canPrompt => false;

  static bool get isInstallUiEligible => false;

  static bool get isAppleMobile => false;

  static Future<PwaInstallPromptResult> promptInstall() async =>
      PwaInstallPromptResult.unavailable;

  static Stream<void> get onInstallable => const Stream.empty();

  static Stream<void> get onInstalled => const Stream.empty();
}
