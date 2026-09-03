import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/devtools/application/dev_experience_provider.dart';

void main() {
  group('DevExperienceConfig', () {
    test('does not require DX_* dart-defines', () {
      final config = DevExperienceConfig.fromEnv();

      expect(config.accounts, isEmpty);
      expect(config.defaultAccountId, isNull);
      expect(config.initialAutoLogin, isFalse);
    });
  });
}
