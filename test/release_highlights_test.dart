import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/updates/release_highlights_presenter.dart';
import 'package:sello/services/updates/release_highlights_store.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReleaseHighlightsPresenter', () {
    test('maps notes to friendly emoji lines', () {
      final lines = ReleaseHighlightsPresenter.lines(
        'Change your password from Account\n'
        'Cheque later is clearer\n'
        'Orders support discounts',
      );
      expect(lines, hasLength(3));
      expect(lines[0].emoji, '🔐');
      expect(lines[1].emoji, '🏦');
      expect(lines[2].emoji, '🧾');
      expect(lines[0].icon, Icons.lock_outline_rounded);
    });

    test('uses soft fallback when notes are empty', () {
      final lines = ReleaseHighlightsPresenter.lines(null);
      expect(lines, isNotEmpty);
      expect(lines.first.emoji, '✨');
    });
  });

  group('ReleaseHighlightsStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('first launch remembers quietly without showing', () async {
      final store = ReleaseHighlightsStore(appKey: 'owner_manager');
      final shown = await store.shouldShowHighlights(
        const AppVersion(major: 1, minor: 0, patch: 4, build: 5),
      );
      expect(shown, isFalse);
      expect(await store.seenVersionIdentity(), '1.0.4+5');
    });

    test('shows when installed version changes', () async {
      final store = ReleaseHighlightsStore(appKey: 'owner_manager');
      await store.markSeen(
        installed: const AppVersion(major: 1, minor: 0, patch: 4, build: 5),
      );
      final shown = await store.shouldShowHighlights(
        const AppVersion(major: 1, minor: 0, patch: 5, build: 6),
      );
      expect(shown, isTrue);
    });

    test('does not show again for the same version', () async {
      final store = ReleaseHighlightsStore(appKey: 'owner_manager');
      await store.markSeen(
        installed: const AppVersion(major: 1, minor: 0, patch: 5, build: 6),
      );
      final shown = await store.shouldShowHighlights(
        const AppVersion(major: 1, minor: 0, patch: 5, build: 6),
      );
      expect(shown, isFalse);
    });
  });
}
