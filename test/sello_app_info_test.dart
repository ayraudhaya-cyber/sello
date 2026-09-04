import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/widgets/feedback/sello_app_info_panel.dart';

void main() {
  group('formatInstalledVersionLine', () {
    test('formats version and build from AppVersion', () {
      const version = AppVersion(major: 1, minor: 0, patch: 3, build: 4);
      expect(
        formatInstalledVersionLine(version),
        'Sello 1.0.3 (build 4)',
      );
    });

    test('appends revision when provided', () {
      const version = AppVersion(major: 1, minor: 0, patch: 3, build: 4);
      expect(
        formatInstalledVersionLine(version, revision: 'abc1234'),
        'Sello 1.0.3 (build 4) · abc1234',
      );
    });
  });

  group('AppVersion from pubspec-style strings', () {
    test('fromNameAndBuild matches pubspec version+build', () {
      final version = AppVersion.fromNameAndBuild('1.0.3', '4');
      expect(version.versionName, '1.0.3');
      expect(version.build, 4);
      expect(version.identity, '1.0.3+4');
    });
  });
}
