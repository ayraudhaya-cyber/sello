/// Pure PWA install presentation decisions (testable without a browser).
enum PwaInstallMode {
  /// Already running as an installed app — hide the install surface.
  hidden,

  /// Browser exposed `beforeinstallprompt` (typically Android Chrome/Edge).
  promptAvailable,

  /// iOS / iPadOS Safari (and other Apple mobile browsers) — manual A2HS tip.
  iosManual,

  /// Web but neither prompt nor Apple-mobile tip applies — hide for V1.
  unsupported,
}

/// Resolves which install UI to show for Sales mobile web.
abstract final class PwaInstallPolicy {
  static PwaInstallMode resolve({
    required bool isWeb,
    required bool isStandalone,
    required bool canPrompt,
    required bool isAppleMobile,
    bool installUiEligible = false,
  }) {
    if (!isWeb) return PwaInstallMode.hidden;
    if (isStandalone) return PwaInstallMode.hidden;
    // Apple mobile never supports programmatic install — never show Android CTA.
    if (isAppleMobile) return PwaInstallMode.iosManual;
    // Keep the card after a cancelled prompt (eligible) or when prompt is ready.
    if (canPrompt || installUiEligible) return PwaInstallMode.promptAvailable;
    return PwaInstallMode.unsupported;
  }

  /// Short body line under the title.
  static String descriptionFor(PwaInstallMode mode) {
    return switch (mode) {
      PwaInstallMode.iosManual =>
        'Add Sello to your Home Screen for faster field access.',
      PwaInstallMode.promptAvailable =>
        'Add Sello to your Home Screen for quicker visits and orders.',
      PwaInstallMode.hidden || PwaInstallMode.unsupported => '',
    };
  }

  /// iOS-only step line (never used for Android prompt mode).
  static String? iosStepsFor(PwaInstallMode mode) {
    if (mode != PwaInstallMode.iosManual) return null;
    return 'Tap Share → Add to Home Screen';
  }
}

enum PwaInstallPromptResult {
  accepted,
  dismissed,
  unavailable,
}
