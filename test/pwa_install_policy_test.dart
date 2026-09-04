import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/pwa/pwa_install_policy.dart';

void main() {
  group('PwaInstallPolicy', () {
    test('hides on non-web platforms', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: false,
          isStandalone: false,
          canPrompt: true,
          isAppleMobile: true,
        ),
        PwaInstallMode.hidden,
      );
    });

    test('hides when already running as installed PWA', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: true,
          isStandalone: true,
          canPrompt: true,
          isAppleMobile: true,
          installUiEligible: true,
        ),
        PwaInstallMode.hidden,
      );
    });

    test('shows install prompt on Android-capable browsers', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: true,
          isStandalone: false,
          canPrompt: true,
          isAppleMobile: false,
        ),
        PwaInstallMode.promptAvailable,
      );
    });

    test('keeps Android card after cancelled prompt via installUiEligible', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: true,
          isStandalone: false,
          canPrompt: false,
          isAppleMobile: false,
          installUiEligible: true,
        ),
        PwaInstallMode.promptAvailable,
      );
    });

    test('shows iOS manual tip without beforeinstallprompt', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: true,
          isStandalone: false,
          canPrompt: false,
          isAppleMobile: true,
        ),
        PwaInstallMode.iosManual,
      );
    });

    test('never shows Android prompt CTA on Apple mobile', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: true,
          isStandalone: false,
          canPrompt: true,
          isAppleMobile: true,
          installUiEligible: true,
        ),
        PwaInstallMode.iosManual,
      );
      expect(
        PwaInstallPolicy.iosStepsFor(PwaInstallMode.iosManual),
        'Tap Share → Add to Home Screen',
      );
      expect(
        PwaInstallPolicy.iosStepsFor(PwaInstallMode.promptAvailable),
        isNull,
      );
    });

    test('hides when browser has no install path', () {
      expect(
        PwaInstallPolicy.resolve(
          isWeb: true,
          isStandalone: false,
          canPrompt: false,
          isAppleMobile: false,
          installUiEligible: false,
        ),
        PwaInstallMode.unsupported,
      );
    });

    test('copy is platform-specific', () {
      expect(
        PwaInstallPolicy.descriptionFor(PwaInstallMode.iosManual),
        contains('Home Screen'),
      );
      expect(
        PwaInstallPolicy.descriptionFor(PwaInstallMode.promptAvailable),
        contains('Home Screen'),
      );
      expect(
        PwaInstallPolicy.iosStepsFor(PwaInstallMode.iosManual),
        'Tap Share → Add to Home Screen',
      );
    });
  });
}
