import 'package:package_info_plus/package_info_plus.dart';
import 'package:sello/shared/models/app_version.dart';

/// Reads the version encoded in the installed binary (`pubspec.yaml`).
abstract class AppVersionReader {
  Future<AppVersion> read();
}

class PackageInfoVersionReader implements AppVersionReader {
  const PackageInfoVersionReader();

  @override
  Future<AppVersion> read() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.fromNameAndBuild(info.version, info.buildNumber);
  }
}
