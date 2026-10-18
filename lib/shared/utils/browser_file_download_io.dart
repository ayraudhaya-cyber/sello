import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Saves [bytes] into the device Downloads folder.
///
/// Returns true when the file was saved on this device.
Future<bool> downloadBrowserFile({
  required List<int> bytes,
  required String filename,
  String mimeType = 'application/octet-stream',
}) async {
  final directory = await _downloadDirectory();
  final safeName = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final file = File('${directory.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return true;
}

Future<Directory> _downloadDirectory() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      if (!await downloads.exists()) {
        await downloads.create(recursive: true);
      }
      return downloads;
    }
  } catch (_) {
    // Some devices do not expose a public Downloads folder.
  }
  return getApplicationDocumentsDirectory();
}
