export 'browser_file_download_stub.dart'
    if (dart.library.io) 'browser_file_download_io.dart'
    if (dart.library.html) 'browser_file_download_web.dart';
