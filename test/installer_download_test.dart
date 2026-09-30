import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/updates/installer_download_update.dart';

void main() {
  test('download progress uses received bytes when the size is known', () {
    expect(downloadFraction(40, 100), 0.4);
    expect(downloadFraction(100, 100), 1);
    expect(downloadFraction(0, 100), 0);
  });

  test('download progress stays open when the size is missing', () {
    expect(downloadFraction(40, null), isNull);
    expect(downloadFraction(40, 0), isNull);
  });
}
