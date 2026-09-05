import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/updates/release_notes_formatter.dart';
import 'package:sello/services/updates/update_presentation_policy.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

void main() {
  group('UpdatePresentationPolicy', () {
    test('web / PWA uses What’s New notification', () {
      expect(
        UpdatePresentationPolicy.forPlatform(AppReleasePlatform.web),
        UpdatePresentationStyle.whatsNew,
      );
    });

    test('Android keeps Update Available modal', () {
      expect(
        UpdatePresentationPolicy.forPlatform(AppReleasePlatform.android),
        UpdatePresentationStyle.updateModal,
      );
    });

    test('iOS keeps Update Available modal', () {
      expect(
        UpdatePresentationPolicy.forPlatform(AppReleasePlatform.ios),
        UpdatePresentationStyle.updateModal,
      );
    });

    test('desktop / Electron (other) keeps Update Available modal', () {
      expect(
        UpdatePresentationPolicy.forPlatform(AppReleasePlatform.other),
        UpdatePresentationStyle.updateModal,
      );
    });
  });

  group('ReleaseNotesFormatter', () {
    test('splits newline notes into bullets', () {
      expect(
        ReleaseNotesFormatter.bullets(
          'Improved invoice & receipt layout\n'
          'Cleaner order details\n'
          'Better PWA experience',
        ),
        [
          'Improved invoice & receipt layout',
          'Cleaner order details',
          'Better PWA experience',
        ],
      );
    });

    test('strips existing bullet markers', () {
      expect(
        ReleaseNotesFormatter.bullets('• One\n- Two\n* Three'),
        ['One', 'Two', 'Three'],
      );
    });

    test('splits semicolon-separated notes', () {
      expect(
        ReleaseNotesFormatter.bullets('Alpha; Beta; Gamma'),
        ['Alpha', 'Beta', 'Gamma'],
      );
    });

    test('empty notes yield no bullets', () {
      expect(ReleaseNotesFormatter.bullets(null), isEmpty);
      expect(ReleaseNotesFormatter.bullets('   '), isEmpty);
    });
  });
}
