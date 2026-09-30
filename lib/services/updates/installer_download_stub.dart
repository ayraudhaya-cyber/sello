import 'package:sello/services/updates/installer_download_update.dart';

Stream<InstallerDownloadUpdate> downloadInstaller(Uri url) {
  return Stream.error(
    UnsupportedError('In-app installer download is only available on Windows.'),
  );
}

Future<bool> openInstaller(String path) async => false;
