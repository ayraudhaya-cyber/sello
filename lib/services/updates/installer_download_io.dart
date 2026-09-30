import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sello/services/updates/installer_download_update.dart';

Stream<InstallerDownloadUpdate> downloadInstaller(Uri url) async* {
  final client = http.Client();
  IOSink? sink;
  try {
    final response = await client.send(http.Request('GET', url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      yield const InstallerDownloadUpdate(
        received: 0,
        error: 'Could not download the update.',
      );
      return;
    }

    final total = response.contentLength;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}sello-setup.exe');
    sink = file.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      yield InstallerDownloadUpdate(received: received, total: total);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    yield InstallerDownloadUpdate(
      received: received,
      total: total,
      filePath: file.path,
    );
  } catch (_) {
    yield const InstallerDownloadUpdate(
      received: 0,
      error: 'Could not download the update.',
    );
  } finally {
    await sink?.close();
    client.close();
  }
}

Future<bool> openInstaller(String path) async {
  if (!File(path).existsSync()) return false;
  await Process.start(path, const [], mode: ProcessStartMode.detached);
  return true;
}
