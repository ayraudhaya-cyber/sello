import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/widgets/inputs/sello_dropdown.dart';

void main() {
  group('selloCycleEnabledIndex', () {
    test('moves down and wraps', () {
      expect(
        selloCycleEnabledIndex(
          current: 0,
          count: 3,
          delta: 1,
          isEnabled: (_) => true,
        ),
        1,
      );
      expect(
        selloCycleEnabledIndex(
          current: 2,
          count: 3,
          delta: 1,
          isEnabled: (_) => true,
        ),
        0,
      );
    });

    test('moves up and wraps', () {
      expect(
        selloCycleEnabledIndex(
          current: 0,
          count: 3,
          delta: -1,
          isEnabled: (_) => true,
        ),
        2,
      );
    });

    test('skips disabled rows', () {
      expect(
        selloCycleEnabledIndex(
          current: 0,
          count: 4,
          delta: 1,
          isEnabled: (index) => index != 1,
        ),
        2,
      );
    });
  });
}
